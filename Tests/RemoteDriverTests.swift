import Foundation
import Observation
import Testing
@testable import JoystickCore

@MainActor
private func waitUntil(_ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + .seconds(2)
    while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(1)) }
    #expect(condition())
}

@Suite("Interactive transport ordering and recovery", .serialized)
@MainActor
struct RemoteDriverTests {
    @Test(arguments: ["legacy-token", ""])
    func samsungReconnectUsesTheNameAndTokenOfAnExistingPairing(_ token: String) throws {
        LocalWebSocket.instances = []
        let oldRecord = Data("""
            {"name":"Samsung","brand":"samsung","host":"192.0.2.40","token":"\(token)","isPaired":false}
            """.utf8)
        let saved = try JSONDecoder().decode(TVDevice.self, from: oldRecord)
        #expect(saved.samsungClientName == nil)
        let driver = SamsungDriver(device: saved)
        defer { driver.disconnect() }
        driver.connect()

        let socket = try #require(LocalWebSocket.instances.last)
        let query = URLComponents(url: socket.url, resolvingAgainstBaseURL: false)?.queryItems
        let encodedName = try #require(query?.first { $0.name == "name" }?.value)
        let clientName = Data(base64Encoded: encodedName).flatMap { String(data: $0, encoding: .utf8) }
        #expect(clientName == "Remote Lab")
        #expect(query?.first { $0.name == "token" }?.value == (token.isEmpty ? nil : token))
        #expect(driver.state == .connecting)
    }

    @Test(arguments: [false, true])
    func samsungExplicitPairingSavesTheNewNameForFutureConnections(_ tokenless: Bool) throws {
        LocalWebSocket.instances = []
        let saved = TVDevice(name: "Samsung", brand: .samsung, host: "192.0.2.40", token: "old-token")
        let driver = SamsungDriver(device: saved)
        driver.pair()
        let pairingSocket = try #require(LocalWebSocket.instances.last)
        let pairingQuery = URLComponents(url: pairingSocket.url, resolvingAgainstBaseURL: false)?.queryItems
        let encodedName = Data("Just a TV Remote".utf8).base64EncodedString()
        #expect(pairingQuery?.first { $0.name == "name" }?.value == encodedName)
        #expect(pairingQuery?.first { $0.name == "token" } == nil)
        #expect(driver.state == .pairing(.acceptOnTV))

        let payload = tokenless ? "{}" : "{\"token\":\"new-token\"}"
        pairingSocket.onText?("{\"event\":\"ms.channel.connect\",\"data\":\(payload)}")
        #expect(driver.device.samsungClientName == "Just a TV Remote")
        #expect(driver.device.token == (tokenless ? "" : "new-token"))
        let restored = try JSONDecoder().decode(TVDevice.self, from: JSONEncoder().encode(driver.device))
        driver.disconnect()

        let reconnecting = SamsungDriver(device: restored)
        defer { reconnecting.disconnect() }
        reconnecting.connect()
        let socket = try #require(LocalWebSocket.instances.last)
        let query = URLComponents(url: socket.url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.first { $0.name == "name" }?.value == encodedName)
        #expect(query?.first { $0.name == "token" }?.value == (tokenless ? nil : "new-token"))
        #expect(reconnecting.state == .connecting)
    }

    @Test func rokuDisconnectInvalidatesEveryQueuedNormalCommandAndOldResponse() async {
        let driver = await connectedRoku()
        driver.send(.up)
        await waitUntil { LocalHTTP.started.count == 1 }
        driver.send(.down)
        driver.send(.left)
        driver.disconnect()
        LocalHTTP.complete("/keypress/Up")
        try? await Task.sleep(for: .milliseconds(30))
        #expect(LocalHTTP.started == ["/keypress/Up"])
        #expect(driver.state == .idle)
        LocalHTTP.reset()
    }

    private func connectedRoku(isTV: Bool? = nil, playerVolume: Bool? = nil) async -> RokuDriver {
        LocalHTTP.reset()
        let tv = isTV.map { "<is-tv>\($0)</is-tv>" } ?? ""
        let volume = playerVolume.map { "<supports-audio-volume-control>\($0)</supports-audio-volume-control>" } ?? ""
        LocalHTTP.deviceInfo = Data("<device-info>\(tv)\(volume)</device-info>".utf8)
        let driver = RokuDriver(device: TVDevice(name: "Test Roku", brand: .roku, host: "192.0.2.10"))
        driver.connect()
        await waitUntil { driver.state == .connected }
        return driver
    }

    @Test(arguments: [nil, false, true] as [Bool?]) func rokuOnlySendsTunerCommandsToTVs(_ isTV: Bool?) async {
        let driver = await connectedRoku(isTV: isTV)
        #expect(driver.supports(.input) == (isTV == true))
        driver.send(.input)
        if isTV == true {
            await waitUntil { LocalHTTP.started == ["/keypress/InputTuner"] }
            LocalHTTP.complete("/keypress/InputTuner")
        } else {
            // A following supported command acts as a barrier in the same queue.
            driver.send(.back)
            await waitUntil { !LocalHTTP.started.isEmpty }
            #expect(LocalHTTP.started == ["/keypress/Back"])
            if let path = LocalHTTP.started.first { LocalHTTP.complete(path) }
        }
        driver.disconnect()
    }

    @Test(arguments: [nil, false, true] as [Bool?]) func rokuPlayerUsesReportedAudioCapability(_ playerVolume: Bool?) async {
        let driver = await connectedRoku(isTV: false, playerVolume: playerVolume)
        defer { driver.disconnect() }
        for key in [RemoteKey.volumeUp, .volumeDown, .mute] {
            #expect(driver.supports(key) == (playerVolume != false))
        }
        driver.send(.mute)
        driver.send(.back)
        await waitUntil { !LocalHTTP.started.isEmpty }
        if playerVolume != false {
            #expect(LocalHTTP.started == ["/keypress/VolumeMute"])
            LocalHTTP.complete("/keypress/VolumeMute")
            await waitUntil { LocalHTTP.started.count == 2 }
        } else {
            #expect(LocalHTTP.started == ["/keypress/Back"])
        }
        #expect(LocalHTTP.started.last == "/keypress/Back")
        LocalHTTP.complete("/keypress/Back")
    }

    @Test func rokuTVKeepsVolumeWhenPlayerFlagIsFalse() async {
        let driver = await connectedRoku(isTV: true, playerVolume: false)
        #expect(driver.supports(.input))
        #expect(driver.supports(.mute))
        driver.disconnect()
    }

    @Test func rokuTunerCapabilityNotifiesAfterKeypressConnectsFirst() async {
        LocalHTTP.reset()
        LocalHTTP.delaysDeviceInfo = true
        LocalHTTP.deviceInfo = Data("<device-info><user-device-name>Test Roku</user-device-name><is-tv>true</is-tv></device-info>".utf8)
        let driver = RokuDriver(device: TVDevice(name: "Test Roku", brand: .roku, host: "192.0.2.10"))
        driver.connect()
        await waitUntil { LocalHTTP.deviceInfoRequest != nil }
        driver.send(.home)
        await waitUntil { LocalHTTP.started == ["/keypress/Home"] }
        LocalHTTP.complete("/keypress/Home")
        await waitUntil { driver.state == .connected }

        await confirmation("The view is notified when tuner support becomes known") { changed in
            let supportsTuner = withObservationTracking {
                driver.supports(.input)
            } onChange: {
                changed()
            }
            #expect(!supportsTuner)
            LocalHTTP.completeDeviceInfo()
            await waitUntil { driver.supports(.input) }
            #expect(driver.state == .connected)
        }
        driver.disconnect()
    }

    @Test(arguments: [false, true])
    func rokuRetriesDeviceInfoOnceWhenCommandsProveReachability(_ homeSucceedsFirst: Bool) async {
        LocalHTTP.reset()
        LocalHTTP.delaysDeviceInfo = true
        LocalHTTP.deviceInfo = Data("<device-info><is-tv>true</is-tv></device-info>".utf8)
        let driver = RokuDriver(device: TVDevice(name: "Test Roku", brand: .roku, host: "192.0.2.10"))
        defer {
            driver.disconnect()
            LocalHTTP.reset()
        }
        driver.connect()
        await waitUntil { LocalHTTP.deviceInfoRequest != nil }
        if !homeSucceedsFirst {
            LocalHTTP.completeDeviceInfo(success: false)
            await waitUntil { if case .failed = driver.state { true } else { false } }
            #expect(LocalHTTP.deviceInfoReads == 1)
        }
        driver.send(.home)
        await waitUntil { LocalHTTP.started == ["/keypress/Home"] }
        LocalHTTP.complete("/keypress/Home")
        await waitUntil { driver.state == .connected }
        if homeSucceedsFirst {
            #expect(LocalHTTP.deviceInfoReads == 1)
            LocalHTTP.completeDeviceInfo(success: false)
        }
        await waitUntil { LocalHTTP.deviceInfoReads == 2 && LocalHTTP.deviceInfoRequest != nil }
        #expect(driver.state == .connected)
        #expect(!driver.supports(.input))

        // A pending lookup must leave the command queue free and must not start another read.
        driver.send(.back)
        await waitUntil { LocalHTTP.started == ["/keypress/Home", "/keypress/Back"] }
        LocalHTTP.complete("/keypress/Back")
        LocalHTTP.completeDeviceInfo()
        await waitUntil { driver.supports(.input) }
        #expect(LocalHTTP.deviceInfoReads == 2)
        #expect(driver.state == .connected)
    }

    @Test func rokuKeepsConfirmedVolumeSupportWhenTheRetryFailsOrTheFieldIsMissing() async {
        let driver = await connectedRoku(isTV: false, playerVolume: false)
        defer {
            driver.disconnect()
            LocalHTTP.reset()
        }
        #expect(!driver.supports(.volumeUp))
        LocalHTTP.delaysDeviceInfo = true
        driver.connect()
        await waitUntil { LocalHTTP.deviceInfoRequest != nil }
        LocalHTTP.completeDeviceInfo(success: false)
        await waitUntil { if case .failed = driver.state { true } else { false } }
        driver.send(.home)
        await waitUntil { LocalHTTP.started == ["/keypress/Home"] }
        LocalHTTP.complete("/keypress/Home")
        await waitUntil { LocalHTTP.deviceInfoReads == 3 && LocalHTTP.deviceInfoRequest != nil }
        LocalHTTP.completeDeviceInfo(success: false)

        driver.send(.back)
        driver.send(.select)
        await waitUntil { LocalHTTP.started.last == "/keypress/Back" }
        LocalHTTP.complete("/keypress/Back")
        await waitUntil { LocalHTTP.started.last == "/keypress/Select" }
        LocalHTTP.complete("/keypress/Select")
        #expect(LocalHTTP.deviceInfoReads == 3)
        #expect(LocalHTTP.deviceInfoRequest == nil)
        #expect(driver.state == .connected)
        #expect(!driver.supports(.volumeUp))

        LocalHTTP.deviceInfo = Data("<device-info><is-tv>false</is-tv></device-info>".utf8)
        driver.connect()
        await waitUntil { LocalHTTP.deviceInfoReads == 4 && LocalHTTP.deviceInfoRequest != nil }
        LocalHTTP.completeDeviceInfo()
        await waitUntil { driver.state == .connected }
        #expect(!driver.supports(.volumeUp))
    }

    @Test func rokuDropsVolumeQueuedBeforeDeviceInfoReportsItUnsupported() async {
        let driver = await connectedRoku(isTV: false, playerVolume: true)
        LocalHTTP.delaysDeviceInfo = true
        LocalHTTP.deviceInfo = Data("<device-info><is-tv>false</is-tv><supports-audio-volume-control>false</supports-audio-volume-control></device-info>".utf8)
        defer {
            driver.disconnect()
            LocalHTTP.reset()
        }
        driver.connect()
        await waitUntil { LocalHTTP.deviceInfoRequest != nil }
        driver.send(.home)
        await waitUntil { LocalHTTP.started == ["/keypress/Home"] }
        #expect(driver.supports(.mute))
        driver.send(.mute)
        driver.send(.back)
        LocalHTTP.completeDeviceInfo()
        await waitUntil { !driver.supports(.mute) }
        LocalHTTP.complete("/keypress/Home")
        await waitUntil { LocalHTTP.started.count == 2 }
        #expect(LocalHTTP.started == ["/keypress/Home", "/keypress/Back"])
        LocalHTTP.complete("/keypress/Back")
    }

    @Test func rokuReportsTimeoutAfterDirectionalLift() async {
        let driver = await connectedRoku()
        let sender = JoystickSender(send: { key, request in
            await driver.sendInteractive(key, request: request)
        })
        sender.hold(.right)
        await waitUntil { LocalHTTP.started == ["/keypress/Right"] }
        sender.release()
        LocalHTTP.complete("/keypress/Right", status: nil)
        await waitUntil { if case .failed = driver.state { return true }; return false }
        #expect(driver.state == .failed("Couldn't reach the Roku."))
        #expect(LocalHTTP.started == ["/keypress/Right"])
        sender.stop()
        driver.disconnect()
    }

    @Test func rokuReportsAccessDeniedAfterDirectionalLift() async {
        let driver = await connectedRoku()
        let sender = JoystickSender(send: { key, request in
            await driver.sendInteractive(key, request: request)
        })
        sender.hold(.right)
        await waitUntil { LocalHTTP.started == ["/keypress/Right"] }
        sender.release()
        LocalHTTP.complete("/keypress/Right", status: 403)
        await waitUntil { if case .failed = driver.state { return true }; return false }
        if case .failed(let message) = driver.state {
            #expect(message.contains("blocking remote apps"))
        } else { Issue.record("The current connection failure was hidden by input cancellation") }
        sender.stop()
        driver.disconnect()
    }

    @Test func rokuIgnoresOldFailureAfterAReplacementConnection() async {
        let driver = await connectedRoku()
        let request = RemoteInputRequest()
        let operation = Task { await driver.sendInteractive(.right, request: request) }
        await waitUntil { LocalHTTP.started.count == 1 }
        driver.connect()
        await waitUntil { driver.state == .connected }
        LocalHTTP.complete("/keypress/Right", status: nil)
        await operation.value
        #expect(driver.state == .connected)
        driver.disconnect()
    }

    @Test func rokuDoesNotReportLocalTaskCancellationAsATVFailure() async {
        let driver = await connectedRoku()
        let operation = Task { await driver.sendInteractive(.right, request: RemoteInputRequest()) }
        await waitUntil { LocalHTTP.started.count == 1 }
        operation.cancel()
        LocalHTTP.complete("/keypress/Right", status: nil)
        await operation.value
        #expect(driver.state == .connected)
        driver.disconnect()
    }

    @Test func rokuNormalAndInteractiveCommandsShareTheirOrder() async {
        let driver = await connectedRoku()
        driver.send(.up)
        await waitUntil { LocalHTTP.started.count == 1 }
        driver.send(.down)
        let request = RemoteInputRequest()
        let interactive = Task { await driver.sendInteractive(.back, request: request) }
        try? await Task.sleep(for: .milliseconds(20))
        #expect(LocalHTTP.started == ["/keypress/Up"])
        LocalHTTP.complete("/keypress/Up")
        await waitUntil { LocalHTTP.started.count == 2 }
        #expect(LocalHTTP.started.last == "/keypress/Down")
        LocalHTTP.complete("/keypress/Down")
        await waitUntil { LocalHTTP.started.count == 3 }
        #expect(LocalHTTP.started == ["/keypress/Up", "/keypress/Down", "/keypress/Back"])
        LocalHTTP.complete("/keypress/Back")
        await interactive.value
        #expect(LocalHTTP.completions.isEmpty)
    }

    @Test func rokuOnlyAccountsForDeleteAtActualDispatch() async {
        let driver = await connectedRoku(isTV: false)
        defer {
            driver.disconnect()
            LocalHTTP.reset()
        }
        driver.send(.home)
        await waitUntil { LocalHTTP.started == ["/keypress/Home"] }
        var dispatched = 0
        let queued = RemoteInputRequest()
        queued.onDispatch = { dispatched += 1 }
        let staleOperation = Task { await driver.sendInteractive(.backspace, request: queued) }
        await Task.yield()
        queued.cancel()
        LocalHTTP.complete("/keypress/Home")
        await staleOperation.value
        #expect(dispatched == 0)
        #expect(LocalHTTP.started == ["/keypress/Home"])

        let active = RemoteInputRequest()
        active.onDispatch = { dispatched += 1 }
        let operation = Task { await driver.sendInteractive(.backspace, request: active) }
        await waitUntil { LocalHTTP.started.last == "/keypress/Backspace" }
        #expect(dispatched == 1)
        active.cancel()
        LocalHTTP.complete("/keypress/Backspace")
        await operation.value
        #expect(dispatched == 1)
    }

    @Test func rokuFinishesTheDispatchedRepeatBeforeTheNextDeliberateCommand() async {
        let driver = await connectedRoku(isTV: false)
        defer {
            driver.disconnect()
            LocalHTTP.reset()
        }
        let request = RemoteInputRequest(isRepeat: true)
        let repeatOperation = Task { await driver.sendInteractive(.backspace, request: request) }
        await waitUntil { LocalHTTP.started == ["/keypress/Backspace"] }
        request.cancel()
        driver.send(.back)
        await Task.yield()
        #expect(LocalHTTP.started == ["/keypress/Backspace"])
        LocalHTTP.complete("/keypress/Backspace", status: 403)
        await repeatOperation.value
        if case .failed(let message) = driver.state {
            #expect(message.contains("blocking remote apps"))
        } else { Issue.record("Lift suppressed the accepted command's HTTP response") }
        await waitUntil { LocalHTTP.started == ["/keypress/Backspace", "/keypress/Back"] }
        LocalHTTP.complete("/keypress/Back")
    }

    @Test func rokuDropsARepeatWhenItsRemoteContextChangesWhileQueued() async {
        let driver = await connectedRoku(isTV: false)
        defer {
            driver.disconnect()
            LocalHTTP.reset()
        }
        driver.send(.home)
        await waitUntil { LocalHTTP.started == ["/keypress/Home"] }
        var isCurrent = true
        let request = RemoteInputRequest(isRepeat: true, isCurrent: { isCurrent })
        let repeatOperation = Task { await driver.sendInteractive(.fastForward, request: request) }
        await Task.yield()
        isCurrent = false
        LocalHTTP.complete("/keypress/Home")
        await repeatOperation.value
        #expect(LocalHTTP.started == ["/keypress/Home"])
    }

    @Test func rokuDropsAQueuedRepeatWhenAppsSheetOpens() async {
        let driver = await connectedRoku(isTV: false)
        defer {
            driver.disconnect()
            LocalHTTP.reset()
        }
        driver.send(.home)
        await waitUntil { LocalHTTP.started == ["/keypress/Home"] }
        var availability = RemoteInputAvailability(state: .connected)
        let request = RemoteInputRequest(isRepeat: true, isCurrent: { availability.allowsCommands })
        let repeatOperation = Task { await driver.sendInteractive(.backspace, request: request) }
        await Task.yield()
        availability.showingApps = true
        LocalHTTP.complete("/keypress/Home")
        await repeatOperation.value
        #expect(LocalHTTP.started == ["/keypress/Home"])
    }

    @Test func rokuDropsAQueuedRepeatAfterItsHoldDeadline() async {
        let driver = await connectedRoku(isTV: false)
        defer {
            driver.disconnect()
            LocalHTTP.reset()
        }
        driver.send(.home)
        await waitUntil { LocalHTTP.started == ["/keypress/Home"] }
        let deadline = ContinuousClock.now + .milliseconds(50)
        let request = RemoteInputRequest(isRepeat: true, deadline: deadline)
        let repeatOperation = Task { await driver.sendInteractive(.fastForward, request: request) }
        try? await ContinuousClock().sleep(until: deadline)
        #expect(!request.canDispatch)
        driver.send(.back)
        LocalHTTP.complete("/keypress/Home")
        await waitUntil { LocalHTTP.started.count == 2 }
        #expect(LocalHTTP.started == ["/keypress/Home", "/keypress/Back"])
        if let started = LocalHTTP.started.last { LocalHTTP.complete(started) }
        await repeatOperation.value
    }

    @Test func rokuDiscardsAQueuedDuoRepeatAcrossConnectionLossAndAllowsTheNextTick() async {
        let driver = await connectedRoku()
        defer { driver.disconnect() }
        driver.send(.home)
        await waitUntil { LocalHTTP.started == ["/keypress/Home"] }
        driver.send(.back)

        let request = RemoteInputRequest(isRepeat: true, requiresCurrentConnection: true)
        var repeatStarted = false
        var repeatFinished = false
        let stale = Task {
            repeatStarted = true
            await driver.sendInteractive(.fastForward, request: request)
            repeatFinished = true
        }
        await waitUntil { repeatStarted }
        LocalHTTP.complete("/keypress/Home", status: nil)
        await waitUntil { LocalHTTP.started == ["/keypress/Home", "/keypress/Back"] }
        #expect(driver.state == .failed("Couldn't reach the Roku."))
        LocalHTTP.complete("/keypress/Back")
        await waitUntil { repeatFinished || LocalHTTP.started.count > 2 }
        #expect(LocalHTTP.started == ["/keypress/Home", "/keypress/Back"])
        LocalHTTP.complete("/keypress/Fwd")
        await stale.value
        #expect(driver.state == .connected)

        let priorCount = LocalHTTP.started.count
        let fresh = Task { await driver.sendInteractive(.fastForward, request: request) }
        await waitUntil { LocalHTTP.started.count > priorCount }
        LocalHTTP.complete("/keypress/Fwd")
        await fresh.value
        #expect(LocalHTTP.started == ["/keypress/Home", "/keypress/Back", "/keypress/Fwd"])
    }

    @Test func rokuDropsReleasedJoystickInputWaitingBehindNormalCommands() async {
        let driver = await connectedRoku()
        driver.send(.up)
        await waitUntil { LocalHTTP.started.count == 1 }
        let request = RemoteInputRequest()
        let interactive = Task { await driver.sendInteractive(.right, request: request) }
        try? await Task.sleep(for: .milliseconds(20))
        request.cancel()
        LocalHTTP.complete("/keypress/Up")
        await interactive.value
        #expect(LocalHTTP.started == ["/keypress/Up"])
        #expect(driver.state == .connected)
    }

    @Test func rokuAllowsTheNextNormalCommandAfterDiscardingStaleInput() async {
        let driver = await connectedRoku()
        driver.send(.up)
        await waitUntil { LocalHTTP.started.count == 1 }
        let request = RemoteInputRequest()
        let interactive = Task { await driver.sendInteractive(.right, request: request) }
        try? await Task.sleep(for: .milliseconds(20))
        driver.send(.back)
        request.cancel()
        LocalHTTP.complete("/keypress/Up")
        await interactive.value
        await waitUntil { LocalHTTP.started.count == 2 }
        #expect(LocalHTTP.started == ["/keypress/Up", "/keypress/Back"])
        LocalHTTP.complete("/keypress/Back")
        await waitUntil { LocalHTTP.completions.isEmpty }
    }

    @Test func acceptedOKSurvivesLiftWhileStaleRokuMovementIsDiscarded() async {
        let driver = await connectedRoku()
        driver.send(.up)
        await waitUntil { LocalHTTP.started.count == 1 }
        let sender = JoystickSender(send: { key, request in
            await driver.sendInteractive(key, request: request)
        })
        sender.hold(.right)
        try? await Task.sleep(for: .milliseconds(20))
        sender.release()
        sender.press(.select)
        sender.release()
        LocalHTTP.complete("/keypress/Up")
        await waitUntil { LocalHTTP.started.count == 2 }
        #expect(LocalHTTP.started == ["/keypress/Up", "/keypress/Select"])
        LocalHTTP.complete("/keypress/Select")
        await waitUntil { LocalHTTP.completions.isEmpty }
        sender.stop()
    }

    @Test func rokuRetainsActiveOKWhenTheNextGestureBegins() async {
        let driver = await connectedRoku()
        driver.send(.up)
        await waitUntil { LocalHTTP.started.count == 1 }
        var accepted: RemoteInputRequest?
        let sender = JoystickSender(send: { key, request in
            if key == .select { accepted = request }
            await driver.sendInteractive(key, request: request)
        })
        sender.press(.select)
        sender.release()
        await waitUntil { accepted != nil }
        sender.hold(.right)
        #expect(accepted?.isCancelled == false)
        LocalHTTP.complete("/keypress/Up")
        await waitUntil { LocalHTTP.started.count == 2 }
        #expect(LocalHTTP.started == ["/keypress/Up", "/keypress/Select"])
        LocalHTTP.complete("/keypress/Select")
        await waitUntil { LocalHTTP.started.count == 3 }
        #expect(LocalHTTP.started == ["/keypress/Up", "/keypress/Select", "/keypress/Right"])
        sender.release()
        LocalHTTP.complete("/keypress/Right")
        await waitUntil { LocalHTTP.completions.isEmpty }
        sender.stop()
    }

    @Test func cancelledRokuResponseCannotRestoreDisconnectedState() async {
        let driver = await connectedRoku()
        let request = RemoteInputRequest()
        let interactive = Task { await driver.sendInteractive(.right, request: request) }
        await waitUntil { LocalHTTP.started.count == 1 }
        request.cancel()
        driver.disconnect()
        LocalHTTP.complete("/keypress/Right")
        await interactive.value
        #expect(driver.state == .idle)
    }

    private func connectLG() -> (LGDriver, LocalWebSocket, LocalWebSocket) {
        LocalWebSocket.instances = []
        let driver = LGDriver(device: TVDevice(name: "Test LG", brand: .lg, host: "192.0.2.20", token: "test"))
        driver.connect()
        let control = LocalWebSocket.instances.last!
        control.onText?("{\"type\":\"registered\",\"id\":\"register_0\",\"payload\":{}}")
        respondToPointerRequest(control)
        return (driver, control, LocalWebSocket.instances.last!)
    }

    private func respondToPointerRequest(_ control: LocalWebSocket) {
        let request = JSON.parse(control.sent.last!)!
        let id = request["id"] as! String
        control.onText?("{\"id\":\"\(id)\",\"payload\":{\"socketPath\":\"ws://192.0.2.20/pointer\"}}")
    }

    @Test func lgInteractiveDeleteUsesTheControlSocketAndHonorsCancellation() async {
        let (driver, control, pointer) = connectLG()
        defer { driver.disconnect() }
        let initialCount = control.sent.count
        let cancelled = RemoteInputRequest()
        cancelled.cancel()
        await driver.sendInteractive(.backspace, request: cancelled)
        #expect(control.sent.count == initialCount)

        await driver.sendInteractive(.backspace, request: RemoteInputRequest())
        #expect(control.sent.count == initialCount + 1)
        let message = control.sent.last.flatMap(JSON.parse)
        #expect(message?["uri"] as? String == "ssap://com.webos.service.ime/deleteCharacters")
        #expect((message?["payload"] as? [String: Int])?["count"] == 1)
        #expect(pointer.sent.isEmpty)
    }

    @Test func lgCursorUsesPointerPacketsRatherThanDirectionalKeys() async {
        let (driver, _, pointer) = connectLG()
        #expect(driver.supportsCursor)
        #expect(await driver.sendCursor(.move(dx: 12.5, dy: -3), request: RemoteInputRequest()))
        #expect(await driver.sendCursor(.scroll(dx: 0, dy: 1), request: RemoteInputRequest()))
        #expect(await driver.sendCursor(.click, request: RemoteInputRequest()))
        #expect(pointer.sent == ["type:move\ndx:12.500\ndy:-3.000\ndown:0\n\n",
                                 "type:scroll\ndx:0.000\ndy:1.000\n\n", "type:click\n\n"])
        driver.disconnect()
    }

    @Test func lgCursorRejectsOversizedWireMovesInsteadOfSendingThem() async {
        let (driver, _, pointer) = connectLG()
        #expect(!(await driver.sendCursor(.move(dx: 500, dy: 0), request: RemoteInputRequest())))
        #expect(pointer.sent.isEmpty)
        #expect(await driver.sendCursor(.move(dx: 96, dy: 0), request: RemoteInputRequest()))
        #expect(pointer.sent == ["type:move\ndx:96.000\ndy:0.000\ndown:0\n\n"])
        driver.disconnect()
    }

    @Test func lgScrollJitterNeverSendsZeroWheelPacketsOrEarnsFeedback() async {
        let (driver, _, pointer) = connectLG()
        var feedback: [RemoteInputRequest.Feedback] = []
        let sender = CursorSender(send: { command, request in
            let sent = await driver.sendCursor(command, request: request)
            if sent { feedback.append(request.feedback) }
            return sent
        })
        for rawDelta in [0.001, -0.001, 4.5, 4.5, 9.0] {
            guard case let .scroll(dx, dy)? = CursorMotion.scroll(dx: 0, dy: rawDelta, reversed: false) else {
                Issue.record("Expected nonzero raw scroll input"); continue
            }
            sender.scroll(dx: dx, dy: dy)
        }
        await waitUntil { sender.scrollActivity == 1 }
        try? await Task.sleep(for: .milliseconds(200))
        #expect(pointer.sent == ["type:scroll\ndx:0.000\ndy:-1.000\n\n"])
        #expect(feedback == [.firm])
        #expect(sender.scrollActivity == 1)
        sender.stop(); driver.disconnect()
    }

    @Test func lgCursorRejectsInvalidAndCancelledInput() async {
        let (driver, _, pointer) = connectLG()
        let cancelled = RemoteInputRequest()
        cancelled.cancel()
        #expect(!(await driver.sendCursor(.click, request: cancelled)))
        #expect(!(await driver.sendCursor(.move(dx: .nan, dy: 1), request: RemoteInputRequest())))
        #expect(!(await driver.sendCursor(.scroll(dx: 0, dy: .infinity), request: RemoteInputRequest())))
        #expect(pointer.sent.isEmpty)
        driver.disconnect()
    }

    @Test func lgCursorRecoveryDropsTheDragAndPreservesCredentials() async {
        let (driver, control, pointer) = connectLG()
        pointer.peerClosed()
        #expect(!(await driver.sendCursor(.move(dx: 50, dy: 0), request: RemoteInputRequest())))
        respondToPointerRequest(control)
        let replacement = LocalWebSocket.instances.last!
        #expect(replacement !== pointer)
        #expect(replacement.sent.isEmpty)
        #expect(driver.device.token == "test")
        #expect(await driver.sendCursor(.move(dx: 3, dy: 2), request: RemoteInputRequest()))
        #expect(replacement.sent == ["type:move\ndx:3.000\ndy:2.000\ndown:0\n\n"])
        driver.disconnect()
    }

    @Test func lgCursorRetriesAfterALostPointerReplyAndIgnoresTheLateReply() async {
        let (driver, control, pointer) = connectLG()
        pointer.peerClosed()
        #expect(!(await driver.sendCursor(.move(dx: 1, dy: 0), request: RemoteInputRequest())))
        let expiredID = JSON.parse(control.sent.last!)!["id"] as! String
        #expect(!(await driver.sendCursor(.click, request: RemoteInputRequest())))
        #expect(driver.state == .connected && driver.device.token == "test")
        #expect(!(await driver.sendCursor(.move(dx: 2, dy: 0), request: RemoteInputRequest())))
        let freshRequest = control.sent.last!
        #expect((JSON.parse(freshRequest)!["id"] as! String) != expiredID)
        let socketCount = LocalWebSocket.instances.count
        control.onText?("{\"id\":\"\(expiredID)\",\"payload\":{\"socketPath\":\"ws://192.0.2.20/stale\"}}")
        #expect(LocalWebSocket.instances.count == socketCount)
        respondToPointerRequest(control)
        let replacement = LocalWebSocket.instances.last!
        #expect(replacement.sent.isEmpty)
        #expect(await driver.sendCursor(.move(dx: 3, dy: 0), request: RemoteInputRequest()))
        #expect(replacement.sent == ["type:move\ndx:3.000\ndy:0.000\ndown:0\n\n"])
        driver.disconnect()
    }

    @Test func lgCursorReplacesAPointerWhoseHandshakeTimedOut() async {
        LocalWebSocket.delayedOpenPaths = ["/pointer"]
        defer { LocalWebSocket.delayedOpenPaths = [] }
        let (driver, control, expired) = connectLG()
        #expect(!(await driver.sendCursor(.click, request: RemoteInputRequest())))
        #expect(driver.state == .connected && driver.device.token == "test")
        LocalWebSocket.delayedOpenPaths = []
        #expect(!(await driver.sendCursor(.scroll(dx: 0, dy: 1), request: RemoteInputRequest())))
        respondToPointerRequest(control)
        let replacement = LocalWebSocket.instances.last!
        #expect(replacement !== expired && replacement.sent.isEmpty)
        expired.completeHandshake()
        expired.peerClosed()
        #expect(await driver.sendCursor(.click, request: RemoteInputRequest()))
        #expect(replacement.sent == ["type:click\n\n"])
        driver.disconnect()
    }

    @Test func freshMotionCanRetryAnExpiredAcquisitionWithoutAButtonPress() async {
        let (driver, control, pointer) = connectLG()
        pointer.peerClosed()
        #expect(!(await driver.sendCursor(.move(dx: 1, dy: 0), request: RemoteInputRequest())))
        let expiredRequest = control.sent.last!
        try? await Task.sleep(for: .milliseconds(4050))
        #expect(!(await driver.sendCursor(.move(dx: 2, dy: 0), request: RemoteInputRequest())))
        #expect(control.sent.last != expiredRequest)
        respondToPointerRequest(control)
        let replacement = LocalWebSocket.instances.last!
        #expect(replacement.sent.isEmpty)
        #expect(await driver.sendCursor(.move(dx: 3, dy: 0), request: RemoteInputRequest()))
        #expect(replacement.sent.count == 1)
        driver.disconnect()
    }

    @Test func lgCursorSendFailureDropsOnlyThePointerAndRecoversOnNewInput() async {
        let (driver, control, pointer) = connectLG()
        pointer.sendSucceeds = false
        #expect(!(await driver.sendCursor(.click, request: RemoteInputRequest())))
        #expect(driver.state == .connected)
        #expect(driver.device.token == "test")
        #expect(!(await driver.sendCursor(.move(dx: 50, dy: 0), request: RemoteInputRequest())))
        respondToPointerRequest(control)
        let replacement = LocalWebSocket.instances.last!
        #expect(replacement !== pointer)
        #expect(replacement.sent.isEmpty)
        #expect(await driver.sendCursor(.click, request: RemoteInputRequest()))
        #expect(replacement.sent == ["type:click\n\n"])
        driver.disconnect()
    }

    @Test func lgCursorDoesNotPairOrReconnectWhenDisconnected() async {
        LocalWebSocket.instances = []
        let driver = LGDriver(device: TVDevice(name: "Test LG", brand: .lg, host: "192.0.2.20", token: "test"))
        #expect(!(await driver.sendCursor(.click, request: RemoteInputRequest())))
        #expect(LocalWebSocket.instances.isEmpty)
    }

    @Test func lgCursorWaitingForHandshakeIsCancelledByAChangedSession() async {
        LocalWebSocket.delayedOpenPaths = ["/pointer"]
        defer { LocalWebSocket.delayedOpenPaths = [] }
        let (driver, _, pointer) = connectLG()
        let request = RemoteInputRequest()
        let click = Task { await driver.sendCursor(.click, request: request) }
        try? await Task.sleep(for: .milliseconds(30))
        request.cancel()
        driver.disconnect()
        pointer.completeHandshake()
        #expect(!(await click.value))
        #expect(pointer.sent.isEmpty)
    }

    @Test func deliberateCommandsReconnectAnIdleLGWithoutPairing() {
        for (key, name) in [(RemoteKey.up, "UP"), (.back, "BACK"), (.home, "HOME")] {
            let (driver, control, _) = connectLG()
            control.peerClosed()
            #expect(driver.state == .idle)
            let availability = RemoteInputAvailability(state: driver.state)
            #expect(availability.allowsCommands)
            #expect(!availability.allowsGestures)
            if availability.allowsCommands { driver.send(key) }
            let replacement = LocalWebSocket.instances.last!
            #expect(replacement !== control)
            #expect(driver.state == .connecting)
            let registration = replacement.sent.compactMap(JSON.parse).first!
            let payload = registration["payload"] as! [String: Any]
            #expect(payload["client-key"] as? String == "test")
            #expect(payload["forcePairing"] as? Bool == false)
            replacement.onText?("{\"type\":\"registered\",\"id\":\"register_0\",\"payload\":{}}")
            respondToPointerRequest(replacement)
            #expect(driver.state == .connected)
            #expect(LocalWebSocket.instances.last!.sent == ["type:button\nname:\(name)\n\n"])
            driver.disconnect()
        }
    }

    @Test func lgRecoversInputSocketWithoutReplayingTheTriggeringKey() async {
        let (driver, control, pointer) = connectLG()
        await driver.sendInteractive(.right, request: RemoteInputRequest())
        #expect(pointer.sent == ["type:button\nname:RIGHT\n\n"])
        pointer.peerClosed()
        let before = control.sent.count
        let left = Task { await driver.sendInteractive(.left, request: RemoteInputRequest()) }
        await waitUntil { control.sent.count == before + 1 }
        #expect(driver.state == .connected)
        var upEntered = false
        let up = Task { upEntered = true; await driver.sendInteractive(.up, request: RemoteInputRequest()) }
        await waitUntil { upEntered }
        #expect(control.sent.count == before + 1) // One recovery request in flight.
        respondToPointerRequest(control)
        await left.value
        await up.value
        let replacement = LocalWebSocket.instances.last!
        #expect(replacement !== pointer)
        #expect(replacement.sent.isEmpty)
        await driver.sendInteractive(.select, request: RemoteInputRequest())
        #expect(replacement.sent == ["type:button\nname:ENTER\n\n"])
    }

    @Test func lgRetainsOneShotUntilPointerCreation() async {
        LocalWebSocket.instances = []
        let driver = LGDriver(device: TVDevice(name: "Test LG", brand: .lg, host: "192.0.2.20", token: "test"))
        driver.connect()
        let control = LocalWebSocket.instances.last!
        control.onText?("{\"type\":\"registered\",\"id\":\"register_0\",\"payload\":{}}")
        var entered = false
        let operation = Task { entered = true; await driver.sendInteractive(.select, request: RemoteInputRequest()) }
        await waitUntil { entered }
        respondToPointerRequest(control)
        let pointer = LocalWebSocket.instances.last!
        await operation.value
        #expect(pointer.sent == ["type:button\nname:ENTER\n\n"])
        driver.disconnect()
    }

    @Test func lgRetainsEachOneShotUntilPointerHandshake() async {
        LocalWebSocket.delayedOpenPaths = ["/pointer"]
        defer { LocalWebSocket.delayedOpenPaths = [] }
        for (key, name) in [(RemoteKey.select, "ENTER"), (.back, "BACK"), (.home, "HOME")] {
            let (driver, _, pointer) = connectLG()
            #expect(!pointer.isReady)
            var entered = false
            let operation = Task { entered = true; await driver.sendInteractive(key, request: RemoteInputRequest()) }
            await waitUntil { entered }
            #expect(pointer.sent.isEmpty)
            pointer.completeHandshake()
            await operation.value
            #expect(pointer.sent == ["type:button\nname:\(name)\n\n"])
            driver.disconnect()
        }
    }

    @Test func lgSelectRecoversWhenThePointerItWasWaitingForCloses() async {
        LocalWebSocket.instances = []
        LocalWebSocket.delayedOpenPaths = ["/pointer"]
        let driver = LGDriver(device: TVDevice(name: "Test LG", brand: .lg, host: "192.0.2.20", token: "test"))
        defer {
            driver.disconnect()
            LocalWebSocket.delayedOpenPaths = []
        }
        driver.connect()
        let control = LocalWebSocket.instances.last!
        control.onText?("{\"type\":\"registered\",\"id\":\"register_0\",\"payload\":{}}")
        #expect(driver.state == .connected)
        let originalRequestCount = control.sent.count

        var waitingForPointer = false
        let select = Task {
            waitingForPointer = true
            await driver.sendInteractive(.select, request: RemoteInputRequest())
        }
        defer { select.cancel() }
        await waitUntil { waitingForPointer }
        #expect(control.sent.count == originalRequestCount)
        respondToPointerRequest(control)
        let firstPointer = LocalWebSocket.instances.last!
        #expect(!firstPointer.isReady)
        firstPointer.peerClosed()

        await waitUntil { control.sent.count > originalRequestCount }
        let requestedReplacement = control.sent.count == originalRequestCount + 1
        #expect(requestedReplacement)
        guard requestedReplacement else { return }
        respondToPointerRequest(control)
        let replacement = LocalWebSocket.instances.last!
        #expect(replacement !== firstPointer)
        replacement.completeHandshake()
        await select.value

        #expect(firstPointer.sent.isEmpty)
        #expect(replacement.sent == ["type:button\nname:ENTER\n\n"])
        #expect(driver.state == .connected)
        #expect(control.isReady)
        driver.sendText("A")
        #expect(control.sent.last.flatMap(JSON.parse)?["uri"] as? String == "ssap://com.webos.service.ime/insertText")
    }

    @Test func lgSelectCanReplaceAnAlreadyExpiredPointerRequest() async throws {
        LocalWebSocket.instances = []
        let driver = LGDriver(device: TVDevice(name: "Test LG", brand: .lg, host: "192.0.2.20", token: "test"))
        defer { driver.disconnect() }
        driver.connect()
        let control = LocalWebSocket.instances.last!
        control.onText?("{\"type\":\"registered\",\"id\":\"register_0\",\"payload\":{}}")
        let originalRequestCount = control.sent.count
        try await Task.sleep(for: .milliseconds(4050))

        let select = Task { await driver.sendInteractive(.select, request: RemoteInputRequest()) }
        defer { select.cancel() }
        await waitUntil { control.sent.count == originalRequestCount + 1 }
        guard control.sent.count == originalRequestCount + 1 else { return }
        respondToPointerRequest(control)
        await select.value

        let pointer = LocalWebSocket.instances.last!
        #expect(pointer.sent == ["type:button\nname:ENTER\n\n"])
        #expect(driver.state == .connected)
    }

    @Test func lgBoundsRecoveryRequestsWhenPointerServiceDeclines() async {
        for key in [RemoteKey.home, .right] {
            LocalWebSocket.instances = []
            let driver = LGDriver(device: TVDevice(name: "Test LG", brand: .lg, host: "192.0.2.20", token: "test"))
            driver.connect()
            let control = LocalWebSocket.instances.last!
            control.onText?("{\"type\":\"registered\",\"id\":\"register_0\",\"payload\":{}}")
            let first = JSON.parse(control.sent.last!)!["id"] as! String
            control.onText?("{\"id\":\"\(first)\",\"payload\":{}}")
            let before = control.sent.count
            let request = RemoteInputRequest()
            var entered = false
            let operation = Task { entered = true; await driver.sendInteractive(key, request: request) }
            await waitUntil { entered && control.sent.count > before }
            var replied = Set<String>()
            let deadline = ContinuousClock.now + .milliseconds(160)
            while ContinuousClock.now < deadline {
                for text in control.sent.dropFirst(before) {
                    if let id = JSON.parse(text)?["id"] as? String, replied.insert(id).inserted {
                        control.onText?("{\"id\":\"\(id)\",\"payload\":{}}")
                    }
                }
                try? await Task.sleep(for: .milliseconds(5))
            }
            request.cancel()
            await operation.value
            #expect(control.sent.count == before + 1)
            #expect(driver.state == .connected) // Cancellation is quiet, not a timeout.
            driver.disconnect()
        }
    }

    @Test func lgMakesPointerTimeoutUnavailableAndPreservesCredentials() async {
        LocalWebSocket.delayedOpenPaths = ["/pointer"]
        defer { LocalWebSocket.delayedOpenPaths = [] }
        let (driver, control, pointer) = connectLG()
        await driver.sendInteractive(.home, request: RemoteInputRequest())
        #expect(driver.state == .idle) // No failed-address rediscovery for a pointer error.
        #expect(driver.device.token == "test")
        #expect(!control.isReady)
        #expect(!pointer.isReady)
        #expect(pointer.sent.isEmpty)
    }

    @Test func lgMissingPointerCreationTimesOutForDirection() async {
        LocalWebSocket.instances = []
        let driver = LGDriver(device: TVDevice(name: "Test LG", brand: .lg, host: "192.0.2.20", token: "test"))
        driver.connect()
        let control = LocalWebSocket.instances.last!
        control.onText?("{\"type\":\"registered\",\"id\":\"register_0\",\"payload\":{}}")
        let before = control.sent.count
        // No pointer descriptor arrives; direction-only input must still hit the bound.
        await driver.sendInteractive(.right, request: RemoteInputRequest())
        #expect(driver.state == .idle)
        #expect(driver.device.token == "test")
        #expect(!control.isReady)
        #expect(control.sent.count == before) // No duplicate acquisition requests.
        #expect(LocalWebSocket.instances.count == 1)
    }

    @Test(arguments: [RemoteKey.volumeUp, .right])
    func lgButtonRepeatTimeoutPreservesPrimaryControl(_ key: RemoteKey) async {
        LocalWebSocket.delayedOpenPaths = ["/pointer"]
        defer { LocalWebSocket.delayedOpenPaths = [] }
        let (driver, control, pointer) = connectLG()
        defer { driver.disconnect() }

        await driver.sendInteractive(key, request: RemoteInputRequest(isRepeat: true, requiresCurrentConnection: true))
        #expect(driver.state == .connected)
        #expect(control.isReady)
        #expect(pointer.sent.isEmpty)

        driver.sendText("A")
        let message = control.sent.last.flatMap(JSON.parse)
        #expect(message?["uri"] as? String == "ssap://com.webos.service.ime/insertText")
    }

    @Test func lgMissingPointerCancellationStaysQuietAndDoesNotReplayDirection() async {
        LocalWebSocket.instances = []
        let driver = LGDriver(device: TVDevice(name: "Test LG", brand: .lg, host: "192.0.2.20", token: "test"))
        driver.connect()
        let control = LocalWebSocket.instances.last!
        control.onText?("{\"type\":\"registered\",\"id\":\"register_0\",\"payload\":{}}")
        let before = control.sent.count
        let request = RemoteInputRequest()
        var entered = false
        let operation = Task { entered = true; await driver.sendInteractive(.right, request: request) }
        await waitUntil { entered }
        request.cancel() // Lift before the pointer descriptor or readiness deadline.
        await operation.value
        #expect(driver.state == .connected)
        #expect(driver.device.token == "test")
        #expect(control.sent.count == before)
        respondToPointerRequest(control)
        let pointer = LocalWebSocket.instances.last!
        #expect(pointer.sent.isEmpty)
        await driver.sendInteractive(.up, request: RemoteInputRequest())
        #expect(pointer.sent == ["type:button\nname:UP\n\n"])
        driver.disconnect()
    }

    @Test func lgDiscardsCancelledInputDuringHandshake() async {
        LocalWebSocket.delayedOpenPaths = ["/pointer"]
        defer { LocalWebSocket.delayedOpenPaths = [] }
        for key in [RemoteKey.select, .right] {
            let (driver, _, pointer) = connectLG()
            let request = RemoteInputRequest()
            var entered = false
            let operation = Task { entered = true; await driver.sendInteractive(key, request: request) }
            await waitUntil { entered }
            request.cancel() // Lifecycle stop for OK, ordinary lift for movement.
            pointer.completeHandshake()
            await operation.value
            #expect(pointer.sent.isEmpty)
            #expect(driver.state == .connected)
            driver.disconnect()
        }
    }

    @Test func lgDoesNotCarryOneShotIntoANewPrimarySession() async {
        LocalWebSocket.delayedOpenPaths = ["/pointer"]
        defer { LocalWebSocket.delayedOpenPaths = [] }
        let (driver, _, oldPointer) = connectLG()
        var entered = false
        let operation = Task { entered = true; await driver.sendInteractive(.home, request: RemoteInputRequest()) }
        await waitUntil { entered }
        driver.disconnect()
        driver.connect()
        let replacementControl = LocalWebSocket.instances.last!
        replacementControl.onText?("{\"type\":\"registered\",\"id\":\"register_0\",\"payload\":{}}")
        respondToPointerRequest(replacementControl)
        let replacementPointer = LocalWebSocket.instances.last!
        replacementPointer.completeHandshake()
        await operation.value
        #expect(oldPointer.sent.isEmpty)
        #expect(replacementPointer.sent.isEmpty)
        #expect(driver.state == .connected)
        driver.disconnect()
    }

    @Test func lgDoesNotRecoverOrSendCancelledInput() async {
        let (driver, control, pointer) = connectLG()
        pointer.peerClosed()
        let request = RemoteInputRequest()
        request.cancel()
        let before = control.sent.count
        await driver.sendInteractive(.back, request: request)
        #expect(control.sent.count == before)
        #expect(LocalWebSocket.instances.count == 2)
    }

    @Test func lgDoesNotPairOrReconnectFromDisconnectedInteractiveInput() async {
        let (driver, control, _) = connectLG()
        driver.disconnect()
        let before = control.sent.count
        await driver.sendInteractive(.home, request: RemoteInputRequest())
        #expect(control.sent.count == before)
        #expect(driver.state == .idle)
    }
}
