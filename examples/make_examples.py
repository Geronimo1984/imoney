"""Примеры выписок с вымышленными данными — повторяют макет настоящих выписок Т-Банка и Сбера,
чтобы на них можно было проверить загрузку в iMoney. Все имена, номера счетов, карт и договоров выдуманы.

Запуск: python3 examples/make_examples.py  (нужен reportlab: pip install reportlab)
"""
import os
import random
from datetime import datetime, timedelta

from reportlab.lib.pagesizes import A4
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas

HERE = os.path.dirname(os.path.abspath(__file__))
# Нужен шрифт со знаком ₽ и свободной лицензией: STIX Two Text (SIL OFL) есть в macOS
FONT_PATHS = ['/System/Library/Fonts/Supplemental/STIXTwoText.ttf',
              '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf']
FONT_BOLD_PATHS = ['/System/Library/Fonts/Supplemental/Arial Bold.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf']

OWNER = 'Иванова Анна Сергеевна'
TODAY = datetime(2026, 10, 27, 18, 0)


def register_fonts():
    regular = next(p for p in FONT_PATHS if os.path.exists(p))
    bold = next((p for p in FONT_BOLD_PATHS if os.path.exists(p)), regular)
    pdfmetrics.registerFont(TTFont('R', regular))
    pdfmetrics.registerFont(TTFont('B', bold))


def money_ru(value, sign=False):
    """89 055,16 — как у Сбера."""
    s = f'{abs(value):,.2f}'.replace(',', ' ').replace('.', ',')
    return ('+' if value > 0 and sign else '') + s


def money_tb(value):
    """-1 000.00 ₽ — как у Т-Банка."""
    s = f'{abs(value):,.2f}'.replace(',', ' ')
    return ('+' if value > 0 else '-') + s + ' ₽'


# MARK: операции

def tbank_operations():
    rnd = random.Random(7)
    ops = []
    def add(dt, amount, desc, card='1234'):
        ops.append((dt, amount, desc, card))
    start = TODAY - timedelta(days=60)
    shops = [('Оплата в PYATEROCHKA Moscow RUS', 300, 1800), ('Оплата в MAGNIT MM Moscow RUS', 250, 1500),
             ('Оплата в VKUSVILL Moscow RUS', 400, 2200), ('Оплата в STARS COFFEE Moscow RUS', 190, 420),
             ('Оплата в YANDEX*4121*GO Moskva RUS', 260, 900), ('Оплата в Яндекс Еда', 600, 1700),
             ('Оплата в OZON.RU Moscow RUS', 700, 4500), ('Оплата в APTEKA RIGLA Moscow RUS', 300, 1900)]
    d = start
    while d < TODAY:
        for _ in range(rnd.randint(1, 3)):
            name, lo, hi = rnd.choice(shops)
            add(d.replace(hour=rnd.randint(8, 22), minute=rnd.randint(0, 59)), -float(rnd.randint(lo, hi)) - rnd.choice([0, 0.5, 0.99]), name)
        d += timedelta(days=1)
    for month in (9, 10):
        add(datetime(2026, month, 5, 12, 10), 40000.0, 'Пополнение. Сбербанк')
        add(datetime(2026, month, 9, 9, 0), -399.0, 'Оплата в YANDEX PLUS Moscow RUS')
        add(datetime(2026, month, 7, 10, 0), -650.0, 'Оплата в MTS Moscow RUS')
        add(datetime(2026, month, 10, 11, 0), -5000.0, 'Пополнение Кубышки')
        add(datetime(2026, month, 15, 19, 30), -3000.0, 'Внешний перевод по номеру телефона +79000000000')
        add(datetime(2026, month, 3, 8, 0), float(rnd.randint(900, 1500)), 'Кэшбэк за покупки')
    add(datetime(2026, 10, 18, 16, 0), 2390.0, 'Отмена операции оплаты OZON.RU Moscow RUS')
    add(datetime(2026, 10, 21, 20, 0), -4800.0, 'Оплата в Фитнес-клуб Спорт Москва')
    return sorted(ops, key=lambda o: o[0], reverse=True)


def sber_operations():
    ops = []
    for month in (9, 10):
        ops.append((datetime(2026, month, 5, 10, 0), 95000.0, 'Прочие поступления', 'Зачисление заработной платы. ООО «Ромашка»', '-'))
        ops.append((datetime(2026, month, 5, 12, 5), -40000.0, 'Перевод с карты', 'Перевод на карту Т-Банк', '0000'))
        ops.append((datetime(2026, month, 1, 9, 0), -35000.0, 'Перевод с карты', 'Перевод для Петрова П', '0000'))
        ops.append((datetime(2026, month, 12, 13, 0), -6480.0, 'Коммунальные платежи, связь, интернет', 'ЖКУ Москва ЕПД', '0000'))
        ops.append((datetime(2026, month, 26, 9, 30), -5000.0, 'Прочие операции', 'Погашение кредита по договору', '-'))
        ops.append((datetime(2026, month, 18, 18, 0), -2315.99, 'Супермаркеты', 'AUCHAN MOSCOW RUS', '0000'))
    ops.append((datetime(2026, 10, 20, 15, 0), -3400.0, 'Здоровье и красота', 'Клиника Медицина Плюс', '0000'))
    return sorted(ops, key=lambda o: o[0], reverse=True)


# MARK: Сбер — «Выписка по платёжному счёту»

def make_sber(path):
    ops = sber_operations()
    c = canvas.Canvas(path, pagesize=A4)
    W, H = A4
    first_page = True
    balance = 12_000.0 + sum(-o[1] for o in ops)  # остаток до первой операции периода
    running = {}
    b = balance
    for o in sorted(ops, key=lambda x: x[0]):
        b += o[1]
        running[id(o)] = b

    def header():
        c.setFont('R', 9)
        c.drawString(171, 813, '900 www.sberbank.ru')
        c.drawString(171, 797, 'ул. Вавилова, д. 19, Москва, 117312')
        c.drawString(452, 813, 'Заказано в СберБанк Онлайн')
        c.setFont('B', 18)
        c.drawString(45, 762, 'Выписка по платёжному счёту')
        c.setFont('R', 10)
        c.drawString(45, 740, 'За период 01.09.2026 — 27.10.2026')
        c.setFont('R', 9)
        c.drawString(57, 705, 'Владелец счёта')
        c.drawString(57, 693, OWNER)
        for y, k, v in [(668, 'Номер счёта', '40817 810 0 0000 0000000'), (654, 'Карты, привязанные к счёту', 'MasterCard Сберкарта •• 0000'),
                        (640, 'Валюта', 'Российский рубль'), (626, 'Дата открытия счёта', '01.02.2020')]:
            c.drawString(57, y, k)
            c.drawString(195, y, v)
        c.setFont('B', 12)
        c.drawString(45, 572, 'Расшифровка операций')
        c.setFont('R', 8)
        c.drawString(45, 546, 'ДАТА ОПЕРАЦИИ (МСК)')
        c.drawString(152, 546, 'КАТЕГОРИЯ')
        c.drawString(370, 546, 'СУММА В ВАЛЮТЕ СЧЁТА')
        c.drawString(490, 546, 'ОСТАТОК СРЕДСТВ')
        c.drawString(45, 532, 'Дата обработки')
        c.drawString(45, 522, 'и код авторизации')
        c.drawString(152, 532, 'Описание операции')

    header()
    y = 500
    auth = random.Random(3)
    for o in ops:
        if y < 120:
            c.setFont('R', 8)
            c.drawString(45, 60, 'Продолжение на следующей странице')
            c.showPage()
            y = 780
        dt, amount, category, desc, card = o
        c.setFont('R', 9)
        c.drawString(45, y, dt.strftime('%d.%m.%Y'))
        c.drawString(102, y, dt.strftime('%H:%M'))
        c.drawString(152, y, category)
        c.drawRightString(470, y, money_ru(amount, sign=True))
        c.drawRightString(560, y, money_ru(running[id(o)]))
        c.drawString(45, y - 11, dt.strftime('%d.%m.%Y'))
        c.drawString(102, y - 11, f'{auth.randint(100000, 999999)}')
        tail = 'Операция по карте ****0000' if card != '-' else 'Операция по счёту ****0000'
        c.drawString(152, y - 11, f'{desc}. {tail}'[:70])
        y -= 38
    c.setFont('R', 7)
    c.drawString(45, 80, 'ПРИМЕР ДЛЯ ПРОВЕРКИ iMoney. Все данные вымышлены. Не является банковским документом.')
    c.save()


# MARK: Т-Банк — «Справка о движении средств»

def make_tbank(path):
    ops = tbank_operations()
    c = canvas.Canvas(path, pagesize=A4)

    def header():
        c.setFont('R', 8)
        c.drawString(314, 796, 'АКЦИОНЕРНОЕ ОБЩЕСТВО «ТБАНК»')
        c.drawString(314, 786, 'РОССИЯ, 127287, МОСКВА, УЛ. 2-Я ХУТОРСКАЯ, Д. 38А, СТР. 26')
        c.setFont('B', 20)
        c.drawString(56, 730, 'Справка о движении средств')
        c.setFont('R', 9)
        c.drawString(56, 705, 'Исх. № 00000000')
        c.drawString(492, 705, TODAY.strftime('%d.%m.%Y'))
        c.drawString(56, 684, OWNER)
        c.drawString(56, 666, 'Адрес места жительства: 000000, г. Москва, ул. Примерная, д. 1, кв. 1')
        c.setFont('B', 14)
        c.drawString(56, 638, 'О продукте')
        c.setFont('R', 9)
        c.drawString(56, 614, 'Дата заключения договора: 01.01.2021')
        c.drawString(56, 596, 'Номер договора: 0000000000')
        c.drawString(56, 578, 'Номер лицевого счета: 40817810000000000000')
        c.setFont('B', 14)
        c.drawString(56, 538, 'Движение средств за период с 27.08.2026 по 27.10.2026')

    def table_head(y):
        c.setFont('R', 9)
        for x, a, b in [(56, 'Дата и время', 'операции'), (126, 'Дата', 'списания'), (199, 'Сумма в валюте', 'операции'),
                        (294, 'Сумма операции', 'в валюте карты'), (389, 'Описание', 'операции'), (499, 'Номер', 'карты')]:
            c.drawString(x, y, a)
            c.drawString(x, y - 11, b)

    header()
    table_head(512)
    y = 485
    for dt, amount, desc, card in ops:
        words, lines, line = desc.split(), [], ''
        for w in words:
            if len(line) + len(w) + 1 > 20 and line:
                lines.append(line)
                line = w
            else:
                line = (line + ' ' + w).strip()
        lines.append(line)
        height = 25 + 11 * max(len(lines) - 2, 0)
        if y - height < 90:
            c.showPage()
            table_head(800)
            y = 773
        posted = dt + timedelta(minutes=random.Random(dt.minute).randint(0, 90))
        c.setFont('R', 9)
        c.drawString(56, y, dt.strftime('%d.%m.%Y'))
        c.drawString(56, y - 11, dt.strftime('%H:%M'))
        c.drawString(126, y, posted.strftime('%d.%m.%Y'))
        c.drawString(126, y - 11, posted.strftime('%H:%M'))
        c.drawString(199, y, money_tb(amount))
        c.drawString(294, y, money_tb(amount))
        for i, l in enumerate(lines):
            c.drawString(389, y - 11 * i, l)
        c.drawString(499, y, card)
        y -= height
    income = sum(o[1] for o in ops if o[1] > 0)
    spent = -sum(o[1] for o in ops if o[1] < 0)
    if y < 140:
        c.showPage()
        y = 800
    c.setFont('R', 10)
    c.drawString(56, y - 20, f'Пополнения: {money_ru(income)} ₽')
    c.drawString(56, y - 35, f'Расходы: {money_ru(spent)} ₽')
    c.setFont('R', 7)
    c.drawString(56, 50, 'ПРИМЕР ДЛЯ ПРОВЕРКИ iMoney. Все данные вымышлены. Не является банковским документом.')
    c.save()
    return income, spent


def make_tbank_csv(path):
    rows = ['"Дата операции";"Дата платежа";"Номер карты";"Статус";"Сумма операции";"Валюта операции";"Сумма платежа";'
            '"Валюта платежа";"Кэшбэк";"Категория";"MCC";"Описание";"Бонусы (включая кэшбэк)";"Округление на инвесткопилку";'
            '"Сумма операции с округлением"']
    cats = {'PYATEROCHKA': ('Супермаркеты', '5411'), 'MAGNIT': ('Супермаркеты', '5411'), 'VKUSVILL': ('Супермаркеты', '5411'),
            'COFFEE': ('Фастфуд', '5814'), 'YANDEX*4121': ('Такси', '4121'), 'Еда': ('Фастфуд', '5814'),
            'OZON': ('Различные товары', '5399'), 'RIGLA': ('Аптеки', '5912'), 'Фитнес': ('Спорттовары', '7997')}
    for dt, amount, desc, card in tbank_operations()[:40]:
        cat, mcc = next((v for k, v in cats.items() if k in desc), ('', ''))
        a = f'{amount:.2f}'.replace('.', ',')
        rows.append(f'"{dt:%d.%m.%Y %H:%M:%S}";"{dt:%d.%m.%Y}";"*{card}";"OK";"{a}";"RUB";"{a}";"RUB";"";"{cat}";"{mcc}";'
                    f'"{desc.replace("Оплата в ", "")}";"0,00";"0,00";"{a.lstrip("-")}"')
    with open(path, 'wb') as f:
        f.write(('\n'.join(rows) + '\n').encode('cp1251'))


if __name__ == '__main__':
    register_fonts()
    make_sber(os.path.join(HERE, 'Пример — выписка Сбера.pdf'))
    inc, sp = make_tbank(os.path.join(HERE, 'Пример — справка Т-Банка.pdf'))
    make_tbank_csv(os.path.join(HERE, 'Пример — операции Т-Банка.csv'))
    print(f'Т-Банк: пополнения {inc:.2f}, расходы {sp:.2f}')
