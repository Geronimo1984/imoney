import Foundation
import PDFKit

/// Строка выписки до категоризации.
struct ParsedRow: Hashable {
    var date: Date
    var amount: Decimal
    var currency = "RUB"
    var card = ""
    var title: String
    var bankCategory = ""
    var mcc = ""
}

struct ParseResult {
    var bank: Bank
    var rows: [ParsedRow]
    /// Строки, похожие на операции, которые не удалось разобрать.
    var skipped: Int
    /// Владелец счёта из шапки выписки — по нему узнаём переводы самому себе.
    var owner: String? = nil
}

enum StatementError: LocalizedError {
    case unreadable, unknownFormat, empty

    var errorDescription: String? {
        switch self {
        case .unreadable:    return "Не удалось прочитать файл."
        case .unknownFormat: return "Формат выписки не распознан. Подходят справка о движении средств Т-Банка (PDF или CSV) и выписка Сбера (PDF)."
        case .empty:         return "В выписке не найдено ни одной операции."
        }
    }
}

enum StatementParser {

    static func parse(url: URL) throws -> ParseResult {
        let ext = url.pathExtension.lowercased()
        let result: ParseResult
        if ext == "pdf" {
            guard let doc = PDFDocument(url: url) else { throw StatementError.unreadable }
            result = try parsePDF(doc)
        } else {
            guard let data = try? Data(contentsOf: url) else { throw StatementError.unreadable }
            result = try parseCSV(decode(data))
        }
        guard !result.rows.isEmpty else { throw StatementError.empty }
        return result
    }

    /// Т-Банк отдаёт CSV в Windows-1251, остальные — чаще в UTF-8.
    static func decode(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .windowsCP1251) { return s }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: CSV (Т-Банк и любой банк с понятными заголовками)

    static func parseCSV(_ text: String) throws -> ParseResult {
        let lines = text.replacingOccurrences(of: "\u{FEFF}", with: "")
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard let headerIndex = lines.firstIndex(where: {
            let l = $0.lowercased()
            return l.contains("дата") && l.contains("сумма")
        }) else { throw StatementError.unknownFormat }

        let headerLine = lines[headerIndex]
        let delimiter: Character = headerLine.filter { $0 == ";" }.count >= headerLine.filter { $0 == "," }.count ? ";" : ","
        let header = splitCSV(headerLine, delimiter).map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        func column(_ names: [String]) -> Int? {
            for name in names {
                if let i = header.firstIndex(where: { $0 == name }) { return i }
            }
            for name in names {
                if let i = header.firstIndex(where: { $0.contains(name) }) { return i }
            }
            return nil
        }

        guard let dateCol = column(["дата операции", "дата и время операции", "дата"]),
              let amountCol = column(["сумма платежа", "сумма в валюте счета", "сумма операции", "сумма"])
        else { throw StatementError.unknownFormat }

        let currencyCol = column(["валюта платежа", "валюта"])
        let statusCol = column(["статус"])
        let categoryCol = column(["категория"])
        let mccCol = column(["mcc"])
        let titleCol = column(["описание", "назначение", "контрагент", "получатель"])
        let cardCol = column(["номер карты", "карта"])

        let joined = header.joined(separator: "|")
        let isTBank = joined.contains("mcc") && joined.contains("кэшбэк") && joined.contains("дата платежа")
        let bank: Bank = isTBank ? .tbank : .other

        var rows: [ParsedRow] = []
        var skipped = 0
        for line in lines[(headerIndex + 1)...] {
            let cells = splitCSV(line, delimiter)
            func cell(_ i: Int?) -> String {
                guard let i, i < cells.count else { return "" }
                return cells[i].trimmingCharacters(in: .whitespaces)
            }
            if let statusCol, cell(statusCol).uppercased() == "FAILED" { continue }
            guard let date = parseDate(cell(dateCol)), let amount = parseAmount(cell(amountCol)) else {
                skipped += 1
                continue
            }
            let title = cell(titleCol)
            rows.append(ParsedRow(
                date: date,
                amount: amount,
                currency: cell(currencyCol).isEmpty ? "RUB" : cell(currencyCol),
                card: cell(cardCol),
                title: title.isEmpty ? cell(categoryCol) : title,
                bankCategory: cell(categoryCol),
                mcc: cell(mccCol)))
        }
        return ParseResult(bank: bank, rows: rows, skipped: skipped)
    }

    static func splitCSV(_ line: String, _ delimiter: Character) -> [String] {
        var cells: [String] = []
        var current = ""
        var quoted = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if quoted, i + 1 < chars.count, chars[i + 1] == "\"" {
                    current.append("\"")
                    i += 1
                } else {
                    quoted.toggle()
                }
            } else if c == delimiter && !quoted {
                cells.append(current)
                current = ""
            } else {
                current.append(c)
            }
            i += 1
        }
        cells.append(current)
        return cells
    }

    // MARK: PDF (Сбер; Т-Банк — по возможности)

    static func parsePDFText(_ text: String) throws -> ParseResult {
        let lower = text.lowercased()
        if lower.contains("сбербанк") || (lower.contains("сбер") && lower.contains("остаток средств")) {
            return parseSberText(text)
        }
        if lower.contains("тинькофф") || lower.contains("т-банк") || lower.contains("тбанк") {
            return parseTBankPDFText(text)
        }
        let sber = parseSberText(text)
        if !sber.rows.isEmpty { return sber }
        let tbank = parseTBankPDFText(text)
        if !tbank.rows.isEmpty { return tbank }
        throw StatementError.unknownFormat
    }

    // MARK: PDF по координатам

    /// Кусок текста на странице с положением: x — левый край, y — середина строки (ось y вверх).
    struct Fragment {
        var text: String
        var x: CGFloat
        var y: CGFloat
    }

    /// Текст таблиц PDF нельзя читать подряд: колонки перемешиваются.
    /// Поэтому берём строки-фрагменты с координатами и собираем таблицу по колонкам.
    static func fragments(_ page: PDFPage) -> [Fragment] {
        guard let all = page.selection(for: page.bounds(for: .mediaBox)) else { return [] }
        return all.selectionsByLine().compactMap { line in
            // В PDF «й» и «ё» бывают разложены на букву и отдельный значок — собираем обратно
            guard let text = line.string?.precomposedStringWithCanonicalMapping
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            let r = line.bounds(for: page)
            return Fragment(text: text, x: r.minX, y: r.midY)
        }
    }

    static func parsePDF(_ doc: PDFDocument) throws -> ParseResult {
        let pages = (0..<doc.pageCount).compactMap { doc.page(at: $0) }.map(fragments)
        // Банк — только по шапке первой страницы: в описаниях операций встречаются названия других банков
        let text = (pages.first ?? []).filter { $0.y > 500 }.map(\.text).joined(separator: "\n").lowercased()
        let owner = findOwner(pages.first ?? [])
        var result: ParseResult
        if text.contains("sberbank") || text.contains("сбербанк") {
            result = parseSberPDF(pages)
        } else if text.contains("тбанк") || text.contains("т-банк") || text.contains("тинькофф") || text.contains("tbank") {
            result = parseTBankPDF(pages)
        } else {
            // Неизвестный банк: пробуем оба макета, затем старый разбор по тексту
            let sber = parseSberPDF(pages)
            let tbank = parseTBankPDF(pages)
            result = sber.rows.count >= tbank.rows.count ? sber : tbank
            if result.rows.isEmpty {
                var plain = ""
                for i in 0..<doc.pageCount { plain += (doc.page(at: i)?.string ?? "") + "\n" }
                result = try parsePDFText(plain)
            }
        }
        result.owner = owner
        return result
    }

    /// ФИО владельца: первая строка из трёх-четырёх слов с заглавной буквы в начале документа.
    static func findOwner(_ frags: [Fragment]) -> String? {
        let pattern = #"^[А-ЯЁ][а-яё]+ [А-ЯЁ][а-яё]+ [А-ЯЁ][а-яё]+( [А-ЯЁа-яё][а-яё]+)?$"#
        return frags.sorted { $0.y > $1.y }
            .first { $0.text.range(of: pattern, options: .regularExpression) != nil }?.text
    }



    /// Видимая строка страницы: фрагменты на одной высоте, слева направо.
    /// На iPhone PDFKit сам склеивает строку таблицы, на Mac отдаёт колонки по отдельности — после склейки текст одинаковый.
    struct VisualLine {
        var text: String
        var y: CGFloat
    }

    static func visualLines(_ frags: [Fragment]) -> [VisualLine] {
        var groups: [[Fragment]] = []
        for f in frags.sorted(by: { $0.y > $1.y }) {
            if let first = groups.last?.first, abs(first.y - f.y) < 2 {
                groups[groups.count - 1].append(f)
            } else {
                groups.append([f])
            }
        }
        return groups.map { group in
            VisualLine(text: group.sorted { $0.x < $1.x }.map(\.text).joined(separator: " "),
                       y: group.map(\.y).reduce(0, +) / CGFloat(group.count))
        }
    }

    private static func firstMatch(_ text: String, _ regex: NSRegularExpression) -> [String]? {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, range: range) else { return nil }
        return (0..<m.numberOfRanges).map { n in
            Range(m.range(at: n), in: text).map { String(text[$0]) } ?? ""
        }
    }

    /// Выписка Сбера: строка «дата время категория сумма остаток»,
    /// ниже — «дата код_авторизации описание» и, может быть, продолжение описания.
    static func parseSberPDF(_ pages: [[Fragment]]) -> ParseResult {
        let money = #"\d{1,3}(?:[ \u00A0\u202F]\d{3})*,\d{2}"#
        let anchor = try! NSRegularExpression(
            pattern: #"^(\d{2}\.\d{2}\.\d{4})\s+(\d{2}:\d{2})\s+(.+?)\s+([+−-]?"# + money + #")(?:\s+"# + money + #")?\s*$"#)
        let detail = try! NSRegularExpression(pattern: #"^\d{2}\.\d{2}\.\d{4}\s+(?:\d{6}|[-–—])?\s*(.*)$"#)
        var rows: [ParsedRow] = []
        var skipped = 0
        for frags in pages {
            let lines = visualLines(frags)
            for (i, line) in lines.enumerated() {
                guard let g = firstMatch(line.text, anchor) else {
                    if line.text.range(of: #"^\d{2}\.\d{2}\.\d{4}\s+\d{2}:\d{2}"#, options: .regularExpression) != nil { skipped += 1 }
                    continue
                }
                guard let date = parseDate(g[1] + " " + g[2]), var amount = parseAmount(g[4]) else { skipped += 1; continue }
                // У Сбера списания без знака, зачисления — с «+»
                if !g[4].hasPrefix("+") && amount > 0 { amount = -amount }

                var parts: [String] = []
                for next in lines.dropFirst(i + 1) {
                    if (line.y - next.y > 40) || (firstMatch(next.text, anchor) != nil) { break }
                    if let d = firstMatch(next.text, detail) { parts.append(d[1]) } else { parts.append(next.text) }
                }
                let description = parts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                let card = description.range(of: #"\*{2,4}\d{4}"#, options: .regularExpression).map { String(description[$0]) } ?? ""
                let title = description
                    .replacingOccurrences(of: #"\.?\s*Операция по (карте|счету|счёту)\s*\*{2,4}\d{4}"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                rows.append(ParsedRow(date: date, amount: amount, card: card,
                                      title: title.isEmpty ? g[3] : title, bankCategory: g[3]))
            }
        }
        return ParseResult(bank: .sber, rows: rows, skipped: skipped)
    }

    /// Справка Т-Банка: строка «дата дата ±сумма ₽ ±сумма ₽ описание карта»,
    /// ниже — «время время продолжение описания» и, может быть, ещё строки описания.
    static func parseTBankPDF(_ pages: [[Fragment]]) -> ParseResult {
        let money = #"[+−-]?\s?\d{1,3}(?:[ \u00A0\u202F]\d{3})*[.,]\d{2}"#
        let anchor = try! NSRegularExpression(
            pattern: #"^(\d{2}\.\d{2}\.\d{4})\s+\d{2}\.\d{2}\.\d{4}\s+("# + money + #")\s*₽\s+("# + money + #")\s*₽\s*(.*?)(?:\s(\d{4}))?$"#)
        let times = try! NSRegularExpression(pattern: #"^(\d{2}:\d{2})\s+\d{2}:\d{2}\s*(.*)$"#)
        var rows: [ParsedRow] = []
        var skipped = 0
        for frags in pages {
            let lines = visualLines(frags)
            for (i, line) in lines.enumerated() {
                guard let g = firstMatch(line.text, anchor) else { continue }
                var time = "00:00"
                var parts = [g[4]]
                for next in lines.dropFirst(i + 1) {
                    if (line.y - next.y > 60) || (firstMatch(next.text, anchor) != nil) { break }
                    if let t = firstMatch(next.text, times) {
                        time = t[1]
                        parts.append(t[2])
                    } else if next.text.range(of: #"^\d{2}\.\d{2}\.\d{4}"#, options: .regularExpression) == nil {
                        parts.append(next.text)
                    } else {
                        break
                    }
                }
                // Сумма в валюте карты — третья колонка; если её нет, берём сумму операции
                guard let date = parseDate(g[1] + " " + time),
                      let amount = parseAmount(g[3]) ?? parseAmount(g[2]) else { skipped += 1; continue }
                let title = parts.filter { !$0.isEmpty }.joined(separator: " ")
                rows.append(ParsedRow(date: date, amount: amount, card: g[5].isEmpty ? "" : "*" + g[5], title: title))
            }
        }
        return ParseResult(bank: .tbank, rows: rows, skipped: skipped)
    }

    private static let money = #"\d{1,3}(?:[   ]\d{3})*,\d{2}"#

    /// Выписка Сбера: строка «дата время категория сумма остаток»,
    /// следом «дата код_авторизации описание операции».
    static func parseSberText(_ text: String) -> ParseResult {
        let anchor = try! NSRegularExpression(
            pattern: #"^(\d{2}\.\d{2}\.\d{4})\s+(\d{2}:\d{2})\s+(?:\d{6}\s+)?(.+?)\s+([+−-]?"# + money + #")(?:\s+"# + money + #")?\s*$"#)
        let detail = try! NSRegularExpression(pattern: #"^\d{2}\.\d{2}\.\d{4}\s+(?:\d{6}\s+|[-–—]\s+)?(.*)$"#)
        let looksLikeOperation = try! NSRegularExpression(pattern: #"^\d{2}\.\d{2}\.\d{4}\s+\d{2}:\d{2}"#)

        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var rows: [ParsedRow] = []
        var skipped = 0
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let range = NSRange(line.startIndex..., in: line)
            guard let m = anchor.firstMatch(in: line, range: range) else {
                if looksLikeOperation.firstMatch(in: line, range: range) != nil { skipped += 1 }
                i += 1
                continue
            }
            func g(_ n: Int) -> String {
                guard let r = Range(m.range(at: n), in: line) else { return "" }
                return String(line[r])
            }
            let category = g(3)
            let rawAmount = g(4)
            var amount = parseAmount(rawAmount) ?? 0
            // У Сбера списания без знака, зачисления — с «+».
            if !rawAmount.hasPrefix("+") && amount > 0 { amount = -amount }

            var description = ""
            var j = i + 1
            while j < lines.count, j <= i + 3 {
                let next = lines[j]
                let nextRange = NSRange(next.startIndex..., in: next)
                if anchor.firstMatch(in: next, range: nextRange) != nil || isSberNoise(next) { break }
                if let d = detail.firstMatch(in: next, range: nextRange), let r = Range(d.range(at: 1), in: next) {
                    description += (description.isEmpty ? "" : " ") + next[r]
                } else {
                    description += (description.isEmpty ? "" : " ") + next
                }
                j += 1
            }

            guard let date = parseDate(g(1) + " " + g(2)) else {
                skipped += 1
                i = j
                continue
            }
            let card = description.range(of: #"\*{2,4}\d{4}"#, options: .regularExpression).map { String(description[$0]) } ?? ""
            let title = description
                .replacingOccurrences(of: #"\.?\s*Операция по (карте|счету|счёту)\s*\*{2,4}\d{4}"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)

            rows.append(ParsedRow(date: date, amount: amount, card: card,
                                  title: title.isEmpty ? category : title, bankCategory: category))
            i = j
        }
        return ParseResult(bank: .sber, rows: rows, skipped: skipped)
    }

    private static func isSberNoise(_ line: String) -> Bool {
        let l = line.lowercased()
        let noise = ["продолжение на следующей", "страница", "дата операции", "дата обработки",
                     "категория", "сумма в валюте", "остаток", "итого", "выписка", "пао сбербанк",
                     "расшифровка", "реквизиты", "www.sberbank", "дата формирования"]
        return noise.contains { l.hasPrefix($0) }
    }

    /// PDF Т-Банка: «дата дата ±сумма ₽ ±сумма ₽ описание карта».
    static func parseTBankPDFText(_ text: String) -> ParseResult {
        let row = try! NSRegularExpression(
            pattern: #"^(\d{2}\.\d{2}\.\d{4})(?:\s+(\d{2}:\d{2}))?\s+\d{2}\.\d{2}\.\d{4}(?:\s+\d{2}:\d{2})?\s+([+−-]?\s?[\d  ]+[.,]\d{2})\s*₽\s+[+−-]?\s?[\d  ]+[.,]\d{2}\s*₽\s+(.+?)(?:\s+(\d{4}))?$"#)
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var rows: [ParsedRow] = []
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            guard let m = row.firstMatch(in: line, range: range) else { continue }
            func g(_ n: Int) -> String {
                guard let r = Range(m.range(at: n), in: line) else { return "" }
                return String(line[r])
            }
            let dateText = g(2).isEmpty ? g(1) : g(1) + " " + g(2)
            guard let date = parseDate(dateText), let amount = parseAmount(g(3)) else { continue }
            rows.append(ParsedRow(date: date, amount: amount, card: g(5), title: g(4)))
        }
        return ParseResult(bank: .tbank, rows: rows, skipped: 0)
    }

    // MARK: Числа и даты

    static func parseAmount(_ raw: String) -> Decimal? {
        var s = raw.replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "₽", with: "")
            .replacingOccurrences(of: "RUB", with: "")
            .replacingOccurrences(of: "руб.", with: "")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: ",", with: ".")
        if s.hasPrefix("+") { s.removeFirst() }
        guard !s.isEmpty, s.range(of: #"^-?\d+(\.\d+)?$"#, options: .regularExpression) != nil else { return nil }
        return Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static let dateFormatters: [DateFormatter] = [
        "dd.MM.yyyy HH:mm:ss", "dd.MM.yyyy HH:mm", "dd.MM.yyyy",
        "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd", "dd.MM.yy"
    ].map {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Moscow")
        f.dateFormat = $0
        return f
    }

    static func parseDate(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        for f in dateFormatters {
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}
