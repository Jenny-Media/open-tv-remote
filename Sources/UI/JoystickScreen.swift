import SwiftUI

struct JoystickScreen: View {
    @Environment(AppModel.self) private var model

    var compactHeight = false
    var navigationAlignment: Alignment?
    var swapSides: (() -> Void)?
    var pageIsActive: () -> Bool = { true }

    var body: some View {
        JoystickControls(tvName: model.current?.name ?? "No TV selected", enabled: model.remoteInputAvailable && pageIsActive(),
                         sessionID: model.currentID, inputLog: inputLog, compactHeight: compactHeight,
                         navigationAlignment: navigationAlignment, swapSides: swapSides,
                         mode: Binding(get: { model.remoteControlMode }, set: model.selectRemoteMode),
                         modes: model.availableRemoteModes) { key, request in
            guard model.remoteInputAvailable, pageIsActive(), model.remoteControlMode == .eyesFree,
                  !request.isCancelled else { return }
            switch request.feedback {
            case .firm:
                switch key {
                case .up, .down, .left, .right: Haptics.joystickStart()
                case .select: Haptics.tick()
                default: Haptics.tap()
                }
            case .soft:
                let recordDispatch = request.onDispatch
                request.onDispatch = {
                    recordDispatch?()
                    Haptics.repeatTick()
                }
            case .none: break
            }
            await model.pressInteractively(key, request: request)
        }
    }

    private var inputLog: String? {
        #if DEBUG
        if DemoMode.isEnabled && UserDefaults.standard.bool(forKey: "demoInputLog") {
            return "\(model.demoInputCount):\(model.demoLastInput)"
        }
        #endif
        return nil
    }
}

private struct JoystickControls: View {
    @Environment(\.scenePhase) private var scenePhase
    let tvName: String
    let enabled: Bool
    let sessionID: String?
    let inputLog: String?
    let compactHeight: Bool
    let navigationAlignment: Alignment?
    let swapSides: (() -> Void)?
    @Binding var mode: RemoteControlMode
    let modes: [RemoteControlMode]
    @State private var input = JoystickGesture()
    @State private var sender: JoystickSender
    @GestureState private var touching = false
    @State private var ignoreUntilLift = false

    init(tvName: String, enabled: Bool, sessionID: String?, inputLog: String? = nil, compactHeight: Bool = false,
         navigationAlignment: Alignment? = nil, swapSides: (() -> Void)? = nil,
         mode: Binding<RemoteControlMode> = .constant(.eyesFree), modes: [RemoteControlMode] = RemoteControlMode.allCases,
         send: @escaping (RemoteKey, RemoteInputRequest) async -> Void) {
        self.tvName = tvName
        self.enabled = enabled
        self.sessionID = sessionID
        self.inputLog = inputLog
        self.compactHeight = compactHeight
        self.navigationAlignment = navigationAlignment
        self.swapSides = swapSides
        self._mode = mode
        self.modes = modes
        _sender = State(initialValue: JoystickSender(send: send))
    }

    var body: some View {
        RemoteModeLayout(spacing: navigationAlignment == nil ? 12 : 16) {
            HStack(spacing: 8) {
                RemoteNavigationRow(selection: $mode, modes: modes, enabled: enabled,
                                    back: { press(.back) }, home: { press(.home) })
                if let swapSides {
                    Button {
                        Haptics.tap()
                        swapSides()
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                            .frame(width: 48, height: 54)
                            .background(KeySurface(shape: RoundedRectangle(cornerRadius: 18)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Swap Sides")
                    .accessibilityIdentifier("ipadSwapSides")
                }
            }
            .frame(maxWidth: navigationAlignment == nil ? .infinity : 440)
            .frame(maxWidth: .infinity, alignment: navigationAlignment ?? .center)
        } controls: {
            joystickSurface
        }
        .foregroundStyle(Theme.label)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .onChange(of: touching) { _, active in
            if !active { endContact() }
        }
        .onChange(of: enabled) { _, _ in cancel() }
        .onChange(of: sessionID) { _, _ in cancel() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancel() } }
        .onDisappear { cancel() }
    }

    private var joystickSurface: some View {
        VStack(spacing: compactHeight ? 6 : 16) {
            surface.frame(minHeight: compactHeight ? 108 : 160)
            if let inputLog {
                Text(inputLog).font(.caption.monospaced()).accessibilityIdentifier("eyesFreeInputLog")
            }
            if !compactHeight {
                Button { press(.back) } label: {
                    Label("Back", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity).frame(height: 80)
                        .background(RoundedRectangle(cornerRadius: 24).fill(Theme.keyTop))
                }
                .buttonStyle(.plain).disabled(!enabled)
                .accessibilityIdentifier("eyesFreeBack")
            }
        }
    }

    private var surface: some View {
            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 32).fill(Theme.well)
                    RoundedRectangle(cornerRadius: 32).strokeBorder(Theme.accent.opacity(enabled ? 0.18 : 0.05))
                    if let origin = input.origin {
                        stick.position(origin)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "hand.draw").font(.system(size: 48, weight: .light))
                            Text(enabled ? "Drag to move · Tap for OK" : "Connect to a TV to start")
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                        }
                        .foregroundStyle(Theme.secondary)
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                    if touching && enabled {
                        VStack {
                            Text(input.direction?.accessibilityName ?? "Rest to pause")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.accent)
                                .padding(.top, 12)
                            Spacer()
                        }
                    }
            }
            .clipped()
            .contentShape(RoundedRectangle(cornerRadius: 32))
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .updating($touching) { _, active, _ in active = true }
                .onChanged { value in
                    guard enabled, scenePhase == .active, !ignoreUntilLift else { return }
                    let previous = input.direction
                    input.update(start: value.startLocation, location: value.location,
                                 time: value.time.timeIntervalSinceReferenceDate)
                    if previous != input.direction { sender.hold(input.direction) }
                }
                .onEnded { value in
                    guard enabled, scenePhase == .active else { cancel(); return }
                    guard !ignoreUntilLift else { endContact(); return }
                    let select = input.finish(location: value.location, time: value.time.timeIntervalSinceReferenceDate)
                    sender.release()
                    if select { sender.press(.select) }
                })
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Floating directional stick")
        .accessibilityHint("Drag in a direction and hold to repeat. A short tap selects. Lift to stop.")
        .accessibilityValue(enabled ? (input.direction?.accessibilityName ?? "Ready") : "Not connected")
        .accessibilityIdentifier("eyesFreeStick")
        .accessibilityAction { press(.select) }
        .accessibilityActions {
            Button("Move up") { press(.up) }
            Button("Move down") { press(.down) }
            Button("Move left") { press(.left) }
            Button("Move right") { press(.right) }
        }
    }

    private var stick: some View {
        let offset = input.offset
        let distance = hypot(offset.width, offset.height)
        let scale = distance > 52 ? 52 / distance : 1
        return ZStack {
            Circle().fill(Theme.accent.opacity(0.05)).frame(width: 144, height: 144)
            Circle().strokeBorder(Theme.accent.opacity(0.28), lineWidth: 2).frame(width: 144, height: 144)
            Circle().strokeBorder(Theme.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                .frame(width: 48, height: 48)
            Circle().fill(Theme.accent.opacity(input.direction == nil ? 0.35 : 0.85))
                .frame(width: 56, height: 56)
                .offset(x: offset.width * scale, y: offset.height * scale)
        }
    }

    private func press(_ key: RemoteKey) {
        guard enabled, scenePhase == .active else { return }
        ignoreUntilLift = touching
        input.cancel()
        sender.press(key)
    }

    private func endContact() {
        input.cancel()
        sender.release()
        ignoreUntilLift = false
    }

    private func cancel() {
        ignoreUntilLift = touching
        input.cancel()
        sender.stop()
    }
}

#Preview("Eyes-free") {
    JoystickControls(tvName: "Living Room TV", enabled: true, sessionID: "preview") { _, _ in }
        .frame(width: 390, height: 844)
}

#Preview("Not connected") {
    JoystickControls(tvName: "Living Room TV", enabled: false, sessionID: "preview") { _, _ in }
        .frame(width: 390, height: 844)
}
