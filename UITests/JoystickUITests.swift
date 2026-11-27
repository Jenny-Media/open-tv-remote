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

    private func launch(openMode: Bool = true, additionalArguments: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-demo", "-jellyfin.enabled", "NO", "-page", "0", "-demoInputLog", "YES", "-demoEyesFree", openMode ? "YES" : "NO"]
        app.launchArguments += additionalArguments
        app.launch()
        if openMode { XCTAssertTrue(stick.waitForExistence(timeout: 10)) }
    }

    private var log: XCUIElement { app.staticTexts["eyesFreeInputLog"] }
    private var stick: XCUIElement { app.descendants(matching: .any).matching(identifier: "eyesFreeStick").firstMatch }
    private var count: Int { Int(log.label.split(separator: ":").first ?? "-1") ?? -1 }

    func testHapticFeedbackSettingReflectsTheConfiguredPreference() {
        for value in ["NO", "YES"] {
            launch(openMode: false, additionalArguments: ["-demoSheet", "settings", "-haptics.enabled", value])
            let haptics = app.switches["Haptic Feedback"]
            XCTAssertTrue(haptics.waitForExistence(timeout: 5))
            XCTAssertEqual(haptics.value as? String, value == "YES" ? "1" : "0")
            app.terminate()
        }
    }

    func testFirstRemoteGuideAfterPairingASavedTVCanBeSkippedAndReopened() {
        let arguments = ["-demoGuideTestProfile", UUID().uuidString]
        launch(openMode: false, additionalArguments: arguments + ["-demoUnpaired", "YES"])
        let offer = app.buttons["firstRemoteGuide"]
        let pair = app.buttons["Pair"]
        XCTAssertTrue(pair.waitForExistence(timeout: 5))
        XCTAssertFalse(offer.exists)
        pair.tap()
        let code = app.textFields["Pairing code"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        code.typeText("123456")
        XCTAssertTrue(offer.waitForExistence(timeout: 5))
        app.buttons["skipRemoteGuide"].tap()
        XCTAssertTrue(offer.waitForNonExistence(timeout: 5))
        selectMode("eyesFree", title: "Eyes-free")
        XCTAssertTrue(app.staticTexts["Drag to move · Tap for OK"].exists)

        app.terminate()
        launch(additionalArguments: arguments)
        XCTAssertFalse(app.buttons["firstRemoteGuide"].exists)

        app.buttons["Settings"].tap()
        let help = app.buttons["remoteGuideInSettings"]
        XCTAssertTrue(help.waitForExistence(timeout: 5))
        help.tap()
        XCTAssertTrue(app.navigationBars["How to use the remote"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Use the joystick"].exists)
    }

    func testPairingExplainsTheCodeBeforeTheUserStarts() {
        launch(openMode: false, additionalArguments: ["-demoUnpaired", "YES"])
        let explanation = app.staticTexts["Choose Pair, then enter the code shown on your TV."]
        XCTAssertTrue(explanation.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["Pairing code"].exists)
        app.buttons["Pair"].tap()
        XCTAssertTrue(app.textFields["Pairing code"].waitForExistence(timeout: 5))
    }

    func testCursorSettingsAreOnDemandAndTouchpadRemainsAvailable() {
        launch(openMode: false, additionalArguments: ["-demoLGCursor", "YES", "-padMode", "cursor"])
        let settings = app.buttons["lgCursorSettings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        let touchpad = app.descendants(matching: .any).matching(identifier: "lgCursorTouchpad").firstMatch
        XCTAssertTrue(touchpad.isHittable)
        XCTAssertFalse(app.buttons["Click"].exists)
        XCTAssertFalse(app.sliders["Cursor speed"].exists)
        XCTAssertFalse(app.switches["Reverse scrolling"].exists)

        settings.tap()
        let sheet = app.navigationBars["Cursor Settings"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["Cursor speed"].isHittable)
        XCTAssertTrue(app.switches["Reverse scrolling"].isHittable)
        sheet.buttons["Done"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        XCTAssertTrue(touchpad.isHittable)
        XCTAssertFalse(app.buttons["Click"].exists)
    }

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

        app.buttons["TV Apps"].tap()
        let youtube = app.buttons["Open YouTube"]
        XCTAssertTrue(youtube.waitForExistence(timeout: 5))
        youtube.tap()
        XCTAssertTrue(stick.waitForExistence(timeout: 5))
        XCTAssertFalse(apps.exists)
    }

    func testBookControlsSwapSidesAndRememberTheMainRemote() throws {
        try requireDuoPosture("book")
        launch()
        let swap = app.buttons["bookSwapSides"]
        XCTAssertTrue(swap.waitForExistence(timeout: 5))

        let remoteStartedOnLeft = stick.frame.midX < swap.frame.midX
        let volume = app.buttons["Volume up"]
        XCTAssertTrue(volume.isHittable)
        XCTAssertEqual(stick.frame.midX < volume.frame.midX, remoteStartedOnLeft)
        swap.tap()
        defer {
            if swap.isHittable && (stick.frame.midX < swap.frame.midX) != remoteStartedOnLeft { swap.tap() }
        }
        XCTAssertEqual(stick.frame.midX < swap.frame.midX, !remoteStartedOnLeft)
        XCTAssertEqual(log.label, "0:None")
        XCTAssertTrue(app.staticTexts["Volume"].isHittable)
        XCTAssertEqual(app.buttons.matching(identifier: "Volume up").count, 1)
        XCTAssertEqual(stick.frame.midX < volume.frame.midX, !remoteStartedOnLeft)
        volume.tap()
        XCTAssertEqual(log.label, "1:Volume up")
        XCTAssertFalse(app.navigationBars["Apps"].exists)
        app.buttons["TV Apps"].tap()
        XCTAssertTrue(app.navigationBars["Apps"].waitForExistence(timeout: 5))
        app.navigationBars["Apps"].buttons["Done"].tap()

        app.terminate()
        launch()
        XCTAssertTrue(swap.waitForExistence(timeout: 5))
        XCTAssertEqual(stick.frame.midX < swap.frame.midX, !remoteStartedOnLeft)
        XCTAssertEqual(stick.frame.midX < app.buttons["Volume up"].frame.midX, !remoteStartedOnLeft)
        XCTAssertEqual(log.label, "0:None")
    }

    func testBookPlaybackRepeatsWaitForThePreviousRequestAndStopOnRelease() throws {
        try requireDuoPosture("book")
        launch(additionalArguments: ["-demoInteractiveDelayMS", "900"])
        let forward = app.buttons["Fast forward"]
        XCTAssertTrue(forward.waitForExistence(timeout: 5))
        forward.press(forDuration: 1.0)
        XCTAssertEqual(log.label, "2:Fast forward")

        let unexpectedRepeat = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.count > 2
        }, object: nil)
        unexpectedRepeat.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [unexpectedRepeat], timeout: 0.5), .completed)
    }

    func testBookDirectionalHoldUsesCancellableRepeats() throws {
        try requireDuoPosture("book")
        launch(openMode: false, additionalArguments: ["-padMode", "standard", "-demoInteractiveDelayMS", "900"])
        let ok = app.buttons["OK"]
        XCTAssertTrue(ok.waitForExistence(timeout: 5))
        let target = ok.coordinate(withNormalizedOffset: CGVector(dx: 1.4, dy: 0.5))
        assertDelayedHoldSendsOneRepeat(log: app.staticTexts["demoPadInputLog"], key: "Right") {
            target.press(forDuration: 1)
        }
    }

    func testBookPlaybackStopsWhenTheTouchLeavesTheButton() throws {
        try requireDuoPosture("book")
        launch()
        let forward = app.buttons["Fast forward"]
        XCTAssertTrue(forward.waitForExistence(timeout: 5))
        let center = forward.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let outside = forward.coordinate(withNormalizedOffset: CGVector(dx: -0.35, dy: 0.5))
        center.press(forDuration: 0.15, thenDragTo: outside, withVelocity: .fast, thenHoldForDuration: 0.7)
        XCTAssertEqual(log.label, "1:Fast forward")
    }

    func testNarrowBookKeyboardActionsRemainReachableAfterSwappingSides() throws {
        try requireDuoPosture("book")
        launch(openMode: false, additionalArguments: ["-padMode", "keyboard", "-demoKeyboardWidth", "164"])
        let swap = app.buttons["bookSwapSides"]
        let clear = app.buttons["Clear"]
        let enter = app.buttons["Return"]
        XCTAssertTrue(swap.waitForExistence(timeout: 5))
        XCTAssertTrue(enter.waitForExistence(timeout: 5))
        let originalSide = enter.frame.midX < swap.frame.midX
        swap.tap()
        defer {
            if swap.isHittable && (enter.frame.midX < swap.frame.midX) != originalSide { swap.tap() }
        }
        XCTAssertEqual(enter.frame.midX < swap.frame.midX, !originalSide)
        let delete = try XCTUnwrap(app.buttons.matching(identifier: "Delete").allElementsBoundByIndex.first {
            abs($0.frame.midY - enter.frame.midY) < 2
        })
        for button in [clear, delete, enter] {
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            XCTAssertEqual(button.frame.midY, enter.frame.midY, accuracy: 2)
        }
        let keys = ["q", "w"]
        for key in keys {
            let button = app.buttons[key]
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            button.tap()
        }
        XCTAssertEqual(app.staticTexts["demoPadInputLog"].label, "2:w")
        clear.tap()
        delete.tap()
        enter.tap()
    }

    func testBookKeyboardDeleteUsesCancellableRepeats() throws {
        try requireDuoPosture("book")
        launch(openMode: false, additionalArguments: [
            "-padMode", "keyboard", "-demoKeyboardWidth", "164", "-demoInteractiveDelayMS", "900",
        ])
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        for key in ["q", "w", "e"] { app.buttons[key].tap() }
        let padLog = app.staticTexts["demoPadInputLog"]
        XCTAssertEqual(padLog.label, "3:e")
        assertDelayedHoldSendsOneRepeat(log: padLog, key: "Delete", expectedCount: 5) {
            delete.press(forDuration: 1)
        }
        app.buttons["Clear"].tap()
        XCTAssertEqual(padLog.label, "6:Delete")
    }

    func testTabletopKeypadMediaHoldUsesCancellableRepeats() throws {
        try requireDuoPosture("tabletop")
        launch(openMode: false, additionalArguments: ["-padMode", "keypad", "-demoInteractiveDelayMS", "900"])
        let forward = app.buttons["Fast forward"]
        XCTAssertTrue(forward.waitForExistence(timeout: 5))
        XCTAssertTrue(forward.isHittable)
        assertDelayedHoldSendsOneRepeat(log: app.staticTexts["demoPadInputLog"], key: "Fast forward") {
            forward.press(forDuration: 1)
        }
    }

    private func assertDelayedHoldSendsOneRepeat(log: XCUIElement, key: String, expectedCount: Int = 2, hold: () -> Void) {
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        hold()
        let expected = "\(expectedCount):\(key)"
        XCTAssertEqual(log.label, expected)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            log.label != expected
        }, object: nil)
        changed.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 0.5), .completed)
    }

    func testTabletopShowsTVStatusAboveTheRemoteAndPlayback() throws {
        try requireDuoPosture("tabletop")
        launch(additionalArguments: ["-demoForegroundAppPackage", "com.google.android.youtube.tv"])
        let tv = app.buttons["tabletopTVSelection"]
        XCTAssertTrue(tv.waitForExistence(timeout: 5))

        XCTAssertTrue(tv.label.contains("Living Room TV"))
        XCTAssertTrue(tv.label.contains("Connected"))
        let reportedApp = app.descendants(matching: .any)["tabletopForegroundApp"].firstMatch
        XCTAssertTrue(reportedApp.isHittable)
        XCTAssertEqual(reportedApp.label, "Last reported app, YouTube")
        let play = app.buttons["Play or pause"]
        let volume = app.buttons["Volume down"]
        XCTAssertTrue(play.isHittable)
        XCTAssertTrue(volume.isHittable)
        XCTAssertGreaterThan(stick.frame.midY, tv.frame.midY)
        XCTAssertLessThan(play.frame.maxY, stick.frame.minY)
        XCTAssertLessThan(volume.frame.maxY, stick.frame.minY)
        XCTAssertGreaterThan(stick.frame.width, app.windows.firstMatch.frame.width * 0.85)
        XCTAssertFalse(app.navigationBars["Apps"].exists)
        play.tap()
        XCTAssertEqual(log.label, "1:Play or pause")

        selectMode("keyboard", title: "Keyboard")
        XCTAssertTrue(app.buttons["q"].waitForExistence(timeout: 5))
        XCTAssertTrue(play.isHittable)
        XCTAssertTrue(volume.isHittable)
        XCTAssertLessThan(play.frame.maxY, app.buttons["q"].frame.minY)
        play.tap()
    }

    func testTabletopLGCursorLeavesRoomForTheTouchpad() throws {
        try requireDuoPosture("tabletop")
        launch(openMode: false, additionalArguments: ["-demoLGCursor", "YES", "-padMode", "cursor"])
        let touchpad = app.descendants(matching: .any)["lgCursorTouchpad"].firstMatch
        let settings = app.buttons["lgCursorSettings"]
        let volume = app.buttons["Volume up"]
        XCTAssertTrue(touchpad.waitForExistence(timeout: 5))
        XCTAssertTrue(touchpad.isHittable)
        XCTAssertGreaterThan(touchpad.frame.width, app.windows.firstMatch.frame.width * 0.72)
        XCTAssertTrue(volume.isHittable)
        XCTAssertLessThan(volume.frame.maxY, touchpad.frame.minY)
        XCTAssertEqual(app.buttons.matching(identifier: "Back").count, 1)
        XCTAssertTrue(settings.isHittable)
        settings.tap()
        XCTAssertTrue(app.navigationBars["Cursor Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Scroll with two fingers or the side strip"].exists)
    }

    func testTabletopMediaStaysPutWhenTheReportedAppIsMissing() throws {
        try requireDuoPosture("tabletop")
        launch(additionalArguments: ["-demoForegroundAppPackage", "com.google.android.youtube.tv"])
        XCTAssertTrue(app.descendants(matching: .any)["tabletopForegroundApp"].firstMatch.isHittable)
        let volumeWithApp = app.buttons["Volume up"].frame
        let playbackWithApp = app.buttons["Play or pause"].frame
        XCTAssertGreaterThan(volumeWithApp.height, 0)
        XCTAssertGreaterThan(playbackWithApp.height, 0)
        app.terminate()

        launch(additionalArguments: ["-demoForegroundAppPackage", "example.unrecognized"])
        XCTAssertFalse(app.descendants(matching: .any)["tabletopForegroundApp"].firstMatch.exists)
        let volume = app.buttons["Volume up"]
        let playback = app.buttons["Play or pause"]
        XCTAssertTrue(volume.isHittable)
        XCTAssertTrue(playback.isHittable)
        XCTAssertEqual(volume.frame.midY, volumeWithApp.midY, accuracy: 1)
        XCTAssertEqual(playback.frame.midY, playbackWithApp.midY, accuracy: 1)
    }

    func testFoldedVolumeControlsInPortraitAndLandscape() throws {
        try requireDuoPosture("closed")
        let device = XCUIDevice.shared
        let originalOrientation = device.orientation
        defer {
            if originalOrientation.isValidInterfaceOrientation { device.orientation = originalOrientation }
        }
        for orientation: UIDeviceOrientation in [.portrait, .landscapeRight] {
            device.orientation = orientation
            try assertVolumeControlsInGestureModes(isLandscape: orientation.isLandscape)
        }
    }

    func testFlatLandscapeVolumeControlsInGestureModes() throws {
        try requireDuoPosture("flat-landscape")
        try assertVolumeControlsInGestureModes(isLandscape: true)
    }

    private func assertVolumeControlsInGestureModes(isLandscape: Bool) throws {
        launch()
        try assertVolumeControls(inputLog: log, isLandscape: isLandscape)
        app.terminate()

        launch(openMode: false, additionalArguments: ["-demoLGCursor", "YES", "-padMode", "cursor"])
        XCTAssertTrue(app.descendants(matching: .any)["lgCursorTouchpad"].firstMatch.waitForExistence(timeout: 5))
        try assertVolumeControls(inputLog: app.staticTexts["demoPadInputLog"], isLandscape: isLandscape)
        app.terminate()
    }

    private func assertVolumeControls(inputLog: XCUIElement, isLandscape: Bool) throws {
        let expectedLayout = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = self.app.windows.firstMatch.frame
            return !frame.isEmpty && (isLandscape ? frame.width > frame.height : frame.height > frame.width)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectedLayout], timeout: 5), .completed)
        let increase = app.buttons["Volume up"]
        let decrease = app.buttons["Volume down"]
        let windowFrame = app.windows.firstMatch.frame
        let volumeGroup = increase.frame.union(decrease.frame)
        XCTAssertGreaterThan(volumeGroup.midY, windowFrame.minY + windowFrame.height * 2 / 3)
        for button in [increase, decrease] {
            XCTAssertTrue(button.isHittable)
            let capture = button.screenshot().image
            let bounds = try XCTUnwrap(coloredBounds(in: capture) { red, green, blue in
                green > 120 && Int(green) - Int(red) > 32 && Int(green) - Int(blue) > 18
            }, "Missing visible volume glyph on \(button.label)")
            let aspect = bounds.width * capture.size.width / (bounds.height * capture.size.height)
            // The speaker extends the plus horizontally and adds height to the minus.
            XCTAssertTrue((1.25...2.8).contains(aspect), "Expected a speaker glyph on \(button.label); aspect was \(aspect)")
        }
        increase.tap()
        XCTAssertEqual(inputLog.label, "1:Volume up")
        decrease.tap()
        XCTAssertEqual(inputLog.label, "2:Volume down")
    }

    func testFlatLandscapeEnlargesTheDirectionalPad() throws {
        try requireDuoPosture("flat-landscape")
        launch(openMode: false, additionalArguments: ["-padMode", "standard"])
        let ok = app.buttons["OK"]
        XCTAssertTrue(ok.waitForExistence(timeout: 5))
        // The old 340-point pad cap limited OK to 136 points.
        XCTAssertGreaterThanOrEqual(ok.frame.width, 140)
        XCTAssertTrue(ok.isHittable)
    }

    private func requireDuoPosture(_ posture: String) throws {
        guard ProcessInfo.processInfo.environment["OPEN_REMOTE_DUO_POSTURE"] == posture else {
            throw XCTSkip("Select the Duo posture and set TEST_RUNNER_OPEN_REMOTE_DUO_POSTURE=\(posture) in xcodebuild's environment.")
        }
    }

    func testTVAppsStaysOpenWhenPairingIsRequired() {
        launch(additionalArguments: ["-demoUnpaired", "YES"])
        app.buttons["TV Apps"].tap()
        let youtube = app.buttons["Open YouTube"]
        XCTAssertTrue(youtube.waitForExistence(timeout: 5))
        youtube.tap()
        XCTAssertTrue(app.staticTexts["Pair with your TV to open apps."].waitForExistence(timeout: 5))
        XCTAssertTrue(youtube.exists)
        XCTAssertTrue(app.navigationBars["Apps"].exists)
    }

    func testPowerHoldSendsFullShutdownWithoutAShortPress() {
        launch()
        let power = app.buttons["Power"]
        XCTAssertTrue(power.isHittable)
        power.tap()
        XCTAssertEqual(log.label, "1:Power")
        power.press(forDuration: 1.1)
        XCTAssertEqual(log.label, "2:Turn off")
    }

    func testMovingDuringPowerHoldSendsNoCommand() {
        launch()
        let power = app.buttons["Power"]
        XCTAssertTrue(power.isHittable)
        let center = power.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let moved = center.withOffset(CGVector(dx: 15, dy: 0))
        center.press(forDuration: 0.1, thenDragTo: moved, withVelocity: .default, thenHoldForDuration: 0.8)
        XCTAssertEqual(log.label, "0:None")
        power.tap()
        XCTAssertEqual(log.label, "1:Power")
    }

    func testPairingKeepsTheCodeAndCancelReachableAfterRotation() {
        let device = XCUIDevice.shared
        let originalOrientation = device.orientation
        defer {
            if originalOrientation.isValidInterfaceOrientation { device.orientation = originalOrientation }
        }
        device.orientation = .portrait
        launch(openMode: false, additionalArguments: ["-demoUnpaired", "YES"])
        let startingFrame = app.frame
        app.buttons["Pair"].tap()

        let field = app.textFields["Pairing code"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText("AB12C")

        device.orientation = .landscapeRight
        waitForLandscapeIfExpected(startingFrame)
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(cancel.isHittable)
        XCTAssertEqual(field.value as? String, "AB12C")
        field.typeText("0")

        let error = app.staticTexts["Incorrect pairing code."]
        let visibleError = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in error.isHittable }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visibleError], timeout: 5), .completed)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(cancel.isHittable)
        cancel.tap()
        XCTAssertTrue(app.buttons["Pair"].waitForExistence(timeout: 5))
    }

    func testDownloadedTVArtworkFitsItsGridCell() throws {
        try assertArtworkFitsTiles(size: CGSize(width: 80, height: 125))
        app.terminate()
        try assertArtworkFitsTiles(size: CGSize(width: 175, height: 42))
    }

    private func assertArtworkFitsTiles(size: CGSize) throws {
        let artwork = UIGraphicsImageRenderer(size: size).pngData { context in
            let rect = CGRect(origin: .zero, size: size)
            UIColor.blue.setFill()
            context.fill(rect)
            UIColor.systemYellow.setFill()
            context.fill(rect.insetBy(dx: size.width * 0.25, dy: size.height * 0.16))
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
        let artworkLoaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.blueArtworkBounds(in: first.screenshot().image) != nil
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [artworkLoaded], timeout: 5), .completed)
        for tile in tiles {
            let artwork = try XCTUnwrap(blueArtworkBounds(in: tile.screenshot().image), "Missing artwork in \(tile.label)")
            let frame = tile.frame
            let points = artwork.applying(CGAffineTransform(scaleX: frame.width, y: frame.height))
            let expectedScale = min((frame.width - 16) / size.width, (frame.height - 16) / size.height)
            XCTAssertEqual(points.width, size.width * expectedScale, accuracy: 2)
            XCTAssertEqual(points.height, size.height * expectedScale, accuracy: 2)
            XCTAssertEqual(points.midX, frame.width / 2, accuracy: 2)
            XCTAssertEqual(points.midY, frame.height / 2, accuracy: 2)
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "TV Apps with downloaded artwork \(Int(size.width))×\(Int(size.height))"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func blueArtworkBounds(in capture: UIImage) -> CGRect? {
        coloredBounds(in: capture) { $0 < 70 && $1 < 100 && $2 > 180 }
    }

    /// Returns the bounds of matching pixels as fractions of the captured image.
    private func coloredBounds(in capture: UIImage, matching: (UInt8, UInt8, UInt8) -> Bool) -> CGRect? {
        // Draw through UIImage so orientation metadata is applied before measuring pixels.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let oriented = UIGraphicsImageRenderer(size: capture.size, format: format)
            .image { _ in capture.draw(at: .zero) }
        guard let image = oriented.cgImage, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = image.width
        let height = image.height
        let stride = width * 4
        var pixels = [UInt8](repeating: 0, count: stride * height)
        return pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: stride,
                                          space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                              CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            var minX = width
            var minY = height
            var maxX = -1
            var maxY = -1
            for y in 0..<height {
                for x in 0..<width {
                    let offset = y * stride + x * 4
                    guard matching(bytes[offset], bytes[offset + 1], bytes[offset + 2]) else { continue }
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
            guard maxX >= minX, maxY >= minY else { return nil }
            return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
                .applying(CGAffineTransform(scaleX: 1 / CGFloat(width), y: 1 / CGFloat(height)))
        }
    }

    func testRotatingKeepsTheRemoteUsable() {
        let device = XCUIDevice.shared
        let originalOrientation = device.orientation
        defer {
            if originalOrientation.isValidInterfaceOrientation { device.orientation = originalOrientation }
        }
        device.orientation = .portrait
        launch()
        let startingFrame = app.frame
        device.orientation = .landscapeRight
        waitForLandscapeIfExpected(startingFrame)
        XCTAssertTrue(app.buttons["TV Apps"].isHittable)
        let home = app.buttons["Home"]
        let stick = self.stick
        let layoutReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            home.isHittable && stick.isHittable && home.frame.midY < stick.frame.midY
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [layoutReady], timeout: 5), .completed)
        stick.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(log.label, "1:OK")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Eyes-free remote after rotation"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func waitForLandscapeIfExpected(_ startingFrame: CGRect) {
        // The Duo's inner display can keep a tall app window after a physical rotation.
        guard UIDevice.current.userInterfaceIdiom == .pad ||
              (startingFrame.width < 500 && startingFrame.width < startingFrame.height) else { return }
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.app.frame.width > self.app.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
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
