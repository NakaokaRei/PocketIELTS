import XCTest
import UIKit

@MainActor
final class PocketIELTSUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP", "--ui-testing", "--ui-reset"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
    }
    override func tearDown() {
        app.terminate()
        app = nil
        super.tearDown()
    }
    private func navigate(_ title: String, tag: Int) {
        if app.tabBars.buttons[title].exists { app.tabBars.buttons[title].tap() }
        else {
            if !app.buttons["navigation.\(tag)"].isHittable { XCUIDevice.shared.orientation = .landscapeLeft }
            XCTAssertTrue(app.buttons["navigation.\(tag)"].waitForExistence(timeout: 5))
            app.buttons["navigation.\(tag)"].tap()
        }
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func backgroundBrightness() -> Double {
        let image = XCUIScreen.main.screenshot().image.cgImage!
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: -CGFloat(image.width) * 0.03, y: -CGFloat(image.height) * 0.5)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Double(Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2])) / (3 * 255)
    }

    private func openReading() {
        let reading = app.buttons["home.skill.Reading"]
        XCTAssertTrue(reading.waitForExistence(timeout: 10)); reading.tap()
        let part = app.buttons["part.open.Reading / Section 1"]
        XCTAssertTrue(part.waitForExistence(timeout: 5)); part.tap()
    }

    func testManualVocabularyAndSeparateLibrary() {
        navigate("単語帳", tag: 2)
        app.buttons["vocabulary.add"].tap()
        let field = app.descendants(matching: .any).matching(identifier: "vocabulary.expression").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["vocabulary.saveManual"].isEnabled)
        field.tap(); field.typeText("resilient")
        if app.buttons["入力を完了"].exists { app.buttons["入力を完了"].tap() }
        capture("iphone-add-vocabulary")
        app.buttons["vocabulary.composeAI"].tap()
        XCTAssertTrue(app.staticTexts["resilient"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tutor.quick.0"].exists)
        app.buttons["完了"].tap()
        app.buttons["vocabulary.saveManual"].tap()
        XCTAssertTrue(app.staticTexts["resilient"].waitForExistence(timeout: 5))
        capture("iphone-my-vocabulary")
        XCTAssertFalse(app.buttons["vocabulary.flashcards"].exists)
        app.buttons["vocabulary.library"].tap()
        XCTAssertFalse(app.buttons["library.flashcards"].exists)
        XCTAssertFalse(app.buttons["すべての分野"].exists)
        XCTAssertTrue(app.staticTexts["accommodation"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["resilient"].exists)
        capture("iphone-word-library")
        app.buttons["library.level.2"].tap()
        let ask = app.buttons["library.ask.tenancy"]
        for _ in 0..<4 where !ask.isHittable { app.swipeUp() }
        ask.tap()
        XCTAssertTrue(app.staticTexts["tenancy"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(ja)", "--ui-testing"]
        app.launch(); navigate("単語帳", tag: 2)
        XCTAssertTrue(app.staticTexts["resilient"].waitForExistence(timeout: 5))
    }

    func testSectionsAvailableOnFirstNavigation() {
        app.terminate()
        app.launch()
        app.buttons["home.skill.Reading"].tap()
        for section in 1...3 {
            XCTAssertTrue(app.buttons["part.open.Reading / Section \(section)"].waitForExistence(timeout: 12))
        }
        capture("iphone-reading-sections")
        app.buttons["part.open.Reading / Section 1"].tap()
        XCTAssertTrue(app.staticTexts["Community services"].waitForExistence(timeout: 5))
    }

    func testOfflineLibraryOpensBundledReading() {
        let library = app.buttons["home.offline"]
        for _ in 0..<6 where !library.isHittable { app.swipeUp() }
        library.tap()
        let reading = app.buttons["offline.open.Reading / Section 1"]
        XCTAssertTrue(reading.waitForExistence(timeout: 5))
        capture("iphone-offline-library")
        reading.tap()
        XCTAssertTrue(app.staticTexts["Community services"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textViews["study.text.Reading / Section 1passage-0"].exists)
    }

    func testTapExpressionSaveAndReopenAfterRelaunch() {
        openReading()
        let passage = app.textViews["study.text.Reading / Section 1passage-0"]
        XCTAssertTrue(passage.waitForExistence(timeout: 5))
        passage.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 75, dy: 12)).tap()
        let save = app.menuItems["単語帳に追加"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(app.staticTexts["単語帳に保存しました"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP", "--ui-testing"]
        app.launch()
        navigate("単語帳", tag: 2)
        XCTAssertTrue(app.buttons["元の問題を復習"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP", "--ui-testing"]
        app.launch()
        navigate("単語帳", tag: 2)
        XCTAssertTrue(app.buttons["元の問題を復習"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["意味・メモを追加"].exists)
        app.buttons["vocabulary.askAI"].firstMatch.tap()
        XCTAssertTrue(app.buttons["tutor.quick.0"].waitForExistence(timeout: 5))
        app.buttons["tutor.quick.1"].tap()
        XCTAssertTrue((app.descendants(matching: .any).matching(identifier: "tutor.input").firstMatch.value as? String ?? "").contains("使い方"))
        app.buttons["完了"].tap()
        capture("iphone-vocabulary-actions")
        app.cells.containing(.button, identifier: "vocabulary.askAI").firstMatch.swipeLeft()
        capture("iphone-vocabulary-swipe")
        app.buttons["削除"].firstMatch.tap()
        XCTAssertTrue(app.alerts["この単語を削除しますか？"].waitForExistence(timeout: 5))
        app.alerts.buttons["キャンセル"].tap()
        XCTAssertTrue(app.buttons["vocabulary.askAI"].exists)
        app.cells.containing(.button, identifier: "vocabulary.askAI").firstMatch.swipeLeft()
        app.buttons["削除"].firstMatch.tap()
        XCTAssertTrue(app.alerts["この単語を削除しますか？"].waitForExistence(timeout: 5))
        app.alerts.buttons["削除"].tap()
        XCTAssertTrue(app.staticTexts["単語帳は空です"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        navigate("単語帳", tag: 2)
        XCTAssertTrue(app.staticTexts["単語帳は空です"].waitForExistence(timeout: 5))
    }
    func testSelectionDismissesOutsideAndAsksDirectly() {
        openReading()
        let passage = app.textViews["study.text.Reading / Section 1passage-0"]
        let word = passage.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 75, dy: 12))
        word.tap()
        XCTAssertTrue(app.menuItems["単語帳に追加"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["テキスト選択"].exists)
        app.staticTexts["Community services"].tap()
        XCTAssertTrue(app.menuItems["単語帳に追加"].waitForNonExistence(timeout: 5))
        word.press(forDuration: 1)
        XCTAssertTrue(app.menuItems["AIに質問"].waitForExistence(timeout: 5))
        app.menuItems["AIに質問"].tap()
        XCTAssertFalse(app.navigationBars["テキスト選択"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "tutor.input").firstMatch.waitForExistence(timeout: 5))
        let subject = app.staticTexts["tutor.subject"]
        XCTAssertTrue(subject.isHittable, "The selected text must be visible without expanding anything")
        XCTAssertFalse(subject.label.isEmpty)
        XCTAssertLessThan(subject.label.count, 80, "Show the selected word, not the full exercise context")
        XCTAssertFalse(app.buttons["tutor.subject.expand"].exists)
        XCTAssertTrue(app.buttons["tutor.quick.0"].exists)
        app.buttons["tutor.quick.0"].tap()
        XCTAssertTrue((app.descendants(matching: .any).matching(identifier: "tutor.input").firstMatch.value as? String ?? "").contains("この文脈での意味"))
        capture(UIDevice.current.userInterfaceIdiom == .pad ? "ipad-tutor" : "iphone-tutor")
    }

    func testReadingFigureCanExpandAndReturn() {
        app.buttons["home.skill.Reading"].tap()
        app.buttons["part.open.Reading / Section 2"].tap()
        let expand = app.buttons["question.visual.expand"]
        for _ in 0..<8 where !expand.isHittable { app.swipeUp() }
        XCTAssertTrue(expand.isHittable)
        capture("iphone-reading-figure")
        expand.tap()
        XCTAssertTrue(app.buttons["完了"].waitForExistence(timeout: 5))
        let figure = app.otherElements["question.visual"].firstMatch
        if figure.exists { figure.pinch(withScale: 2, velocity: 1) }
        let reset = app.buttons["question.visual.resetZoom"]
        XCTAssertTrue(reset.exists)
        reset.tap()
        capture("iphone-reading-figure-expanded")
        app.buttons["完了"].tap()
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
    }

    func testListeningFigureCanExpandAndReturn() {
        app.buttons["home.skill.Listening"].tap()
        app.buttons["part.open.Listening / Part 2"].tap()
        let expand = app.buttons["question.visual.expand"]
        for _ in 0..<8 where !expand.isHittable { app.swipeUp() }
        XCTAssertTrue(expand.isHittable)
        capture("iphone-listening-figure")
        expand.tap()
        XCTAssertTrue(app.buttons["完了"].waitForExistence(timeout: 5))
        capture("iphone-listening-figure-expanded")
        app.buttons["完了"].tap()
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
    }

    func testReadableChoicesAndAnswerSelection() {
        app.buttons["home.skill.Listening"].tap()
        app.buttons["part.open.Listening / Part 2"].tap()
        let choice = app.buttons["answer.choice.0.B"]
        for _ in 0..<10 where !choice.isHittable { app.swipeUp() }
        XCTAssertTrue(choice.isHittable)
        XCTAssertTrue(app.staticTexts["Question 11"].exists)
        XCTAssertTrue(app.textViews["study.text.Listening / Part 2choice-0-B"].exists)
        choice.tap()
        XCTAssertEqual(choice.value as? String, "選択済み")
        capture("iphone-questions")
    }

    func testAppearancePersistsAndCanFollowSystem() {
        app.buttons["home.settings"].tap()
        let picker = app.segmentedControls["settings.appearance"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.buttons["ダーク"].tap()
        XCTAssertTrue(picker.buttons["ダーク"].isSelected)
        XCTAssertLessThan(backgroundBrightness(), 0.4, "The open settings sheet must become dark")
        capture("iphone-settings-dark")
        app.buttons["完了"].tap()
        capture("iphone-home-dark")
        app.terminate(); app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP", "--ui-testing"]; app.launch()
        app.buttons["home.settings"].tap()
        XCTAssertTrue(picker.buttons["ダーク"].isSelected)
        picker.buttons["ライト"].tap()
        XCTAssertTrue(picker.buttons["ライト"].isSelected)
        XCTAssertGreaterThan(backgroundBrightness(), 0.6, "The open settings sheet must become light")
        capture("iphone-settings-light")
        picker.buttons["システム"].tap()
        XCTAssertTrue(picker.buttons["システム"].isSelected)
    }

    func testEnglishInterfaceAndTutorSuggestions() {
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing", "--ui-reset"]
        app.launch()
        XCTAssertTrue(app.staticTexts["What will you practice today?"].waitForExistence(timeout: 5))
        capture("iphone-home-en")
        app.buttons["home.settings"].tap()
        let picker = app.segmentedControls["settings.appearance"]
        XCTAssertTrue(picker.buttons["System"].waitForExistence(timeout: 5))
        XCTAssertTrue(picker.buttons["Light"].exists)
        XCTAssertTrue(picker.buttons["Dark"].exists)
        capture("iphone-settings-en")
        app.buttons["Done"].tap()
        openReading()
        let passage = app.textViews["study.text.Reading / Section 1passage-0"]
        passage.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 75, dy: 12)).tap()
        XCTAssertTrue(app.menuItems["Save word"].waitForExistence(timeout: 5))
        app.menuItems["Ask AI"].tap()
        XCTAssertTrue(app.buttons["tutor.quick.0"].waitForExistence(timeout: 5))
        app.buttons["tutor.quick.0"].tap()
        let input = app.descendants(matching: .any).matching(identifier: "tutor.input").firstMatch
        XCTAssertTrue((input.value as? String ?? "").contains("simple English"))
        capture("iphone-tutor-en")
    }

    func testGenerationLoadingAndCancel() {
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP", "--ui-testing", "--ui-reset", "--ui-generation-preview"]
        app.launch()
        navigate("単語帳", tag: 2)
        app.buttons["vocabulary.add"].tap()
        let field = app.descendants(matching: .any).matching(identifier: "vocabulary.expression").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("available")
        if app.buttons["入力を完了"].exists { app.buttons["入力を完了"].tap() }
        app.buttons["vocabulary.saveManual"].tap()
        navigate("ホーム", tag: 0)
        app.buttons["home.skill.Reading"].tap()
        app.buttons["新しい問題を生成して練習"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["あなただけの問題を準備中"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["進捗の目安"].exists)
        let action = app.buttons["generation.nextWord"]
        for _ in 0..<5 where !action.isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["generation.word"].exists)
        XCTAssertEqual(app.staticTexts["generation.word"].label, "available")
        XCTAssertFalse(app.staticTexts["generation.meaning"].label.isEmpty)
        let pronounce = app.buttons["vocabulary.pronounce.available"]
        XCTAssertTrue(pronounce.exists)
        XCTAssertEqual(pronounce.frame.width, 44, accuracy: 1)
        XCTAssertEqual(pronounce.frame.height, 44, accuracy: 1)
        XCTAssertEqual(pronounce.frame.minY, app.staticTexts["generation.word"].frame.minY, accuracy: 1)
        capture("iphone-generation-vocabulary")
        action.tap()
        let bundledWord = app.staticTexts["generation.word"].label
        XCTAssertNotEqual(bundledWord, "available")
        XCTAssertTrue(app.staticTexts["generation.source.bundled"].exists)
        XCTAssertTrue(app.staticTexts["generation.meaning"].exists)
        action.tap()
        XCTAssertNotEqual(app.staticTexts["generation.word"].label, bundledWord)
        XCTAssertNotEqual(app.staticTexts["generation.word"].label, "available")
        for _ in 0..<5 {
            for _ in 0..<3 where !action.isHittable { app.swipeUp() }
            action.tap()
        }
        capture("iphone-generation-bundled-word")
        let cancel = app.buttons["キャンセルして戻る"]
        for _ in 0..<3 where !cancel.isHittable { app.swipeUp() }
        cancel.tap()
        XCTAssertTrue(app.buttons["part.open.Reading / Section 1"].waitForExistence(timeout: 5))
    }

    func testPerAnswerSourceAndTutor() {
        openReading()
        let review = app.buttons["practice.review"]
        for _ in 0..<30 where !review.isHittable { app.swipeUp(velocity: .fast) }
        review.tap()
        let source = app.buttons["review.source.0"]
        for _ in 0..<8 where !source.isHittable { app.swipeUp() }
        source.tap()
        XCTAssertTrue(app.staticTexts["review.source.target"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["完了"].tap()
        app.buttons["review.tutor.0"].tap()
        XCTAssertTrue(app.staticTexts["tutor.subject"].waitForExistence(timeout: 5))
    }

    func testReviewRetryAndReturnHome() {
        openReading()
        let review = app.buttons["practice.review"]
        for _ in 0..<30 where !review.isHittable { app.swipeUp(velocity: .fast) }
        XCTAssertTrue(review.isHittable); review.tap()
        XCTAssertTrue(app.staticTexts["答えと解説"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["答えと解説"].isHittable, "Review must start at the top, not retain the question scroll offset")
        let retry = app.buttons["practice.retry"]
        for _ in 0..<20 where !retry.isHittable { app.swipeUp(velocity: .fast) }
        XCTAssertTrue(retry.isHittable)
        XCTAssertTrue(app.buttons["practice.save"].isHittable)
        XCTAssertTrue(app.buttons["practice.ask"].isHittable)
        capture(UIDevice.current.userInterfaceIdiom == .pad ? "ipad-review-actions" : "iphone-review-actions")
        app.buttons["practice.ask"].tap()
        let subject = app.staticTexts["tutor.subject"]
        XCTAssertTrue(subject.waitForExistence(timeout: 5))
        XCTAssertTrue(subject.isHittable)
        let collapsedHeight = subject.frame.height
        let expand = app.buttons["tutor.subject.expand"]
        XCTAssertTrue(expand.isHittable)
        capture("iphone-tutor-long-subject")
        expand.tap()
        XCTAssertGreaterThan(subject.frame.height, collapsedHeight)
        app.buttons["完了"].tap()
        retry.tap()
        XCTAssertTrue(app.buttons["practice.review"].exists)
        app.buttons["practice.back"].tap()
        let endAlert = app.alerts["練習を終了しますか？"]
        XCTAssertTrue(endAlert.waitForExistence(timeout: 5))
        capture(UIDevice.current.userInterfaceIdiom == .pad ? "ipad-exit-alert" : "iphone-exit-alert")
        endAlert.buttons["続ける"].tap()
        XCTAssertTrue(app.buttons["practice.back"].exists)
        app.buttons["practice.back"].tap()
        endAlert.buttons["練習を終了"].tap()
        XCTAssertFalse(app.buttons["practice.back"].exists)
        XCTAssertFalse(app.staticTexts["練習を終了しました"].exists)
        XCTAssertTrue(app.buttons["home.skill.Reading"].waitForExistence(timeout: 5))
    }
    func testResultOpensHistoryAndPreservesAllAnswers() {
        openReading()
        let choice = app.buttons["answer.choice.0.TRUE"]
        for _ in 0..<20 where !choice.isHittable { app.swipeUp(velocity: .fast) }
        XCTAssertTrue(choice.isHittable)
        choice.tap()
        let review = app.buttons["practice.review"]
        for _ in 0..<25 where !review.isHittable { app.swipeUp(velocity: .fast) }
        review.tap()
        XCTAssertTrue(app.staticTexts["答えと解説"].isHittable)
        for _ in 0..<20 where !review.isHittable { app.swipeUp(velocity: .fast) }
        review.tap()
        XCTAssertTrue(app.alerts.buttons["練習を終了"].waitForExistence(timeout: 5))
        app.alerts.buttons["練習を終了"].tap()
        XCTAssertTrue(app.buttons["home.skill.Reading"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["練習を終了しました"].exists)
        navigate("学習記録", tag: 1)
        let record = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Community services")).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5)); record.tap()
        capture(UIDevice.current.userInterfaceIdiom == .pad ? "ipad-history-detail" : "iphone-history-detail")
        app.buttons["この問題を保存"].tap()
        XCTAssertTrue(app.alerts["保存しました"].waitForExistence(timeout: 5))
        app.alerts.buttons["学習を続ける"].tap()
        app.buttons["history.answers"].tap()
        XCTAssertTrue(app.staticTexts["あなたの解答: TRUE"].waitForExistence(timeout: 5))
        let unanswered = app.staticTexts["あなたの解答: 未回答"].firstMatch
        for _ in 0..<5 where !unanswered.isHittable { app.swipeUp() }
        XCTAssertTrue(unanswered.isHittable)
        app.terminate(); app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP", "--ui-testing"]; app.launch()
        let savedPapers = app.buttons["home.savedPapers"]
        for _ in 0..<8 where !savedPapers.isHittable { app.swipeUp() }
        savedPapers.tap()
        let saved = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Community services")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["saved.skill.Listening"].exists)
        app.buttons["saved.skill.Listening"].tap()
        XCTAssertTrue(app.staticTexts["保存した問題はありません"].exists)
        app.buttons["saved.skill.Reading"].tap()
        XCTAssertTrue(app.staticTexts["Section 1"].exists)
        capture(UIDevice.current.userInterfaceIdiom == .pad ? "ipad-saved-questions" : "iphone-saved-questions")
        for _ in 0..<8 where !saved.isHittable { app.swipeUp() }
        app.cells.containing(.staticText, identifier: "Community services").firstMatch.swipeLeft()
        capture("iphone-saved-swipe")
        app.buttons["削除"].firstMatch.tap()
        let confirmation = app.alerts["保存した問題を削除しますか？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["キャンセル"].tap()
        XCTAssertTrue(saved.exists)
        app.cells.containing(.staticText, identifier: "Community services").firstMatch.swipeLeft()
        app.buttons["削除"].firstMatch.tap()
        confirmation.buttons["削除"].tap()
        XCTAssertTrue(app.staticTexts["保存した問題はありません"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        for _ in 0..<8 where !savedPapers.isHittable { app.swipeUp() }
        savedPapers.tap()
        XCTAssertTrue(app.staticTexts["保存した問題はありません"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        navigate("学習記録", tag: 1)
        XCTAssertTrue(record.waitForExistence(timeout: 5)); record.tap()
        app.buttons["この問題をもう一度練習"].tap()
        XCTAssertTrue(app.staticTexts["Community services"].waitForExistence(timeout: 5))
    }

    func testToolbarSaveAndTwoChoiceExit() {
        openReading()
        app.buttons["practice.back"].tap()
        XCTAssertTrue(app.alerts.buttons["練習を終了"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.buttons.count, 2)
        app.alerts.buttons["続ける"].tap()
        app.buttons["practice.saveToolbar"].tap()
        app.alerts.buttons["学習を続ける"].tap()
        app.buttons["practice.back"].tap()
        app.alerts.buttons["練習を終了"].tap()
        XCTAssertTrue(app.buttons["home.skill.Reading"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["練習を終了しました"].exists)
        let savedPapers = app.buttons["home.savedPapers"]
        for _ in 0..<8 where !savedPapers.isHittable { app.swipeUp() }
        savedPapers.tap()
        let saved = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Community services")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5)); saved.tap()
        app.buttons["practice.back"].tap()
        XCTAssertTrue(app.alerts.buttons["練習を終了"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.buttons.count, 2)
    }

    func testMockExitHasTwoChoices() {
        let mock = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "4技能をまとめて腕試し")).firstMatch
        for _ in 0..<8 where !mock.isHittable { app.swipeUp() }
        mock.tap()
        let start = app.buttons["模試を始める"]
        for _ in 0..<8 where !start.isHittable { app.swipeUp() }
        start.tap()
        XCTAssertTrue(app.buttons["practice.back"].waitForExistence(timeout: 5))
        app.buttons["practice.back"].tap()
        XCTAssertTrue(app.alerts.buttons["練習を終了"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.buttons.count, 2)
        capture("iphone-mock-save-on-exit")
        app.alerts.buttons["続ける"].tap()
        XCTAssertTrue(app.buttons["practice.back"].exists)
        app.buttons["practice.back"].tap()
        app.alerts.buttons["練習を終了"].tap()
        XCTAssertTrue(app.buttons["home.skill.Reading"].waitForExistence(timeout: 5))
    }

    func testAdditionalLanguageLayouts() {
        for (language, title) in [("ar", "الإعدادات"), ("zh-Hans", "设置"), ("hi", "सेटिंग"), ("th", "การตั้งค่า"), ("es", "Ajustes")] {
            app.terminate()
            app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", language, "--ui-testing", "--ui-reset"]
            app.launch()
            XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 5))
            capture("iphone-home-\(language)")
            app.buttons["home.settings"].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            capture("iphone-settings-\(language)")
        }
    }

    func testSpeakingModelSelectionPersistsAndConversationOpens() {
        app.buttons["home.settings"].tap()
        let model = app.buttons["settings.speakingModel"]
        for _ in 0..<8 where !model.isHittable { app.swipeUp() }
        XCTAssertTrue(model.isHittable)
        model.tap()
        app.buttons["標準 · 高品質"].tap()
        capture("iphone-speaking-model-settings")
        app.buttons["完了"].tap()
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP", "--ui-testing"]
        app.launch()
        app.buttons["home.skill.Speaking"].tap()
        app.buttons["part.open.Speaking / Part 1"].tap()
        let voice = app.buttons["speaking.conversation"]
        for _ in 0..<12 where !voice.isHittable { app.swipeUp() }
        XCTAssertTrue(voice.isHittable); voice.tap()
        XCTAssertTrue(app.buttons["speaking.start"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["標準 · 高品質"].exists)
        capture("iphone-speaking-conversation")
        app.buttons["閉じる"].tap()
        XCTAssertTrue(voice.waitForExistence(timeout: 5))
        // Never start a paid API session or request microphone access in UI tests.
    }

    func testSettingsSeparatesChatGPTAndAudioAPI() {
        app.buttons["home.settings"].tap()
        XCTAssertTrue(app.buttons["settings.signIn"].waitForExistence(timeout: 5))
        let key = app.secureTextFields["settings.speechKey"]
        for _ in 0..<8 where !key.isHittable { app.swipeUp() }
        XCTAssertTrue(key.exists)
        XCTAssertTrue(app.buttons["APIキー取得ページを開く"].exists || app.links["APIキー取得ページを開く"].exists)
        capture("iphone-audio-settings")
    }
    func testOSSLicensesCanBeReadInSettings() {
        app.buttons["home.settings"].tap()
        let licenses = app.buttons["settings.licenses"]
        for _ in 0..<15 where !licenses.isHittable { app.swipeUp() }
        XCTAssertTrue(licenses.isHittable); licenses.tap()
        let nunito = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Nunito")).firstMatch
        XCTAssertTrue(nunito.waitForExistence(timeout: 5))
        capture("iphone-oss-licenses")
        nunito.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "SIL OPEN FONT LICENSE")).firstMatch.waitForExistence(timeout: 5))
    }

    func testWritingResponseIsSavedInHistory() {
        app.buttons["home.skill.Writing"].tap()
        app.buttons["part.open.Writing / Task 1"].tap()
        let editor = app.textViews["英作文の回答"]
        for _ in 0..<12 where !editor.isHittable { app.swipeUp(velocity: .fast) }
        XCTAssertTrue(editor.isHittable)
        editor.tap(); editor.typeText("Dear Sir, I am writing about the heater in my flat. It has not worked since Monday. Please arrange a repair this week. Yours faithfully, Alex")
        let dismissKeyboard = app.buttons["practice.dismissKeyboard"]
        XCTAssertTrue(dismissKeyboard.waitForExistence(timeout: 5))
        XCTAssertTrue(dismissKeyboard.isHittable)
        dismissKeyboard.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let review = app.buttons["practice.review"]
        for _ in 0..<10 {
            if review.isHittable && review.frame.maxY < app.frame.maxY - 30 { break }
            app.swipeUp(velocity: .fast)
        }
        review.tap()
        let assessment = app.buttons["AIの講評を見る"]
        for _ in 0..<8 where !assessment.isHittable { app.swipeUp() }
        XCTAssertTrue(assessment.waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP", "--ui-testing"]; app.launch()
        navigate("学習記録", tag: 1)
        let history = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Writing")).firstMatch
        for _ in 0..<8 where !history.isHittable { app.swipeUp(velocity: .fast) }
        XCTAssertTrue(history.isHittable); history.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Dear Sir")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["この問題をもう一度練習"].exists)
    }
    func testMockGenerationChoiceAtLargeText() {
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "--ui-testing", "--ui-reset"]
        app.launch()
        let mock = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "模擬テスト")).firstMatch
        for _ in 0..<10 where !mock.isHittable { app.swipeUp() }
        mock.tap()
        let toggle = app.switches["mock.generate"]
        for _ in 0..<15 where !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.isHittable)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")
        let start = app.buttons["模試を始める"]
        for _ in 0..<8 where !start.isHittable { app.swipeUp() }
        XCTAssertTrue(start.isHittable)
        capture(UIDevice.current.userInterfaceIdiom == .pad ? "ipad-mock-large-text" : "iphone-mock-large-text")
    }

    func testMockStartsWithoutRevealingAnswersAndCanExit() {
        let mock = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "模擬テスト")).firstMatch
        for _ in 0..<12 where !mock.isHittable { app.swipeUp() }
        mock.tap()
        let start = app.buttons["模試を始める"]
        for _ in 0..<8 where !start.isHittable { app.swipeUp(velocity: .fast) }
        capture(UIDevice.current.userInterfaceIdiom == .pad ? "ipad-mock-intro" : "iphone-mock-intro")
        start.tap()
        XCTAssertTrue(app.staticTexts["Listening / Part 1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["この問題をAIに質問"].exists)
        XCTAssertFalse(app.buttons["AIの講評を見る"].exists)
        app.buttons["終了"].tap()
        XCTAssertTrue(app.buttons["模試を始める"].waitForExistence(timeout: 5))
    }

    func testZScreenshotsAndAdaptiveNavigation() {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        if isPad { XCUIDevice.shared.orientation = .landscapeLeft }
        let prefix = isPad ? "ipad" : "iphone"
        XCTAssertTrue(app.buttons["home.skill.Reading"].waitForExistence(timeout: 5))
        capture(prefix + "-home")
        openReading()
        XCTAssertTrue(app.staticTexts["Community services"].waitForExistence(timeout: 5))
        capture(prefix + "-reading")
        let passage = app.textViews["study.text.Reading / Section 1passage-0"]
        passage.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 75, dy: 12)).tap()
        XCTAssertTrue(app.menuItems["単語帳に追加"].waitForExistence(timeout: 5))
        capture(prefix + "-selection")
        app.menuItems["単語帳に追加"].tap()
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP", "--ui-testing"]
        app.launch()
        navigate("単語帳", tag: 2)
        XCTAssertTrue(app.buttons["元の問題を復習"].waitForExistence(timeout: 5))
        capture(prefix + "-vocabulary")
        app.terminate(); app.launch()
        if isPad {
            XCUIDevice.shared.orientation = .portrait
            XCTAssertTrue(app.buttons["home.skill.Reading"].waitForExistence(timeout: 5))
            capture("ipad-home-portrait")
            XCUIDevice.shared.orientation = .landscapeLeft
            navigate("学習記録", tag: 1)
            XCTAssertTrue(app.staticTexts["学習履歴"].waitForExistence(timeout: 5))
            navigate("ホーム", tag: 0)
        }
        app.buttons["home.settings"].tap()
        let cloud = app.switches["settings.icloud"]
        for _ in 0..<10 where !cloud.isHittable { app.swipeUp() }
        XCTAssertTrue(cloud.exists)
        capture(prefix + "-settings")
    }

}
