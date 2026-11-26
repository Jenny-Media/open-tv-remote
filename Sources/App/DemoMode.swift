#if DEBUG
import Foundation

/// Debug-only fake TV for App Store screenshots and UI work without touching a real TV.
/// Launch with `-demo` (optionally `-padMode keyboard|keypad`, `-demoSheet apps|devices|keyboard|settings`).
/// Simulator-only `-demoLiveActivity YES` opts in to the system Live Activity with the fake TV.
@MainActor
final class DemoDriver: TVDriver {
    let device: TVDevice
    weak var delegate: TVDriverDelegate?
    private(set) var state: ConnectionState {
        didSet { delegate?.driver(self, didChangeState: state) }
    }

    init(device: TVDevice) {
        self.device = device
        state = device.hasCredentials ? .connected : .unpaired
    }

    func connect() {
        state = device.hasCredentials ? .connected : .unpaired
    }

    func pair() { state = .pairing(.enterCode(length: 6, error: nil)) }
    func submitPairingCode(_ code: String) {
        guard case .pairing(.enterCode) = state else { return }
        state = .pairing(.enterCode(length: 6, error: "Incorrect pairing code."))
    }
    func disconnect() {}
    func supports(_ key: RemoteKey) -> Bool { true }
    func send(_ key: RemoteKey) {}
    func sendInteractive(_ key: RemoteKey, request: RemoteInputRequest) async {
        let delay = UserDefaults.standard.integer(forKey: "demoInteractiveDelayMS")
        if delay > 0 { try? await Task.sleep(for: .milliseconds(delay)) }
    }
    func sendText(_ text: String) {}
    func launch(_ app: TVApp) {}
    func installedApps() async -> [TVApp]? { DemoMode.artworkApps }
}

enum DemoMode {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    static var devices: [TVDevice] {
        [
            TVDevice(name: "Living Room TV", brand: .androidTV, host: "192.168.1.20",
                     isPaired: !UserDefaults.standard.bool(forKey: "demoUnpaired")),
            TVDevice(name: "Bedroom Roku", brand: .roku, host: "192.168.1.31"),
        ]
    }

    static var sheet: String? { UserDefaults.standard.string(forKey: "demoSheet") }
    static var foregroundAppName: String? { UserDefaults.standard.string(forKey: "demoForegroundApp") }
    static var keyboardTestWidth: CGFloat? {
        let width = UserDefaults.standard.double(forKey: "demoKeyboardWidth")
        return isEnabled && width > 0 ? CGFloat(width) : nil
    }

    static var artworkApps: [TVApp]? {
        guard let value = UserDefaults.standard.string(forKey: "demoAppArtworkURL"),
              let iconURL = URL(string: value), iconURL.scheme == "data" else { return nil }
        return (1...6).map { index in
            TVApp(name: "Artwork \(index)", launchID: "artwork-\(index)", iconURL: iconURL)
        }
    }
}
#endif
