import SwiftUI
#if os(iOS)
import UIKit
#endif

enum Theme {
    static let background = Color(red: 0.035, green: 0.037, blue: 0.045)
    static let keyTop = Color(white: 0.155)
    static let keyBottom = Color(white: 0.105)
    static let well = Color(white: 0.07)
    static let accent = Color(red: 0.36, green: 0.89, blue: 0.65)
    static let power = Color(red: 1.0, green: 0.36, blue: 0.33)
    static let label = Color(white: 0.92)
    static let secondary = Color(white: 0.55)
    static let corner: CGFloat = 18
}

enum Haptics {
    static let preferenceKey = "haptics.enabled"

    #if os(iOS)
    private static var canPlay: Bool {
        UIApplication.shared.applicationState == .active &&
            (UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true)
    }

    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let firm = UIImpactFeedbackGenerator(style: .medium)
    private static let repeatPulse = UIImpactFeedbackGenerator(style: .light)
    private static let cursorPulse = UIImpactFeedbackGenerator(style: .light)
    private static let selectionFeedback = UISelectionFeedbackGenerator()
    private static let notificationFeedback = UINotificationFeedbackGenerator()
    #endif

    static func tap() {
        #if os(iOS)
        guard canPlay else { return }
        light.impactOccurred()
        #endif
    }

    static func tick() {
        #if os(iOS)
        guard canPlay else { return }
        rigid.impactOccurred(intensity: 0.6)
        #endif
    }

    static func joystickStart() {
        #if os(iOS)
        guard canPlay else { return }
        firm.impactOccurred(intensity: 0.8)
        repeatPulse.prepare()
        #endif
    }

    static func cursorStart() {
        #if os(iOS)
        guard canPlay else { return }
        firm.impactOccurred(intensity: 0.8)
        cursorPulse.prepare()
        #endif
    }

    static func cursorTick() {
        #if os(iOS)
        guard canPlay else { return }
        cursorPulse.impactOccurred()
        cursorPulse.prepare()
        #endif
    }

    static func repeatTick() {
        #if os(iOS)
        guard canPlay else { return }
        repeatPulse.impactOccurred()
        repeatPulse.prepare()
        #endif
    }

    static func selection() {
        #if os(iOS)
        guard canPlay else { return }
        selectionFeedback.selectionChanged()
        #endif
    }

    static func outcome(_ outcome: InteractionOutcome) {
        #if os(iOS)
        guard canPlay else { return }
        notificationFeedback.notificationOccurred(outcome == .success ? .success : .error)
        #endif
    }
}

/// The raised, slightly glossy surface every remote key sits on.
struct KeySurface<S: InsettableShape>: View {
    let shape: S
    var pressed = false
    var tint: Color? = nil

    var body: some View {
        shape
            .fill(LinearGradient(colors: pressed ? [Theme.keyBottom, Theme.keyBottom] : [Theme.keyTop, Theme.keyBottom],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                if let tint, pressed { shape.fill(tint.opacity(0.22)) }
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(pressed ? 0.05 : 0.11), .white.opacity(0.02)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .shadow(color: .black.opacity(pressed ? 0.2 : 0.55), radius: pressed ? 2 : 7, y: pressed ? 1 : 4)
    }
}

/// A remote button: fires on touch-down (like a physical remote) and can auto-repeat while held.
struct KeyCap<Label: View, S: InsettableShape>: View {
    var shape: S
    var repeats = false
    var tint: Color? = Theme.accent
    var enabled = true
    var accessibilityLabel: String
    /// If set, a short tap fires `action` on release and holding fires this instead.
    var holdAction: (() -> Void)? = nil
    var holdName = "Hold"
    var repeatAction: ((RemoteInputRequest) async -> Void)? = nil
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    private enum DragPress { case idle, inside, exited }

    /// GestureState resets even when the system cancels a touch without calling onEnded.
    @GestureState private var dragPress = DragPress.idle
    @State private var hitSize = CGSize.zero
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.remoteRepeatIsCurrent) private var remoteRepeatIsCurrent
    @State private var repeatTask: Task<Void, Never>?
    @State private var repeatRequest: RemoteInputRequest?
    @State private var held = false
    #if os(iOS)
    @State private var holdHighlighted = false
    #endif

    var body: some View {
        interaction
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { fire() }
            .accessibilityActions {
                if let holdAction { Button(holdName) { fireHold(holdAction) } }
            }
            .disabled(!enabled)
            .onChange(of: enabled) { _, enabled in if !enabled { stopRepeating() } }
    }

    @ViewBuilder private var interaction: some View {
        #if os(iOS)
        if let holdAction {
            face(pressed: holdHighlighted)
                .overlay {
                    HoldKeyCapTarget(tap: { fire() }, hold: { fireHold(holdAction) },
                                     highlight: { holdHighlighted = $0 })
                    .accessibilityHidden(true)
                }
        } else {
            dragInteraction
        }
        #else
        dragInteraction
        #endif
    }

    private var dragInteraction: some View {
        face(pressed: dragPress == .inside)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { hitSize = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($dragPress) { value, state, _ in
                        guard state != .exited else { return }
                        let bounds = CGRect(origin: .zero, size: hitSize)
                        if repeatAction != nil, !shape.path(in: bounds).contains(value.location) {
                            state = .exited
                        } else {
                            state = .inside
                        }
                    }
                    // A cancelled drag never turns into a tap.
                    .onEnded { _ in
                        if holdAction != nil && !held { fire() }
                    }
            )
            .onChange(of: dragPress == .inside) { _, isPressed in
                stopRepeating()
                guard isPressed, enabled, isEnabled else { return }
                if let holdAction {
                    held = false
                    repeatTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(700))
                        guard !Task.isCancelled else { return }
                        held = true
                        fireHold(holdAction)
                    }
                    return
                }
                fire()
                if repeats { startRepeating() }
            }
            .onChange(of: scenePhase) { _, phase in
                if repeatAction != nil && phase != .active { stopRepeating() }
            }
            .onChange(of: isEnabled) { _, enabled in
                if repeatAction != nil && !enabled { stopRepeating() }
            }
            .onDisappear { stopRepeating() }
    }

    private func face(pressed: Bool) -> some View {
        label()
            .foregroundStyle(enabled ? Theme.label : Theme.secondary.opacity(0.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KeySurface(shape: shape, pressed: pressed, tint: tint))
            .contentShape(shape)
            .scaleEffect(pressed ? 0.955 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.65), value: pressed)
    }

    private func fire(playsFeedback: Bool = true) {
        guard enabled, isEnabled else { return }
        if playsFeedback { Haptics.tap() }
        action()
    }

    private func fireHold(_ holdAction: () -> Void) {
        guard enabled, isEnabled else { return }
        Haptics.tick()
        holdAction()
    }

    private func startRepeating() {
        let isCurrent = remoteRepeatIsCurrent
        let deadline = ContinuousClock.now + .seconds(8)
        let request = repeatAction.map { _ in
            RemoteInputRequest(isRepeat: true, feedback: .soft, requiresCurrentConnection: true,
                               deadline: deadline, isCurrent: isCurrent)
        }
        var feedback = RepeatFeedbackCadence()
        request?.onDispatch = {
            if feedback.consume(at: .now) { Haptics.repeatTick() }
        }
        repeatRequest = request
        repeatTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            // Belt and braces: never auto-repeat for more than ~8 seconds.
            for _ in 0..<70 {
                guard !Task.isCancelled, request?.canDispatch != false,
                      ContinuousClock.now < deadline else { return }
                if let repeatAction, let request {
                    await repeatAction(request)
                } else {
                    fire(playsFeedback: false)
                }
                try? await Task.sleep(for: .milliseconds(110))
            }
        }
    }

    private func stopRepeating() {
        if let repeatRequest {
            // Let an already-dispatched command finish so its response and place in the queue survive lift.
            repeatRequest.cancel()
        } else {
            repeatTask?.cancel()
        }
        repeatRequest = nil
        repeatTask = nil
    }
}

#if os(iOS)
private struct HoldKeyCapTarget: UIViewRepresentable {
    let tap: () -> Void
    let hold: () -> Void
    let highlight: (Bool) -> Void

    func makeUIView(context: Context) -> PressButton {
        PressButton()
    }

    func updateUIView(_ button: PressButton, context: Context) {
        button.tap = tap
        button.hold = hold
        button.highlight = highlight
    }

    final class PressButton: UIButton {
        private static let holdDuration: TimeInterval = 0.7
        private static let movementLimit: CGFloat = 10

        var tap: (() -> Void)?
        var hold: (() -> Void)?
        var highlight: ((Bool) -> Void)?
        private var tapStart: (location: CGPoint, timestamp: TimeInterval)?

        override var isHighlighted: Bool {
            didSet { if oldValue != isHighlighted { highlight?(isHighlighted) } }
        }

        init() {
            super.init(frame: .zero)
            isAccessibilityElement = false
            let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
            recognizer.minimumPressDuration = Self.holdDuration
            recognizer.allowableMovement = Self.movementLimit
            // Recognition cancels the button touch, so release never also sends Power.
            recognizer.cancelsTouchesInView = true
            addGestureRecognizer(recognizer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

        override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            tapStart = (touch.location(in: self), touch.timestamp)
            return super.beginTracking(touch, with: event)
        }

        override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            // Once movement cancels a tap, returning to the button doesn't restore it.
            if !isValidTap(touch) { tapStart = nil }
            return super.continueTracking(touch, with: event)
        }

        override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
            let shouldTap = touch.map(isValidTap) ?? false
            tapStart = nil
            super.endTracking(touch, with: event)
            if shouldTap { tap?() }
        }

        override func cancelTracking(with event: UIEvent?) {
            tapStart = nil
            super.cancelTracking(with: event)
        }

        private func isValidTap(_ touch: UITouch) -> Bool {
            guard let tapStart, touch.timestamp - tapStart.timestamp < Self.holdDuration else { return false }
            let location = touch.location(in: self)
            return bounds.contains(location) &&
                hypot(location.x - tapStart.location.x, location.y - tapStart.location.y) <= Self.movementLimit
        }

        @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
            if recognizer.state == .began, bounds.contains(recognizer.location(in: self)) {
                hold?()
            }
        }
    }
}
#endif

extension KeyCap where S == RoundedRectangle {
    init(repeats: Bool = false, tint: Color? = Theme.accent, enabled: Bool = true, accessibilityLabel: String,
         repeatAction: ((RemoteInputRequest) async -> Void)? = nil,
         action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.init(shape: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous), repeats: repeats, tint: tint,
                  enabled: enabled, accessibilityLabel: accessibilityLabel, repeatAction: repeatAction,
                  action: action, label: label)
    }
}

/// Convenience: a key bound straight to a RemoteKey.
struct RemoteKeyButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.cancellableRemoteRepeats) private var cancellableRepeats
    let key: RemoteKey
    let symbol: String
    var repeats = false

    var body: some View {
        KeyCap(repeats: repeats, enabled: model.supports(key), accessibilityLabel: key.accessibilityName,
               repeatAction: model.repeatAction(for: key, enabled: repeats && cancellableRepeats)) {
            model.press(key)
        } label: {
            Image(systemName: symbol).font(.system(size: 19, weight: .semibold))
        }
    }
}

private struct CancellableRemoteRepeatsKey: EnvironmentKey {
    static let defaultValue = false
}

private struct RemoteRepeatIsCurrentKey: EnvironmentKey {
    static let defaultValue: () -> Bool = { true }
}

extension EnvironmentValues {
    var cancellableRemoteRepeats: Bool {
        get { self[CancellableRemoteRepeatsKey.self] }
        set { self[CancellableRemoteRepeatsKey.self] = newValue }
    }

    var remoteRepeatIsCurrent: () -> Bool {
        get { self[RemoteRepeatIsCurrentKey.self] }
        set { self[RemoteRepeatIsCurrentKey.self] = newValue }
    }
}

extension AppModel {
    func repeatAction(for key: RemoteKey, enabled: Bool) -> ((RemoteInputRequest) async -> Void)? {
        guard enabled else { return nil }
        let deviceID = currentID
        return { request in
            guard request.canDispatch, self.currentID == deviceID, self.remoteCommandsAvailable,
                  !self.isConnectionPaused, self.supports(key) else {
                request.cancel()
                return
            }
            guard self.remoteInputAvailable else { return }
            await self.pressInteractively(key, request: request)
        }
    }
}
