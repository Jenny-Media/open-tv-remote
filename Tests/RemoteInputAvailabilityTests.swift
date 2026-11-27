import Testing
@testable import JoystickCore

@Suite("Explicit pairing feedback")
struct PairingFeedbackTests {
    @Test func rejectionsCanBeRetriedAndSuccessIsOneShot() {
        var feedback = PairingFeedback()
        #expect(feedback.receive(.connected) == nil)
        feedback.start()
        #expect(feedback.receive(.idle) == nil)
        #expect(feedback.receive(.connecting) == nil)
        #expect(feedback.receive(.pairing(.enterCode(length: 6, error: nil))) == nil)
        let wrongCode = ConnectionState.pairing(.enterCode(length: 6, error: "Wrong code"))
        #expect(feedback.receive(wrongCode) == .error)
        #expect(feedback.receive(wrongCode) == .error)
        #expect(feedback.receive(.pairing(.verifying)) == nil)
        #expect(feedback.receive(.connected) == .success)
        #expect(feedback.receive(.connected) == nil)
    }

    @Test func cancellingOrFailingDoesNotPulseOnReconnect() {
        var feedback = PairingFeedback()
        feedback.start()
        feedback.cancel()
        #expect(feedback.receive(.failed("Cancelled")) == nil)
        #expect(feedback.receive(.connected) == nil)
        feedback.start()
        #expect(feedback.receive(.failed("Denied")) == .error)
        #expect(feedback.receive(.failed("Denied")) == nil)
        #expect(feedback.receive(.connected) == nil)
    }

    @Test func returningToUnpairedEndsAnExplicitAttempt() {
        var feedback = PairingFeedback()
        #expect(feedback.receive(.unpaired) == nil)
        feedback.start()
        #expect(feedback.receive(.pairing(.verifying)) == nil)
        #expect(feedback.receive(.connecting) == nil)
        #expect(feedback.receive(.unpaired) == .error)
        #expect(feedback.receive(.unpaired) == nil)
        #expect(feedback.receive(.connected) == nil)
    }
}

@Suite("Remote input availability")
struct RemoteInputAvailabilityTests {
    private let states: [ConnectionState] = [
        .idle, .connecting, .unpaired, .pairing(.acceptOnTV), .connected, .failed("offline")
    ]

    @Test func deliberateCommandsCanReachDriverRecovery() {
        for state in states {
            #expect(RemoteInputAvailability(state: state).allowsCommands)
        }
    }

    @Test func gesturesRequireAnEstablishedConnection() {
        for state in states {
            #expect(RemoteInputAvailability(state: state).allowsGestures == (state == .connected))
        }
    }

    @Test func everySheetAndCombinationBlocksBothInputPaths() {
        for state in states {
            for mask in 1...15 {
                let availability = RemoteInputAvailability(state: state,
                    showingDevices: mask & 1 != 0, showingKeyboard: mask & 2 != 0,
                    showingApps: mask & 4 != 0, showingSettings: mask & 8 != 0)
                #expect(!availability.allowsCommands)
                #expect(!availability.allowsGestures)
            }
        }
    }
}
