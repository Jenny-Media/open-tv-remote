import SwiftUI
#if os(iOS)
import UIKit
#endif

struct CursorScreen: View {
    @Environment(AppModel.self) private var model
    @AppStorage("page") private var page = 0

    var compactHeight = false
    var wide = false
    var surfaceOnly = false
    var tabletop = false
    var scrollStripOnLeading = false
    var navigationAlignment: Alignment?
    var swapSides: (() -> Void)?

    var body: some View {
        CursorControls(tvName: model.current?.name ?? "No TV selected",
                       enabled: model.supportsCursor && model.remoteInputAvailable && page == 0,
                       sessionID: model.currentID, compactHeight: compactHeight, wide: wide,
                       surfaceOnly: surfaceOnly, tabletop: tabletop, scrollStripOnLeading: scrollStripOnLeading,
                       navigationAlignment: navigationAlignment, swapSides: swapSides,
                       mode: Binding(get: { model.remoteControlMode }, set: model.selectRemoteMode),
                       modes: model.availableRemoteModes) { command, request in
            guard page == 0 else { return false }
            let sent = await model.sendCursor(command, request: request)
            if case .move = command { return sent }
            if sent {
                switch request.feedback {
                case .firm:
                    if command.isContinuous { Haptics.cursorStart() }
                    else { Haptics.tap() }
                case .soft: Haptics.cursorTick()
                case .none: break
                }
            }
            return sent
        }
    }
}

private struct CursorControls: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("cursor.reverseScroll.v1") private var reverseScroll = false
    @State private var sender: CursorSender
    @State private var showingCursorSettings = false
    let tvName: String
    let enabled: Bool
    let sessionID: String?
    let compactHeight: Bool
    let wide: Bool
    let surfaceOnly: Bool
    let tabletop: Bool
    let scrollStripOnLeading: Bool
    let navigationAlignment: Alignment?
    let swapSides: (() -> Void)?
    @Binding var mode: RemoteControlMode
    let modes: [RemoteControlMode]

    private var inputEnabled: Bool { enabled && scenePhase == .active && !showingCursorSettings }

    init(tvName: String, enabled: Bool, sessionID: String?, compactHeight: Bool = false,
         wide: Bool = false, surfaceOnly: Bool = false, tabletop: Bool = false, scrollStripOnLeading: Bool = false,
         navigationAlignment: Alignment? = nil, swapSides: (() -> Void)? = nil,
         mode: Binding<RemoteControlMode> = .constant(.cursor), modes: [RemoteControlMode] = RemoteControlMode.allCases,
         send: @escaping (CursorCommand, RemoteInputRequest) async -> Bool) {
        self.tvName = tvName
        self.enabled = enabled
        self.sessionID = sessionID
        self.compactHeight = compactHeight
        self.wide = wide
        self.surfaceOnly = surfaceOnly
        self.tabletop = tabletop
        self.scrollStripOnLeading = scrollStripOnLeading
        self.navigationAlignment = navigationAlignment
        self.swapSides = swapSides
        self._mode = mode
        self.modes = modes
        _sender = State(initialValue: CursorSender(send: send,
            speed: UserDefaults.standard.object(forKey: "cursor.speed.v2") as? Double ?? CursorMotion.defaultSpeed,
            saveSpeed: { UserDefaults.standard.set($0, forKey: "cursor.speed.v2") }))
    }

    var body: some View {
        RemoteModeLayout(spacing: navigationAlignment == nil ? 12 : 16) {
            HStack(spacing: 8) {
                RemoteNavigationRow(selection: $mode, modes: modes, enabled: enabled,
                                    back: { press(.back) }, home: { press(.home) })
                if surfaceOnly && !tabletop { cursorSettingsButton }
            }
            .frame(maxWidth: navigationAlignment == nil ? .infinity : 440)
            .frame(maxWidth: .infinity, alignment: navigationAlignment ?? .center)
        } controls: {
            if tabletop {
                HStack(alignment: .top, spacing: 8) {
                    controlSurface
                    cursorSettingsButton
                }
            } else if surfaceOnly {
                controlSurface
            } else if compactHeight {
                HStack(spacing: 16) {
                    controlSurface
                    settingsScroll.frame(maxWidth: 250)
                }
            } else {
                VStack(spacing: 12) {
                    if dynamicTypeSize.isAccessibilitySize {
                        // Keep scrollable settings outside the pointer's gesture surface.
                        controlSurface
                        settingsScroll
                    } else {
                        instructions
                        controlSurface
                        HStack(spacing: 12) {
                            actions
                            cursorSettingsButton
                        }
                    }
                }
            }
        }
        .foregroundStyle(Theme.label)
        .padding(.bottom, 12)
        .frame(maxWidth: wide || tabletop ? .infinity : 600, maxHeight: .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .onChange(of: enabled) { _, _ in sender.stop() }
        .onChange(of: sessionID) { _, _ in sender.stop() }
        .onChange(of: scrollStripOnLeading) { _, _ in sender.stop() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { sender.stop() } }
        .onDisappear { sender.stop() }
        .sheet(isPresented: $showingCursorSettings) {
            NavigationStack {
                Form {
                    Section { preferences } footer: {
                        if surfaceOnly { Text(scrollHint) }
                    }
                    if let swapSides {
                        Section {
                            Button("Swap Sides", systemImage: "arrow.left.arrow.right") {
                                Haptics.tap()
                                showingCursorSettings = false
                                swapSides()
                            }
                            .accessibilityIdentifier("ipadCursorSwapSides")
                        }
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("Cursor Settings")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingCursorSettings = false }
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 350, minHeight: 210)
            #endif
        }
    }

    private var settingsScroll: some View {
        ScrollView {
            VStack(spacing: 16) {
                instructions
                actions
                cursorSettingsButton
            }
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var instructions: some View {
        VStack(spacing: 5) {
            if dynamicTypeSize.isAccessibilitySize {
                Text(tvName).font(.caption).foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
            }
            Text(enabled ? "Drag to move · Tap to click" : "Connect to your LG TV first")
                .font(.system(.headline, design: .rounded))
            Text(status)
                .font(.footnote)
                .foregroundStyle(sender.unavailable ? Theme.power : Theme.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var controlSurface: some View {
        HStack(spacing: 12) {
            if scrollStripOnLeading { scrollStrip }
            touchpad
            if !scrollStripOnLeading { scrollStrip }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: compactHeight ? 108 : dynamicTypeSize.isAccessibilitySize ? 220 : 180)
    }

    private var scrollStrip: some View {
        CursorScrollStrip(enabled: inputEnabled, activity: sender.scrollActivity,
                          scroll: { scroll(0, $0) }, release: { sender.release() })
            .frame(width: dynamicTypeSize.isAccessibilitySize ? 140 : 56)
            .id(sessionID)
    }

    private var cursorSettingsButton: some View {
        Button {
            sender.stop()
            showingCursorSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 18, weight: .semibold))
                .frame(minWidth: 52, minHeight: 56)
                .background(KeySurface(shape: RoundedRectangle(cornerRadius: 18)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cursor Settings")
        .accessibilityIdentifier("lgCursorSettings")
    }

    private var preferences: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Cursor speed")
                Spacer()
                Text("\(Int(sender.speed))×").monospacedDigit()
            }
            .font(.subheadline.weight(.medium))
            Slider(value: Binding(get: { sender.speed }, set: { sender.setSpeed($0) }), in: CursorMotion.speedRange, step: 4)
                .accessibilityLabel("Cursor speed")
            Toggle("Reverse scrolling", isOn: $reverseScroll)
                .font(.subheadline)
                .onChange(of: reverseScroll) { _, _ in sender.release() }
        }
    }

    @ViewBuilder private var actions: some View {
        #if os(iOS)
        action("Back", symbol: "arrow.uturn.backward", command: .back)
        #else
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                action("Back", symbol: "arrow.uturn.backward", command: .back)
                action("Click", symbol: "cursorarrow.click", command: .click)
            }
        } else {
            HStack(spacing: 12) {
                action("Back", symbol: "arrow.uturn.backward", command: .back)
                action("Click", symbol: "cursorarrow.click", command: .click)
            }
        }
        #endif
    }

    private var status: String {
        if !enabled { return "Choose or reconnect to your TV above." }
        if sender.unavailable { return "Cursor not ready. Try again, or reconnect above." }
        return scrollHint
    }

    private var scrollHint: String {
        #if os(iOS)
        return "Scroll with two fingers or the side strip"
        #else
        return "Drag the side strip to scroll"
        #endif
    }

    private var touchpad: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30).fill(Theme.well)
            RoundedRectangle(cornerRadius: 30).strokeBorder(Theme.accent.opacity(0.2))
            VStack(spacing: 12) {
                Image(systemName: "hand.draw").font(.system(size: 48, weight: .light))
                if surfaceOnly {
                    Text(enabled && !sender.unavailable ? "Drag to move · Tap to click" : status)
                        .font(.subheadline)
                        .foregroundStyle(sender.unavailable ? Theme.power : Theme.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                } else if !dynamicTypeSize.isAccessibilitySize {
                    Text("Look at your TV").font(.system(.body, design: .rounded).weight(.medium))
                }
            }
            .foregroundStyle(Theme.secondary.opacity(0.6))
            .allowsHitTesting(false)
            #if os(iOS)
            CursorTouchpad(enabled: inputEnabled,
                           move: { dx, dy in move(dx, dy) },
                           scroll: { dx, dy in scroll(dx, dy) },
                           click: { press(.click) }, release: { sender.release() })
                .id(sessionID)
            #else
            MacCursorTouchpad(enabled: inputEnabled,
                              move: { dx, dy in move(dx, dy) },
                              click: { press(.click) }, release: { sender.release() })
                .id(sessionID)
            #endif
        }
        .clipShape(RoundedRectangle(cornerRadius: 30))
        .accessibilityIdentifier("lgCursorTouchpad")
    }

    private func action(_ title: String, symbol: String, command: CursorCommand) -> some View {
        Button {
            press(command)
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(RoundedRectangle(cornerRadius: 18).fill(Theme.keyTop))
        }
        .buttonStyle(.plain).disabled(!enabled)
    }

    private func move(_ dx: Double, _ dy: Double) {
        guard inputEnabled else { return }
        sender.drag(dx: dx, dy: dy)
    }

    private func scroll(_ dx: Double, _ dy: Double) {
        guard inputEnabled else { return }
        if case let .scroll(x, y)? = CursorMotion.scroll(dx: dx, dy: dy, reversed: reverseScroll) {
            sender.scroll(dx: x, dy: y)
        }
    }

    private func press(_ command: CursorCommand) {
        guard inputEnabled else { return }
        sender.press(command)
    }
}

private struct CursorScrollStrip: View {
    let enabled: Bool
    let activity: Int
    let scroll: (Double) -> Void
    let release: () -> Void
    @State private var previous: CGFloat?
    @State private var ignoreUntilLift = false
    @State private var highlighting = false
    @GestureState private var touching = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chevron.up").font(.system(size: 16, weight: .semibold))
            Spacer(minLength: 0)
            Capsule().fill(Theme.accent.opacity(highlighting && enabled ? 0.9 : 0.35))
                .frame(width: 8, height: 50)
            Text("Scroll").font(.caption2.weight(.semibold))
            Spacer(minLength: 0)
            Image(systemName: "chevron.down").font(.system(size: 16, weight: .semibold))
        }
        .foregroundStyle(Theme.secondary)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 25).fill(Theme.well))
        .overlay(RoundedRectangle(cornerRadius: 25).strokeBorder(Theme.accent.opacity(highlighting && enabled ? 0.4 : 0.12)))
        .contentShape(RoundedRectangle(cornerRadius: 25))
        .gesture(DragGesture(minimumDistance: 0)
            .updating($touching) { _, active, _ in active = true }
            .onChanged { value in
                guard enabled, !ignoreUntilLift else { return }
                if previous == nil { release() }
                scroll(Double(value.translation.height - (previous ?? 0)))
                previous = value.translation.height
            }
            .onEnded { _ in endContact() })
        .onChange(of: touching) { _, active in if !active { endContact() } }
        .onChange(of: activity) { _, _ in highlighting = enabled && touching && !ignoreUntilLift }
        .task(id: activity) {
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            highlighting = false
        }
        .onChange(of: enabled) { _, _ in
            ignoreUntilLift = touching
            highlighting = false
            previous = nil
            release()
        }
        .onDisappear { release() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scroll strip")
        .accessibilityHint("Slide up or down to scroll the TV content under the pointer.")
        .accessibilityAdjustableAction { direction in
            guard enabled else { return }
            release()
            switch direction {
            case .increment: scroll(-18)
            case .decrement: scroll(18)
            @unknown default: break
            }
        }
    }

    private func endContact() {
        previous = nil
        ignoreUntilLift = false
        highlighting = false
        release()
    }
}

#if os(iOS)
/// Native recognizers distinguish pointer movement, two-finger scrolling and a tap.
/// A cancelled/scrolling gesture must never turn into a pointer click.
private final class CursorAccessibleView: UIView {
    var activate: (() -> Bool)?
    override func accessibilityActivate() -> Bool { activate?() ?? false }
}

private struct CursorTouchpad: UIViewRepresentable {
    let enabled: Bool
    let move: (Double, Double) -> Void
    let scroll: (Double, Double) -> Void
    let click: () -> Void
    let release: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = CursorAccessibleView()
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        let move = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.move(_:)))
        move.minimumNumberOfTouches = 1
        move.maximumNumberOfTouches = 1
        let scroll = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.scroll(_:)))
        scroll.minimumNumberOfTouches = 2
        scroll.maximumNumberOfTouches = 2
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.click(_:)))
        tap.require(toFail: move)
        tap.require(toFail: scroll)
        for recognizer in [move, scroll, tap] { view.addGestureRecognizer(recognizer) }
        view.isAccessibilityElement = true
        view.accessibilityTraits = .button
        view.accessibilityLabel = "LG cursor touchpad"
        view.accessibilityHint = "Use Actions to move the pointer or scroll. Double-tap to click."
        let coordinator = context.coordinator
        view.activate = { [weak coordinator] in coordinator?.accessibleClick() ?? false }
        view.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Move pointer up", target: coordinator, selector: #selector(Coordinator.accessibleUp(_:))),
            UIAccessibilityCustomAction(name: "Move pointer down", target: coordinator, selector: #selector(Coordinator.accessibleDown(_:))),
            UIAccessibilityCustomAction(name: "Move pointer left", target: coordinator, selector: #selector(Coordinator.accessibleLeft(_:))),
            UIAccessibilityCustomAction(name: "Move pointer right", target: coordinator, selector: #selector(Coordinator.accessibleRight(_:))),
            UIAccessibilityCustomAction(name: "Scroll up", target: coordinator, selector: #selector(Coordinator.accessibleScrollUp(_:))),
            UIAccessibilityCustomAction(name: "Scroll down", target: coordinator, selector: #selector(Coordinator.accessibleScrollDown(_:)))
        ]
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
        view.isUserInteractionEnabled = enabled
        view.accessibilityTraits = enabled ? .button : [.button, .notEnabled]
        for recognizer in view.gestureRecognizers ?? [] where recognizer.isEnabled != enabled {
            recognizer.isEnabled = enabled
        }
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) { coordinator.parent.release() }

    final class Coordinator: NSObject {
        var parent: CursorTouchpad
        init(_ parent: CursorTouchpad) { self.parent = parent }

        @objc func move(_ pan: UIPanGestureRecognizer) { handle(pan, scrolling: false) }
        @objc func scroll(_ pan: UIPanGestureRecognizer) { handle(pan, scrolling: true) }
        @objc func click(_ tap: UITapGestureRecognizer) {
            if parent.enabled, tap.state == .ended { parent.click() }
        }

        func accessibleClick() -> Bool {
            guard parent.enabled else { return false }
            parent.click()
            return true
        }

        @objc func accessibleUp(_ action: UIAccessibilityCustomAction) -> Bool { nudge(0, -4) }
        @objc func accessibleDown(_ action: UIAccessibilityCustomAction) -> Bool { nudge(0, 4) }
        @objc func accessibleLeft(_ action: UIAccessibilityCustomAction) -> Bool { nudge(-4, 0) }
        @objc func accessibleRight(_ action: UIAccessibilityCustomAction) -> Bool { nudge(4, 0) }
        @objc func accessibleScrollUp(_ action: UIAccessibilityCustomAction) -> Bool { scrollStep(-18) }
        @objc func accessibleScrollDown(_ action: UIAccessibilityCustomAction) -> Bool { scrollStep(18) }

        private func nudge(_ dx: Double, _ dy: Double) -> Bool {
            guard parent.enabled else { return false }
            parent.release()
            parent.move(dx, dy)
            return true
        }

        private func scrollStep(_ dy: Double) -> Bool {
            guard parent.enabled else { return false }
            parent.release()
            parent.scroll(0, dy)
            return true
        }

        private func handle(_ pan: UIPanGestureRecognizer, scrolling: Bool) {
            guard parent.enabled else { parent.release(); return }
            switch pan.state {
            case .began, .changed:
                if pan.state == .began { parent.release() }
                let delta = pan.translation(in: pan.view)
                pan.setTranslation(.zero, in: pan.view)
                if scrolling { parent.scroll(Double(delta.x), Double(delta.y)) }
                else {
                    parent.move(Double(delta.x), Double(delta.y))
                }
            case .ended, .cancelled, .failed: parent.release()
            default: break
            }
        }
    }
}
#else
private struct MacCursorTouchpad: View {
    let enabled: Bool
    let move: (Double, Double) -> Void
    let click: () -> Void
    let release: () -> Void
    @State private var previous: CGSize = .zero
    @State private var dragging = false
    @State private var ignoreUntilLift = false

    var body: some View {
        Color.clear.contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 6)
                .onChanged { value in
                    dragging = true
                    guard enabled, !ignoreUntilLift else { return }
                    let dx = Double(value.translation.width - previous.width)
                    let dy = Double(value.translation.height - previous.height)
                    move(dx, dy)
                    previous = value.translation
                }
                .onEnded { _ in
                    previous = .zero
                    dragging = false
                    ignoreUntilLift = false
                    release()
                }
                .exclusively(before: TapGesture().onEnded { if enabled { click() } }))
            .onChange(of: enabled) { _, _ in
                ignoreUntilLift = dragging
                previous = .zero
                release()
            }
            .accessibilityLabel("LG cursor touchpad")
    }
}
#endif

#Preview("LG cursor") {
    CursorControls(tvName: "Living Room LG", enabled: true, sessionID: "preview") { _, _ in true }
        .frame(width: 390, height: 844)
}
