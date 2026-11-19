import XCTest
import UIKit

@MainActor
final class PocketIELTSUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-reset"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
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
    private func openReading() {
        let reading = app.buttons["home.skill.Reading"]
        XCTAssertTrue(reading.waitForExistence(timeout: 10)); reading.tap()
        let part = app.buttons["part.open.Reading / Section 1"]
        XCTAssertTrue(part.waitForExistence(timeout: 5)); part.tap()
    }
    func testTapExpressionSaveAndReopenAfterRelaunch() {
        openReading()
        let passage = app.textViews["study.text.Reading / Section 1passage-0"]
        XCTAssertTrue(passage.waitForExistence(timeout: 5))
        passage.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 75, dy: 12)).tap()
        let save = app.buttons["選んだ表現を単語帳に追加"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(app.staticTexts["単語帳に保存しました"].waitForExistence(timeout: 5))
        app.buttons["単語帳を見る"].tap()
        XCTAssertTrue(app.buttons["元の問題を復習"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        navigate("単語帳", tag: 2)
        XCTAssertTrue(app.buttons["元の問題を復習"].waitForExistence(timeout: 5))
        app.buttons["元の問題を復習"].tap()
        XCTAssertTrue(app.staticTexts["Community services"].waitForExistence(timeout: 5))
    }
    func testReviewRetryAndReturnHome() {
        openReading()
        let review = app.buttons["practice.review"]
        for _ in 0..<30 where !review.isHittable { app.swipeUp(velocity: .fast) }
        XCTAssertTrue(review.isHittable); review.tap()
        XCTAssertTrue(app.staticTexts["答えと解説"].waitForExistence(timeout: 5))
        let retry = app.buttons["practice.retry"]
        for _ in 0..<20 where !retry.isHittable { app.swipeUp(velocity: .fast) }
        XCTAssertTrue(retry.isHittable); retry.tap()
        XCTAssertTrue(app.buttons["practice.review"].exists)
        app.buttons["practice.finish"].tap()
        app.buttons["練習を終了"].tap()
        XCTAssertTrue(app.buttons["ホームに戻る"].waitForExistence(timeout: 5))
        app.buttons["ホームに戻る"].tap()
        XCTAssertTrue(app.buttons["home.skill.Reading"].waitForExistence(timeout: 5))
    }
    func testSettingsHasChatGPTOnly() {
        app.buttons["home.settings"].tap()
        XCTAssertTrue(app.buttons["Sign in with ChatGPT"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.secureTextFields.firstMatch.exists)
        XCTAssertFalse(app.staticTexts["APIキー"].exists)
    }
    func testWritingResponseIsSavedInHistory() {
        app.buttons["home.skill.Writing"].tap()
        app.buttons["part.open.Writing / Task 1"].tap()
        let editor = app.textViews["英作文の回答"]
        for _ in 0..<12 where !editor.isHittable { app.swipeUp(velocity: .fast) }
        XCTAssertTrue(editor.isHittable)
        editor.tap(); editor.typeText("Dear Sir, I am writing about the heater in my flat. It has not worked since Monday. Please arrange a repair this week. Yours faithfully, Alex")
        app.buttons["入力を完了"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let review = app.buttons["practice.review"]
        for _ in 0..<10 {
            if review.isHittable && review.frame.maxY < app.frame.maxY - 30 { break }
            app.swipeUp(velocity: .fast)
        }
        review.tap()
        XCTAssertTrue(app.buttons["AIの講評を見る"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = ["--ui-testing"]; app.launch()
        navigate("学習記録", tag: 1)
        let history = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Writing")).firstMatch
        for _ in 0..<8 where !history.isHittable { app.swipeUp(velocity: .fast) }
        XCTAssertTrue(history.isHittable); history.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Dear Sir")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["この問題をもう一度練習"].exists)
    }
    func testMockStartsWithoutRevealingAnswersAndCanExit() {
        app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "模擬テスト")).firstMatch.tap()
        let start = app.buttons["模試を始める"]
        for _ in 0..<8 where !start.isHittable { app.swipeUp(velocity: .fast) }
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
        XCTAssertTrue(app.buttons["選んだ表現を単語帳に追加"].waitForExistence(timeout: 5))
        capture(prefix + "-selection")
        app.buttons["選んだ表現を単語帳に追加"].tap()
        app.buttons["単語帳を見る"].tap()
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
        XCTAssertTrue(app.switches["settings.icloud"].waitForExistence(timeout: 5))
        capture(prefix + "-settings")
    }

}
