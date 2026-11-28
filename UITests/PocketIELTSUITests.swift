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
        XCTAssertEqual(app.buttons["vocabulary.composeAI"].label, "AIに質問")
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

    func testTabBarReturnsWithHomeAfterLeavingAnExercise() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone)
        let homeTab = app.tabBars.buttons["ホーム"]
        let reading = app.buttons["home.skill.Reading"]
        let section = app.buttons["part.open.Reading / Section 1"]
        XCTAssertTrue(homeTab.isHittable)
        reading.tap()
        XCTAssertTrue(section.waitForExistence(timeout: 5))
        XCTAssertFalse(homeTab.isHittable)
        section.tap()
        let back = app.buttons["practice.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertFalse(homeTab.isHittable)
        back.tap()
        app.alerts.buttons["練習を終了"].tap()
        XCTAssertTrue(section.waitForExistence(timeout: 5))
        XCTAssertFalse(homeTab.isHittable)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(reading.waitForExistence(timeout: 5))
        XCTAssertTrue(homeTab.isHittable)
    }

    func testSectionsAvailableOnFirstNavigation() {
        app.terminate()
        app.launch()
        app.buttons["home.skill.Reading"].tap()
        for (index, minutes) in [15, 20, 25].enumerated() {
            let section = app.buttons["part.open.Reading / Section \(index + 1)"]
            XCTAssertTrue(section.waitForExistence(timeout: 12))
            XCTAssertTrue(section.label.contains(String(minutes)))
        }
        XCTAssertFalse(app.buttons["保存した問題から練習"].exists)
        capture("iphone-reading-sections")
        app.buttons["part.open.Reading / Section 1"].tap()
        XCTAssertTrue(app.staticTexts["Community services"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["practice.elapsed"].firstMatch.exists)
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
        let save = app.menuItems["後で確認"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertFalse(app.descendants(matching: .any)["selection.saved"].exists)
        app.buttons["practice.jumpQuestion"].tap()
        let review = app.buttons["practice.review"]
        for _ in 0..<30 where !review.isHittable { app.swipeUp(velocity: .fast) }
        review.tap()
        XCTAssertTrue(app.staticTexts["後で確認する語句"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["practice.score"].label, "0 / 13 正解")
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
        XCTAssertTrue(app.menuItems["後で確認"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.menuItems["問題を保存"].exists)
        let pronunciation = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND (elementType == %d OR elementType == %d)", "発音を聞く", XCUIElement.ElementType.menuItem.rawValue, XCUIElement.ElementType.button.rawValue)).firstMatch
        if !pronunciation.exists { app.buttons["進む"].tap() }
        XCTAssertTrue(pronunciation.waitForExistence(timeout: 5))
        XCTAssertFalse(app.menuItems["問題を保存"].exists)
        pronunciation.tap()
        XCTAssertTrue(pronunciation.waitForNonExistence(timeout: 5))
        word.tap()
        XCTAssertTrue(app.menuItems["後で確認"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["テキスト選択"].exists)
        app.staticTexts["Community services"].tap()
        XCTAssertTrue(app.menuItems["後で確認"].waitForNonExistence(timeout: 5))
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
        app.buttons["翻訳する"].tap()
        XCTAssertTrue((app.descendants(matching: .any).matching(identifier: "tutor.input").firstMatch.value as? String ?? "").contains("日本語に翻訳"))
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
        XCTAssertTrue(app.buttons["question.visual.close"].waitForExistence(timeout: 5))
        let figure = app.otherElements["question.visual"].firstMatch
        if figure.exists { figure.pinch(withScale: 2, velocity: 1) }
        let reset = app.buttons["question.visual.resetZoom"]
        XCTAssertTrue(reset.exists)
        reset.tap()
        capture("iphone-reading-figure-expanded")
        app.buttons["question.visual.close"].tap()
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
    }

    func testListeningControlsAppearBelowPlaybackSlider() {
        app.buttons["home.skill.Listening"].tap()
        app.buttons["part.open.Listening / Part 1"].tap()
        let play = app.buttons["listening.play"]
        for _ in 0..<8 where !play.isHittable { app.swipeUp() }
        XCTAssertTrue(play.isHittable)
        let slider = app.sliders["再生位置"]
        XCTAssertTrue(slider.exists)
        XCTAssertGreaterThanOrEqual(play.frame.minY, slider.frame.maxY)
        XCTAssertGreaterThanOrEqual(app.buttons["listening.rewind"].frame.minY, slider.frame.maxY)
    }

    func testListeningFigureCanExpandAndReturn() {
        app.buttons["home.skill.Listening"].tap()
        app.buttons["part.open.Listening / Part 2"].tap()
        let expand = app.buttons["question.visual.expand"]
        for _ in 0..<8 where !expand.isHittable { app.swipeUp() }
        XCTAssertTrue(expand.isHittable)
        capture("iphone-listening-figure")
        expand.tap()
        XCTAssertTrue(app.buttons["question.visual.close"].waitForExistence(timeout: 5))
        capture("iphone-listening-figure-expanded")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.18)).tap()
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
    }

    func testPasteSelectedWordIntoListeningAnswer() {
        verifyPasteIntoSecondAnswer(skill: "Listening", part: "Listening / Part 1")
    }

    func testReadingAnswerShowsPasteWithKeyboardOpen() {
        verifyPasteIntoSecondAnswer(skill: "Reading", part: "Reading / Section 2")
    }

    private func verifyPasteIntoSecondAnswer(skill: String, part: String) {
        app.buttons["home.skill.\(skill)"].tap()
        app.buttons["part.open.\(part)"].tap()
        let jump = app.buttons["practice.jumpQuestion"]
        XCTAssertTrue(jump.waitForExistence(timeout: 8))
        jump.tap()
        let first = app.textFields["解答"].firstMatch
        let firstPaste = app.buttons.matching(identifier: "answer.paste").firstMatch
        XCTAssertTrue(firstPaste.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(firstPaste.frame.width, 44)
        first.tap()
        XCTAssertTrue(firstPaste.isHittable)
        first.typeText("Course")
        first.typeKey("a", modifierFlags: .command)
        first.typeKey("c", modifierFlags: .command)
        let paste = app.buttons.matching(identifier: "answer.paste").element(boundBy: 1)
        for _ in 0..<5 where !paste.isHittable { app.swipeUp() }
        paste.tap()
        let second = app.textFields.element(boundBy: 1)
        let pasted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Course"), object: second)
        XCTAssertEqual(XCTWaiter.wait(for: [pasted], timeout: 5), .completed, app.debugDescription)

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
        let device = XCUIDevice.shared
        let originalAppearance = device.appearance
        defer { device.appearance = originalAppearance }
        device.appearance = .dark
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
        XCTAssertLessThan(backgroundBrightness(), 0.4, "Light → System must restore dark on the open sheet")
        device.appearance = .light
        // Device appearance changes asynchronously, including its crossfade.
        let followsSystem = expectation(for: NSPredicate { _, _ in self.backgroundBrightness() > 0.6 },
                                        evaluatedWith: nil)
        wait(for: [followsSystem], timeout: 5)
        picker.buttons["ダーク"].tap()
        picker.buttons["システム"].tap()
        XCTAssertGreaterThan(backgroundBrightness(), 0.6, "Dark → System must restore light on the open sheet")
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
        XCTAssertTrue(app.menuItems["Review later"].waitForExistence(timeout: 5))
        app.menuItems["Ask AI"].tap()
        XCTAssertTrue(app.buttons["tutor.quick.0"].waitForExistence(timeout: 5))
        app.buttons["tutor.quick.0"].tap()
        let input = app.descendants(matching: .any).matching(identifier: "tutor.input").firstMatch
        XCTAssertTrue((input.value as? String ?? "").contains("simple English"))
        capture("iphone-tutor-en")
    }

    func testBackgroundingDuringSectionGeneration() {
        app.terminate()
        app.launchArguments.append("--ui-generation-preview")
        app.launch()
        app.buttons["home.skill.Reading"].tap()
        app.buttons["part.open.Reading / Section 1"].tap()
        XCTAssertTrue(app.staticTexts["進捗の目安"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        let home = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        home.name = "generation-live-activity-background"
        home.lifetime = .keepAlways
        add(home)
        app.activate()
        XCTAssertTrue(app.staticTexts["進捗の目安"].waitForExistence(timeout: 5))
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
        app.buttons["part.open.Reading / Section 1"].tap()
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

    private func openListeningTranscript() {
        app.buttons["home.skill.Listening"].tap()
        app.buttons["part.open.Listening / Part 1"].tap()
        let review = app.buttons["practice.review"]
        for _ in 0..<30 where !review.isHittable { app.swipeUp(velocity: .fast) }
        review.tap()

        let transcript = app.buttons["review.transcript"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 5))
        transcript.tap()
        let firstLine = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Eastbank Community Centre")).firstMatch
        XCTAssertTrue(firstLine.waitForExistence(timeout: 5))
    }

    func testEnglishTranscriptHidesTranslationControl() {
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing", "--ui-reset"]
        app.launch()
        openListeningTranscript()
        XCTAssertFalse(app.buttons["review.translation.0"].exists)
    }

    func testListeningReviewOpensPausedTranscriptAndReturnsToAnswer() {
        openListeningTranscript()
        XCTAssertTrue(app.buttons["review.translation.0"].isHittable)
        XCTAssertTrue(app.buttons["review.translation.1"].exists)
        XCTAssertTrue(app.buttons["音声を再生"].exists)
        // Check playback geometry when the simulator has a prepared recording.
        if app.sliders["再生位置"].exists {
            let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "That photograph was taken")).firstMatch
            for _ in 0..<3 where !row.isHittable { app.swipeUp() }
            XCTAssertTrue(row.isHittable)
            let before = row.frame.minY
            row.tap()
            XCTAssertTrue(app.buttons["一時停止"].waitForExistence(timeout: 5))
            XCTAssertEqual(row.frame.minY, before, accuracy: 1)
            row.tap()
            XCTAssertEqual(row.frame.minY, before, accuracy: 1)
        }
        app.buttons["閉じる"].tap()
        let evidence = app.buttons["review.listen.1"]
        for _ in 0..<6 where !evidence.isHittable { app.swipeUp() }
        XCTAssertTrue(evidence.isHittable)
    }

    private func askAboutPassageSelection() {
        let paragraph = app.textViews.matching(NSPredicate(
            format: "value BEGINSWITH %@ OR label BEGINSWITH %@", "Your ordinary library card", "Your ordinary library card"
        )).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 5))
        paragraph.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 12, dy: 12)).tap()
        let ask = app.menuItems["AIに質問"]
        XCTAssertTrue(ask.waitForExistence(timeout: 5))
        ask.tap()
        XCTAssertTrue(app.staticTexts["tutor.subject"].waitForExistence(timeout: 5))
        app.buttons["tutor.done"].tap()
    }

    func testPerAnswerSourceAndTutor() {
        openReading()
        let review = app.buttons["practice.review"]
        for _ in 0..<30 where !review.isHittable { app.swipeUp(velocity: .fast) }
        review.tap()
        let fullText = app.buttons["review.reading.fullText"]
        XCTAssertTrue(fullText.waitForExistence(timeout: 5))
        fullText.tap()
        XCTAssertTrue(app.buttons["review.reading.translate.0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["review.reading.translate.1"].exists)
        askAboutPassageSelection()
        XCTAssertTrue(app.buttons["review.reading.translate.0"].waitForExistence(timeout: 5))
        app.buttons["完了"].tap()
        let source = app.buttons["review.source.0"]
        for _ in 0..<8 where !source.isHittable { app.swipeUp() }
        source.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "review.source.target").firstMatch.waitForExistence(timeout: 5))
        app.buttons["完了"].tap()
        app.buttons["review.tutor.0"].tap()
        XCTAssertTrue(app.staticTexts["tutor.subject"].waitForExistence(timeout: 5))
    }

    func testReviewedPaperCanBeRetriedThenBackReturnsToSections() {
        openReading()
        let review = app.buttons["practice.review"]
        for _ in 0..<30 where !review.isHittable { app.swipeUp(velocity: .fast) }
        XCTAssertFalse(app.buttons["practice.save"].exists)
        XCTAssertFalse(app.buttons["practice.ask"].exists)
        XCTAssertTrue(app.buttons["practice.saveToolbar"].isHittable)
        XCTAssertTrue(review.isHittable); review.tap()
        XCTAssertTrue(app.staticTexts["答えと解説"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["答えと解説"].isHittable, "Review must start at the top, not retain the question scroll offset")
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.003, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertTrue(review.isHittable, "Native back should restore the question's scroll position")
        XCTAssertFalse(app.staticTexts["答えと解説"].exists)
        review.tap()
        XCTAssertTrue(app.staticTexts["答えと解説"].waitForExistence(timeout: 5))
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
        app.alerts.buttons["練習を終了"].tap()
        let part = app.buttons["part.open.Reading / Section 1"]
        XCTAssertTrue(part.waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertTrue(part.label.contains("新しい問題を生成して練習"))
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
        XCTAssertTrue(app.staticTexts["答えと解説"].waitForExistence(timeout: 5))
        app.buttons["review.reading.fullText"].tap()
        XCTAssertTrue(app.buttons["review.reading.translate.1"].waitForExistence(timeout: 5))
        askAboutPassageSelection()
        app.buttons["完了"].tap()
        app.buttons["practice.saveToolbar"].tap()
        XCTAssertTrue(app.alerts["保存しました"].waitForExistence(timeout: 5))
        app.alerts.buttons["学習を続ける"].tap()
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
        let savedRow = app.cells.containing(.staticText, identifier: "Community services").firstMatch
        let originalRowY = savedRow.frame.minY
        savedRow.swipeLeft()
        capture("iphone-saved-swipe")
        app.buttons["削除"].firstMatch.tap()
        let confirmation = app.alerts["保存した問題を削除しますか？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["キャンセル"].tap()
        XCTAssertTrue(saved.exists)
        XCTAssertEqual(savedRow.frame.minY, originalRowY, accuracy: 2)
        savedRow.swipeLeft()
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

    func testBackBeforeReviewKeepsPaperReadyAndReturnsToItsSource() {
        openReading()
        XCTAssertTrue(app.staticTexts["Community services"].waitForExistence(timeout: 5))
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.003, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        XCTAssertTrue(app.buttons["practice.back"].isHittable)
        let jump = app.buttons["practice.jumpQuestion"]
        jump.tap()
        let firstChoice = app.buttons["answer.choice.0.TRUE"]
        XCTAssertTrue(firstChoice.isHittable)
        firstChoice.tap()
        let second = app.buttons["answer.choice.1.TRUE"]
        for _ in 0..<8 where !second.isHittable { app.swipeUp() }
        second.tap()
        let prior = app.buttons["answer.choice.0.FALSE"]
        for _ in 0..<8 where !prior.isHittable { app.swipeDown() }
        prior.tap()
        XCTAssertTrue(jump.label.contains("2"))
        app.buttons["practice.jumpPassage"].tap()
        XCTAssertTrue(app.staticTexts["Community services"].isHittable)
        jump.tap()
        XCTAssertTrue(second.isHittable)
        app.buttons["practice.back"].tap()
        app.alerts.buttons["続ける"].tap()
        XCTAssertTrue(second.isHittable)
        app.buttons["practice.back"].tap()
        app.alerts.buttons["練習を終了"].tap()
        let part = app.buttons["part.open.Reading / Section 1"]
        XCTAssertTrue(part.waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertTrue(part.label.contains("生成済み"))
        part.tap()
        XCTAssertTrue(app.staticTexts["Community services"].waitForExistence(timeout: 5))
        app.buttons["practice.saveToolbar"].tap()
        app.alerts.buttons["学習を続ける"].tap()
        app.buttons["practice.back"].tap()
        app.alerts.buttons["練習を終了"].tap()
        XCTAssertTrue(part.waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        let savedPapers = app.buttons["home.savedPapers"]
        for _ in 0..<8 where !savedPapers.isHittable { app.swipeUp() }
        savedPapers.tap()
        let saved = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Community services")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5)); saved.tap()
        app.buttons["practice.back"].tap()
        app.alerts.buttons["練習を終了"].tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testResetRequiresConfirmationAndClearsPersonalVocabulary() {
        navigate("単語帳", tag: 2)
        app.buttons["vocabulary.add"].tap()
        let field = app.descendants(matching: .any)["vocabulary.expression"].firstMatch
        field.tap(); field.typeText("refund")
        if app.buttons["入力を完了"].exists { app.buttons["入力を完了"].tap() }
        app.buttons["vocabulary.saveManual"].tap()
        XCTAssertTrue(app.staticTexts["refund"].waitForExistence(timeout: 5))
        navigate("ホーム", tag: 0)
        app.buttons["home.settings"].tap()
        let reset = app.buttons["settings.resetLearningData"]
        for _ in 0..<12 where !reset.isHittable { app.swipeUp() }
        reset.tap()
        app.alerts.buttons["キャンセル"].tap()
        reset.tap()
        app.alerts.buttons["削除"].tap()
        XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 5))
        navigate("単語帳", tag: 2)
        XCTAssertTrue(app.buttons["vocabulary.add"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["refund"].exists)
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

    func testSettingsShowsSharedAPIKeyAndMediaToggles() {
        app.buttons["home.settings"].tap()
        XCTAssertTrue(app.buttons["settings.signIn"].waitForExistence(timeout: 5))
        let key = app.secureTextFields["settings.openAIKey"]
        for _ in 0..<8 where !key.isHittable { app.swipeUp() }
        XCTAssertTrue(key.exists)
        let manageKeys = app.descendants(matching: .any).matching(identifier: "settings.manageAPIKeys").firstMatch
        for _ in 0..<8 where !manageKeys.isHittable { app.swipeUp() }
        XCTAssertTrue(manageKeys.isHittable)
        let audio = app.switches["settings.prepareListeningAudio"]
        let images = app.switches["settings.questionImages"]
        for _ in 0..<8 where !images.isHittable { app.swipeUp() }
        XCTAssertTrue(audio.isHittable)
        XCTAssertTrue(images.isHittable)
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

    func testMockListeningReviewEditsEarlierPartsAndExpiresIntoReading() {
        let mock = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "模擬テスト")).firstMatch
        for _ in 0..<12 where !mock.isHittable { app.swipeUp() }
        mock.tap()
        let start = app.buttons["模試を始める"]
        for _ in 0..<8 where !start.isHittable { app.swipeUp(velocity: .fast) }
        start.tap()
        for part in 1...4 {
            XCTAssertTrue(app.staticTexts["Listening / Part \(part)"].waitForExistence(timeout: 10))
            let next = app.buttons["practice.review"]
            for _ in 0..<30 where !next.isHittable { app.swipeUp(velocity: .fast) }
            next.tap()
        }
        let picker = app.segmentedControls.firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        picker.buttons["Part 2"].tap()
        let choice = app.buttons["answer.choice.0.B"]
        for _ in 0..<10 where !choice.isHittable { app.swipeUp(velocity: .fast) }
        choice.tap()
        for _ in 0..<10 where !picker.isHittable { app.swipeDown(velocity: .fast) }
        picker.buttons["Part 1"].tap()
        picker.buttons["Part 2"].tap()
        XCTAssertEqual(choice.value as? String, "選択済み")
        XCTAssertTrue(app.staticTexts["Reading / Section 1"].waitForExistence(timeout: 125))
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
        XCTAssertTrue(app.menuItems["後で確認"].waitForExistence(timeout: 5))
        capture(prefix + "-selection")
        app.menuItems["後で確認"].tap()
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
