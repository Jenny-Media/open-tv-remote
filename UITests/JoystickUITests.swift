import XCTest
import UIKit

final class JoystickUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    private func launch(openMode: Bool = true) {
        app = XCUIApplication()
        app.launchArguments = ["-demo", "-jellyfin.enabled", "NO", "-page", "0", "-demoInputLog", "YES", "-demoEyesFree", openMode ? "YES" : "NO"]
        app.launch()
        if openMode { XCTAssertTrue(stick.waitForExistence(timeout: 10)) }
    }

    private var log: XCUIElement { app.staticTexts["eyesFreeInputLog"] }
    private var stick: XCUIElement { app.descendants(matching: .any).matching(identifier: "eyesFreeStick").firstMatch }
    private var count: Int { Int(log.label.split(separator: ":").first ?? "-1") ?? -1 }

    func testSwitchPersistentModes() {
        launch(openMode: false)
        selectMode("eyesFree", title: "Eyes-free")
        XCTAssertTrue(stick.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Eyes-free remote"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        selectMode("standard", title: "Directional pad")
        XCTAssertFalse(stick.exists)
    }

    func testTVAppsOpenOnDemandAndReturnToTheSameRemote() {
        launch()
        let apps = app.navigationBars["Apps"]
        XCTAssertFalse(apps.exists)
        XCTAssertFalse(app.staticTexts["TV Apps"].exists)

        app.buttons["TV Apps"].tap()
        XCTAssertTrue(apps.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open YouTube"].exists)

        apps.buttons["Done"].tap()
        XCTAssertTrue(stick.waitForExistence(timeout: 5))
        XCTAssertEqual(log.label, "0:None")
    }

    func testDownloadedTVArtworkFitsItsGridCell() {
        let artwork = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 125)).pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 125))
            UIColor.systemYellow.setFill()
            context.fill(CGRect(x: 20, y: 20, width: 40, height: 85))
        }
        app = XCUIApplication()
        app.launchArguments = ["-demo", "-jellyfin.enabled", "NO", "-page", "0", "-demoSheet", "apps",
                               "-demoAppArtworkURL", "data:image/png;base64,\(artwork.base64EncodedString())"]
        app.launch()

        let first = app.buttons["Open Artwork 1"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        let tiles = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Open Artwork ")).allElementsBoundByIndex
        XCTAssertGreaterThanOrEqual(tiles.count, 3)
        XCTAssertEqual(first.frame.height, 72, accuracy: 1)
        for (index, tile) in tiles.enumerated() {
            for neighbor in tiles.dropFirst(index + 1) {
                XCTAssertFalse(tile.frame.intersects(neighbor.frame))
            }
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "TV Apps with downloaded artwork"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testRotatingKeepsTheRemoteUsable() {
        let device = XCUIDevice.shared
        launch()
        let startingFrame = app.frame
        let originalOrientation = device.orientation
        defer {
            if originalOrientation.isValidInterfaceOrientation { device.orientation = originalOrientation }
        }
        device.orientation = originalOrientation == .landscapeRight ? .landscapeLeft : .landscapeRight

        if startingFrame.width < 500 && startingFrame.width < startingFrame.height {
            let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                self.app.frame.width > self.app.frame.height
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
        }
        XCTAssertTrue(app.buttons["TV Apps"].isHittable)
        XCTAssertTrue(app.buttons["Home"].isHittable)
        XCTAssertLessThan(app.buttons["Home"].frame.midY, stick.frame.midY)
        stick.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(log.label, "1:OK")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Eyes-free remote after rotation"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func selectMode(_ id: String, title: String) {
        let inline = app.buttons["remoteMode-" + id]
        let picker = app.buttons["remoteModePicker"]
        let available = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            inline.exists || picker.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [available], timeout: 10), .completed)
        if inline.exists {
            inline.tap()
        } else {
            picker.tap()
            app.buttons[title].tap()
        }
    }

    func testTapBackAndHome() {
        launch()
        stick.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).tap()
        XCTAssertEqual(log.label, "1:OK")
        let largeBack = app.buttons["eyesFreeBack"]
        (largeBack.exists ? largeBack : app.buttons["Back"]).tap()
        XCTAssertEqual(log.label, "2:Back")
        app.buttons["Home"].tap()
        XCTAssertEqual(log.label, "3:Home")
    }

    func testRestingThumbDoesNothing() {
        launch()
        stick.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).press(forDuration: 0.65)
        XCTAssertEqual(log.label, "0:None")
    }

    func testFloatingStickRepeatsAndStopsOnLift() {
        launch()
        let start = stick.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7))
        let end = start.withOffset(CGVector(dx: 70, dy: 0))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.9)
        XCTAssertTrue(log.label.hasSuffix(":Right"))
        let afterLift = count
        XCTAssertGreaterThanOrEqual(afterLift, 2)
        let noMore = NSPredicate { [weak self] _, _ in self?.count != afterLift }
        let expectation = XCTNSPredicateExpectation(predicate: noMore, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 0.6), .timedOut)
        XCTAssertTrue(log.label.hasSuffix(":Right"))
    }

    func testDraggingDoesNotSelect() {
        launch()
        let start = stick.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.6))
        let end = start.withOffset(CGVector(dx: 0, dy: -65))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(log.label.hasSuffix(":Up"))
        XCTAssertGreaterThanOrEqual(count, 1)
    }
}
