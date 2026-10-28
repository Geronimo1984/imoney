import XCTest

/// Проверяет основные сценарии: вкладки, фильтр, смена категории, загрузка выписки, удаление.
final class TapTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-light", "-design=system"] + args
        app.launch()
        return app
    }

    func testTabsSwitch() {
        let app = launch([])
        for tab in ["Операции", "План", "Счета", "Сводка"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.navigationBars[tab].waitForExistence(timeout: 3), "Не открылась вкладка \(tab)")
        }
    }

    func testFilterMenu() {
        let app = launch(["-tab=operations"])
        app.navigationBars["Операции"].buttons["Фильтровать"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["Доходы"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "заработной")).firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["STARS COFFEE"].exists)
    }

    func testChangeCategoryFromDetail() {
        let app = launch(["-tab=operations", "-edit"])
        XCTAssertTrue(app.navigationBars["Операция"].waitForExistence(timeout: 3))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Категория")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Категория"].waitForExistence(timeout: 3))
        let education = app.buttons["Образование"].firstMatch
        for _ in 0..<4 where !education.isHittable { app.swipeUp() }
        education.tap()
        app.navigationBars["Категория"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Образование")).firstMatch.waitForExistence(timeout: 3),
                      "Категория не сменилась")
    }

    func testImportSheetShowsResult() {
        // Пример выписки из репозитория: examples/Пример — операции Т-Банка.csv
        let sample = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("examples/Пример — операции Т-Банка.csv").path
        let app = launch(["-import=" + sample])
        XCTAssertTrue(app.navigationBars["Выписка загружена"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Добавлено 40 операций"].exists)
        app.buttons["Готово"].tap()
        XCTAssertFalse(app.navigationBars["Выписка загружена"].waitForExistence(timeout: 1))
    }

    func testDeleteAllAsksFirst() {
        let app = launch(["-tab=accounts"])
        let delete = app.buttons["Удалить все данные"]
        for _ in 0..<4 where !delete.isHittable { app.swipeUp() }
        delete.tap()
        XCTAssertTrue(app.buttons["Удалить все данные"].firstMatch.waitForExistence(timeout: 2))
        // «Отмена» в листе действий: данные остаются
        app.buttons["Отмена"].tap()
        app.tabBars.buttons["Сводка"].tap()
        XCTAssertTrue(app.staticTexts["ПОТРАЧЕНО"].waitForExistence(timeout: 3))
    }

    func testSwitchDesignBothWays() {
        let app = launch(["-tab=accounts"])
        let glossy = app.buttons["Оформление: Глянцевое"]
        for _ in 0..<4 where !glossy.isHittable { app.swipeUp() }
        glossy.tap()
        // Глянцевое: своя панель вкладок, мы остались на экране «Выписки» с переключателем
        XCTAssertTrue(app.buttons["Загрузить выписку"].waitForExistence(timeout: 3), "Не включилось глянцевое оформление")
        XCTAssertFalse(app.tabBars.firstMatch.exists)

        let system = app.buttons["Оформление: Системное"]
        for _ in 0..<5 where !system.isHittable { app.swipeUp() }
        system.tap()
        XCTAssertTrue(app.tabBars.buttons["Счета"].waitForExistence(timeout: 3), "Не вернулось системное оформление")
        XCTAssertTrue(app.navigationBars["Счета"].exists)
    }

    func testAutoPlanApplies() {
        let app = launch(["-tab=plan"])
        app.buttons["Распределить автоматически"].tap()
        XCTAssertTrue(app.navigationBars["Предлагаемый план"].waitForExistence(timeout: 3))
        app.navigationBars["Предлагаемый план"].buttons["Применить"].tap()
        XCTAssertTrue(app.navigationBars["План"].waitForExistence(timeout: 3))
    }

    func testAddRecurringPayment() {
        let app = launch(["-tab=plan"])
        let add = app.buttons["Добавить платёж"]
        for _ in 0..<8 where !add.isHittable { app.swipeUp() }
        add.tap()
        XCTAssertTrue(app.navigationBars["Новый платёж"].waitForExistence(timeout: 3))
        let title = app.textFields["Название"]
        title.tap()
        title.typeText("Спортзал")
        let amount = app.textFields["0"]
        amount.tap()
        amount.typeText("2500")
        app.navigationBars["Новый платёж"].buttons["Добавить"].tap()
        // Список отсортирован по дате платежа — новый может оказаться выше видимой части
        let added = app.staticTexts["Спортзал"]
        for _ in 0..<6 where !added.waitForExistence(timeout: 1) { app.swipeDown() }
        XCTAssertTrue(added.exists, "Платёж не появился в списке")
    }

    func testAddDebt() {
        let app = launch(["-tab=plan"])
        let all = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Все кредиты и рассрочки")).firstMatch
        for _ in 0..<4 where !all.isHittable { app.swipeUp() }
        all.tap()
        XCTAssertTrue(app.navigationBars["Кредиты и рассрочки"].waitForExistence(timeout: 3))
        app.buttons["Добавить кредит или рассрочку"].tap()
        XCTAssertTrue(app.navigationBars["Новый долг"].waitForExistence(timeout: 3))
        let title = app.textFields["Название, например «Ипотека»"]
        title.tap()
        title.typeText("Кредитка")
        let fields = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "0"))
        fields.element(boundBy: 1).tap()
        fields.element(boundBy: 1).typeText("50000")
        fields.element(boundBy: 2).tap()
        fields.element(boundBy: 2).typeText("5000")
        app.navigationBars["Новый долг"].buttons["Добавить"].tap()
        XCTAssertTrue(app.staticTexts["Кредитка"].waitForExistence(timeout: 3), "Долг не появился в списке")
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        if let dir = ProcessInfo.processInfo.environment["SHOTS"] {
            try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + name + ".png"))
        }
    }

    private func open(_ app: XCUIApplication, _ prefix: String) {
        let e = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        for _ in 0..<6 where !(e.exists && e.isHittable) { app.swipeUp() }
        // Дождаться конца инерции прокрутки — иначе нажатие только остановит список
        sleep(1)
        e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    func testTaxDeduction() {
        let app = launch([])
        open(app, "Вернуть")
        XCTAssertTrue(app.navigationBars["Налоговый вычет"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Лечение"].exists || app.staticTexts["Лекарства"].exists || app.staticTexts["Спорт и фитнес"].exists)
        shot(app, "tax")
    }

    func testCashback() {
        let app = launch([])
        open(app, "+")
        XCTAssertTrue(app.navigationBars["Кэшбэк"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Проценты на остаток"].exists, "Нет разбивки на кэшбэк и проценты")
        shot(app, "cashback")
    }

    func testRecap() {
        let app = launch([])
        open(app, "Итоги")
        XCTAssertTrue(app.navigationBars["Итоги месяца"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Поделиться"].waitForExistence(timeout: 3))
        // Демо-данные — за текущий месяц: итоги за него, а не за прошлый
        XCTAssertTrue(app.staticTexts["ИТОГИ НА СЕГОДНЯ"].exists, "Итоги не за выбранный месяц")
        shot(app, "recap")
    }

    func testPayoffStrategy() {
        let app = launch(["-tab=plan"])
        open(app, "Стратегия погашения")
        XCTAssertTrue(app.navigationBars["Стратегия погашения"].waitForExistence(timeout: 3))
        shot(app, "payoff")
        app.buttons["Снежный ком"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "самый маленький")).firstMatch.waitForExistence(timeout: 2))
    }

    func testAddGoal() {
        let app = launch(["-tab=plan"])
        open(app, "Новая цель")
        XCTAssertTrue(app.navigationBars["Новая цель"].waitForExistence(timeout: 3))
        let title = app.textFields["Например, «Отпуск»"]
        title.tap(); title.typeText("Ноутбук")
        let fields = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "0"))
        fields.element(boundBy: 0).tap(); fields.element(boundBy: 0).typeText("90000")
        app.navigationBars["Новая цель"].buttons["Добавить"].tap()
        XCTAssertTrue(app.staticTexts["Ноутбук"].waitForExistence(timeout: 3), "Цель не появилась")
        shot(app, "goals")
    }

    func testOnboardingWalkthrough() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding", "-demo", "-light", "-design=system"]
        app.launch()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Добро пожаловать")).firstMatch.waitForExistence(timeout: 3))
        // Страницы лежат рядом, кнопок «Продолжить» несколько — жмём видимую
        for _ in 0..<4 {
            app.buttons.matching(identifier: "Продолжить").allElementsBoundByIndex.first { $0.isHittable }?.tap()
            sleep(1)
        }
        XCTAssertTrue(app.staticTexts["Всё готово"].waitForExistence(timeout: 2))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Начать")).firstMatch.tap()
        XCTAssertTrue(app.tabBars.buttons["Сводка"].waitForExistence(timeout: 3), "Обучение не закрылось")
    }

    func testCreditCardOperations() {
        let app = launch(["-tab=plan"])
        open(app, "Кредитная карта")
        XCTAssertTrue(app.navigationBars["Кредитная карта"].waitForExistence(timeout: 3))
        let section = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Операции по карте")).firstMatch
        for _ in 0..<6 where !section.exists { app.swipeUp() }
        XCTAssertTrue(section.exists, "Нет раздела с операциями по кредитке")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Погашение кредитки")).firstMatch.exists)
        shot(app, "credit_card_ops")
    }

    func testAutoImportFolderPicker() {
        let app = launch(["-tab=accounts"])
        let toggle = app.switches.matching(NSPredicate(format: "label CONTAINS %@", "Загружать новые выписки")).firstMatch
        for _ in 0..<6 where !toggle.isHittable { app.swipeUp() }
        if (toggle.value as? String) != "1" { toggle.switches.firstMatch.tap() }
        let choose = app.buttons["Выбрать другую папку…"]
        for _ in 0..<3 where !choose.isHittable { app.swipeUp() }
        sleep(1)
        choose.tap()
        let openButton = app.buttons.matching(NSPredicate(format: "label IN %@", ["Open", "Открыть"])).firstMatch
        // Выбор папки — отдельный процесс, его кнопки появляются не сразу
        let opened = openButton.waitForExistence(timeout: 15)
        // Выбор папки — отдельный процесс, снимок окна приложения его не видит
        if let dir = ProcessInfo.processInfo.environment["SHOTS"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + "folder_picker.png"))
        }
        XCTAssertTrue(opened, "Не открылся выбор папки")
    }

    func testAddPlannedExpense() {
        let app = launch(["-tab=plan"])
        let add = app.buttons["Добавить расход"]
        for _ in 0..<10 where !add.isHittable { app.swipeUp() }
        add.tap()
        XCTAssertTrue(app.navigationBars["Новый расход"].waitForExistence(timeout: 3))
        let title = app.textFields["Название"]
        title.tap()
        title.typeText("Ремонт ноутбука")
        let amount = app.textFields["0"]
        amount.tap()
        amount.typeText("12000")
        app.navigationBars["Новый расход"].buttons["Добавить"].tap()
        let added = app.staticTexts["Ремонт ноутбука"]
        for _ in 0..<6 where !added.waitForExistence(timeout: 1) { app.swipeDown() }
        XCTAssertTrue(added.exists, "Расход не появился в списке")
        XCTAssertTrue(app.staticTexts["Разовые расходы"].exists || app.staticTexts["РАЗОВЫЕ РАСХОДЫ"].exists)
        shot(app, "planned")
    }

    func testSummaryFollowsPeriod() {
        let app = launch([])
        let month = app.staticTexts["Кэшбэк и проценты за месяц"]
        for _ in 0..<3 where !month.exists { app.swipeUp() }
        XCTAssertTrue(month.exists)
        for _ in 0..<3 { app.swipeDown() }
        app.buttons["Год"].tap()
        let year = app.staticTexts["Кэшбэк и проценты за год"]
        for _ in 0..<3 where !year.exists { app.swipeUp() }
        XCTAssertTrue(year.exists, "«Полезное» не пересчиталось за год")
        shot(app, "summary_year")
    }
}
