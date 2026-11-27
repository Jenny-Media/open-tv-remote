// Host-only substitutes for the networking types. These never open sockets.
import Foundation

@MainActor
final class LocalWebSocket {
    static var instances: [LocalWebSocket] = []
    static var delayedOpenPaths: Set<String> = []
    let url: URL
    var onOpen: (() -> Void)?
    var onText: ((String) -> Void)?
    var onClose: ((Error?) -> Void)?
    private(set) var isReady = false
    var sendSucceeds = true
    private(set) var sent: [String] = []

    init(url: URL) { self.url = url; Self.instances.append(self) }
    func start() {
        if !Self.delayedOpenPaths.contains(url.path) { completeHandshake() }
    }
    func completeHandshake() { isReady = true; onOpen?() }
    func send(_ text: String) { sent.append(text) }
    func send(json: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: json)
        send(String(decoding: data, as: UTF8.self))
    }
    func sendAndWait(_ text: String, beginDispatch: () -> Bool = { true }) async {
        if isReady, !Task.isCancelled, beginDispatch() { sent.append(text) }
    }
    func sendAndWait(json: [String: Any], beginDispatch: () -> Bool) async {
        let data = try! JSONSerialization.data(withJSONObject: json)
        await sendAndWait(String(decoding: data, as: UTF8.self), beginDispatch: beginDispatch)
    }
    func sendReportingResult(_ text: String) async -> Bool {
        guard isReady, sendSucceeds else { return false }
        sent.append(text)
        return true
    }
    func close() { isReady = false; onClose = nil }
    func peerClosed() { isReady = false; onClose?(nil) }
}

@MainActor
enum LocalHTTP {
    static var started: [String] = []
    static var completions: [String: CheckedContinuation<Int?, Never>] = [:]
    static var deviceInfo = Data("<device-info/>".utf8)
    static var delaysDeviceInfo = false
    private(set) static var deviceInfoReads = 0
    private(set) static var deviceInfoRequest: CheckedContinuation<Data?, Never>?

    static func get(_ url: URL, timeout: TimeInterval = 3) async -> Data? {
        if url.path == "/query/device-info" {
            deviceInfoReads += 1
            if delaysDeviceInfo {
                return await withCheckedContinuation { deviceInfoRequest = $0 }
            }
        }
        return deviceInfo
    }
    static func post(_ url: URL, body: Data? = nil, timeout: TimeInterval = 3) async -> Int? {
        started.append(url.path)
        return await withCheckedContinuation { completions[url.path] = $0 }
    }
    static func complete(_ path: String, status: Int? = 200) {
        completions.removeValue(forKey: path)?.resume(returning: status)
    }
    static func completeDeviceInfo(success: Bool = true) {
        deviceInfoRequest?.resume(returning: success ? deviceInfo : nil)
        deviceInfoRequest = nil
    }
    static func reset() {
        for completion in completions.values { completion.resume(returning: nil) }
        completions = [:]
        started = []
        deviceInfoRequest?.resume(returning: nil)
        deviceInfoRequest = nil
        delaysDeviceInfo = false
        deviceInfoReads = 0
        deviceInfo = Data("<device-info/>".utf8)
    }
}

enum XMLText {
    static func first(_ tag: String, in data: Data) -> String? {
        try? XMLDocument(data: data).rootElement()?.elements(forName: tag).first?.stringValue
    }
}

enum JSON {
    static func parse(_ text: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }
}
