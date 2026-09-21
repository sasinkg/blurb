//
//  blurbUITests.swift
//  blurbUITests
//
//  Created by Sasin on 8/26/26.
//

import XCTest

final class blurbUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testEmailSignInFormAndCancellation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppStoreScreenshot", "welcome"]
        app.launch()

        let emailOption = app.buttons["continueWithEmail"]
        XCTAssertTrue(emailOption.waitForExistence(timeout: 10))
        if !emailOption.isHittable { app.swipeUp() }
        emailOption.tap()

        let email = app.textFields["emailAddress"]
        let password = app.secureTextFields["emailPassword"]
        let submit = app.buttons["emailAuthSubmit"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        XCTAssertFalse(submit.isEnabled)
        app.buttons["Forgot password?"].tap()
        XCTAssertTrue(app.staticTexts["emailAuthError"].exists)

        email.tap()
        email.typeText("reviewer@example.com")
        XCTAssertFalse(submit.isEnabled)
        XCTAssertTrue(app.buttons["Forgot password?"].isEnabled)
        password.tap()
        password.typeText("ui-test-only")
        XCTAssertTrue(submit.isEnabled)

        // Do not submit credentials to the configured Firebase project.
        app.buttons["Cancel"].tap()
        XCTAssertTrue(emailOption.waitForExistence(timeout: 5))
        emailOption.tap()
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        XCTAssertFalse(submit.isEnabled)
        XCTAssertEqual(email.value as? String, "you@example.com")
    }

    @MainActor
    func testSignUpRequiresPasswordConfirmation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppStoreScreenshot", "welcome"]
        app.launch()
        let emailOption = app.buttons["continueWithEmail"]
        XCTAssertTrue(emailOption.waitForExistence(timeout: 10))
        if !emailOption.isHittable { app.swipeUp() }
        emailOption.tap()
        app.buttons["emailAuthSwitchMode"].tap()
        let confirmation = app.secureTextFields["emailPasswordConfirmation"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        let email = app.textFields["emailAddress"]
        email.tap()
        email.typeText("new-user@example.com")
        let password = app.secureTextFields["emailPassword"]
        password.tap()
        password.typeText("ui-test-only")
        let submit = app.buttons["emailAuthSubmit"]
        XCTAssertFalse(submit.isEnabled)
        confirmation.tap()
        confirmation.typeText("ui-test-only")
        XCTAssertTrue(submit.isEnabled)
        // Do not create real accounts in the configured Firebase project.
        app.buttons["Cancel"].tap()
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
