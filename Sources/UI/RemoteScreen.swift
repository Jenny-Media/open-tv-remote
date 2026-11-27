import SwiftUI

struct RemoteScreen: View {
    @Environment(AppModel.self) private var model
    var usesSystemToolbar = false
    var pageIsActive: () -> Bool = { true }
    private var mode: PadMode {
        switch model.remoteControlMode {
        case .keyboard: .keyboard
        case .keypad: .keypad
        default: .dpad
        }
    }
    @FocusState private var focused: Bool
    @State private var heldHardwareKeys: Set<Character> = []
    #if os(iOS)
    @AppStorage("duo.bookRemoteOnRight") private var bookRemoteOnRight = false
    @AppStorage("ipad.remoteOnRight") private var tabletRemoteOnRight = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    #endif

    var body: some View {
        let controlMode = model.remoteControlMode
        let deviceID = model.currentID
        Group {
            #if os(iOS)
            adaptiveRemote
            #else
            remote(showHeader: true, tabletop: false)
            #endif
        }
        .environment(\.remoteRepeatIsCurrent, { requiresCurrentConnection in
            model.remoteControlMode == controlMode && model.currentID == deviceID && pageIsActive() &&
                model.remoteCommandsAvailable && (!requiresCurrentConnection || !model.isConnectionPaused)
        })
        .background(Theme.background.ignoresSafeArea())
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(phases: [.down, .repeat, .up], action: handleHardwareKey)
        .onAppear { focused = true }
        .onDisappear { model.typed = "" }
        .onChange(of: mode) { oldMode, _ in
            if oldMode == .keyboard { model.typed = "" }
        }
        .onChange(of: focused) { _, _ in heldHardwareKeys.removeAll() }
        .onChange(of: model.remoteCommandsAvailable) { _, _ in heldHardwareKeys.removeAll() }
    }

    #if os(iOS)
    private var adaptiveRemote: some View {
        GeometryReader { geometry in
            let layout = windowLayout(in: geometry)
            let tabletop = layout.arrangement == .tabletop
            let book = layout.arrangement == .book
            let tablet = UIDevice.current.userInterfaceIdiom == .pad
            let tabletPanels = tablet && layout.fitsTabletControlPanels && !dynamicTypeSize.isAccessibilitySize && mode != .keyboard
            let wide = UIDevice.current.userInterfaceIdiom == .phone && usesSystemToolbar && layout.hasWideFlatSurface

            ZStack {
                HStack(alignment: .top, spacing: 0) {
                    if tabletPanels {
                        tabletLandscapeRemote
                            .id(tabletRemoteOnRight)
                    } else {
                        remote(showHeader: !tabletop, tabletop: tabletop, book: book, wide: wide,
                               compactHeight: tabletop || layout.usesTrailingShortcuts,
                               showsShortcuts: !usesSystemToolbar && !tabletop && !book && !layout.usesTrailingShortcuts,
                               tablet: tablet)
                        if !usesSystemToolbar && !tabletop && layout.usesTrailingShortcuts {
                            shortcutColumn
                        }
                    }
                }
                    // Recreate transient input when its hit targets move. The selected TV,
                    // navigation page, and mode live above this view.
                    .id(layout.arrangement)
                    .id(usesSystemToolbar)
                    .id([layout.controls.minX, layout.controls.minY, layout.controls.width, layout.controls.height])
                    .frame(width: layout.controls.width, height: layout.controls.height)
                    .position(x: layout.controls.midX, y: layout.controls.midY)

                if let companion = layout.companion {
                    Group {
                        if tabletop {
                            tabletopCompanion(groupsSideBySide: companion.width >= 430)
                        } else {
                            bookControls
                        }
                    }
                    .id([companion.minX, companion.minY, companion.width, companion.height])
                    .frame(width: companion.width, height: companion.height)
                    .position(x: companion.midX, y: companion.midY)
                }
            }
            .preference(key: RemotePaneControlsKey.self, value: book || tabletop || tabletPanels)
            .onChange(of: layout.controls) { _, _ in heldHardwareKeys.removeAll() }
            .onChange(of: layout.arrangement) { _, _ in heldHardwareKeys.removeAll() }
            .onChange(of: usesSystemToolbar) { _, _ in heldHardwareKeys.removeAll() }
            .onChange(of: tabletRemoteOnRight) { _, _ in heldHardwareKeys.removeAll() }
        }
    }

    private func windowLayout(in geometry: GeometryProxy) -> RemoteWindowLayout {
        // Xcode 27.0 has Swift 6.4, but reserved regions arrived in iOS 27.1.
        #if compiler(>=6.4) && !IPHONE_SDK_27_0
        if #available(iOS 27.1, *) {
            return RemoteWindowLayout(size: geometry.size,
                                      division: geometry.reservedRegions(kind: .division).first?.frame,
                                      occlusions: geometry.reservedRegions(kind: .occlusion).map(\.frame),
                                      bookRemoteOnRight: bookRemoteOnRight)
        }
        #endif
        return RemoteWindowLayout(size: geometry.size, division: nil)
    }

    private var bookControls: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !usesSystemToolbar {
                    ViewThatFits(in: .horizontal) {
                        TopBar(showsTVSelection: false).fixedSize(horizontal: true, vertical: false)
                        TopBar(showsTVSelection: false, vertical: true)
                    }
                }
                DuoQuickControls(showsInput: true)
                    .id(model.remoteControlMode)
                swapSidesButton(remoteOnRight: $bookRemoteOnRight, identifier: "bookSwapSides")
            }
            .frame(maxWidth: 300)
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var tabletLandscapeRemote: some View {
        VStack(spacing: 12) {
            remoteHeader(showTV: true, showsShortcuts: !usesSystemToolbar)
                .frame(maxWidth: 620)
            GeometryReader { geo in
                let remoteWidth = min(430, geo.size.width * 0.54)
                let companionWidth = min(320, geo.size.width * 0.38)
                let height = min(480, max(0, geo.size.height - 16))
                HStack(spacing: 16) {
                    tabletMainControls
                        .environment(\.layoutDirection, layoutDirection)
                        .frame(width: remoteWidth)
                        .accessibilitySortPriority(1)
                    Spacer(minLength: 0)
                    tabletCompanion
                        .environment(\.layoutDirection, layoutDirection)
                        .frame(width: companionWidth)
                }
                // The preference chooses a physical side in every language.
                .environment(\.layoutDirection, tabletRemoteOnRight ? .rightToLeft : .leftToRight)
                .frame(height: height)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.top, 8)
        .overlay(alignment: .bottomTrailing) { inputLog }
    }

    @ViewBuilder private var tabletMainControls: some View {
        switch model.remoteControlMode {
        case .standard, .keypad, .keyboard:
            RemoteModeLayout { navRow } controls: {
                pad
                    .frame(maxWidth: 380, maxHeight: 380)
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .eyesFree:
            JoystickScreen(compactHeight: true)
        case .cursor:
            CursorScreen(surfaceOnly: true)
        }
    }

    private var tabletCompanion: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 20) {
                    if model.current != nil {
                        if model.remoteControlMode.isGestureMode {
                            DuoQuickControls(showsInput: true)
                        } else {
                            controls(book: false)
                        }
                    }
                    swapSidesButton(remoteOnRight: $tabletRemoteOnRight, identifier: "ipadSwapSides")
                }
                .id(model.remoteControlMode)
                .frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func swapSidesButton(remoteOnRight: Binding<Bool>, identifier: String) -> some View {
        Button {
            Haptics.tap()
            remoteOnRight.wrappedValue.toggle()
        } label: {
            Label("Swap Sides", systemImage: "arrow.left.arrow.right")
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .accessibilityHint(remoteOnRight.wrappedValue ? "Move the main remote to the left" : "Move the main remote to the right")
        .accessibilityIdentifier(identifier)
    }

    private func tabletopCompanion(groupsSideBySide: Bool) -> some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 12) {
                        TVSelectionButton(prominent: true)
                            .accessibilityIdentifier("tabletopTVSelection")
                        if let appName = model.lastReportedAppName {
                            Label("Last reported app · \(appName)", systemImage: "play.tv")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondary)
                                .accessibilityLabel("Last reported app, \(appName)")
                                .accessibilityIdentifier("tabletopForegroundApp")
                        }
                        StatusBanner()
                        if !usesSystemToolbar {
                            TopBar(showsTVSelection: false)
                        }
                    }
                    .frame(maxWidth: 440)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            if model.current != nil {
                // Keep media keys next to the hinge when status appears, wraps, or scrolls.
                DuoQuickControls(groupsSideBySide: groupsSideBySide)
                    .id(model.remoteControlMode)
                    .frame(maxWidth: 440)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
        .accessibilityIdentifier("remoteTVStatusPane")
    }

    private var shortcutColumn: some View {
        ScrollView {
            VStack(spacing: 12) {
                TopBar(showsTVSelection: false, vertical: true)
                if model.current != nil && model.remoteControlMode.isGestureMode &&
                    (model.supports(.volumeUp) || model.supports(.volumeDown)) {
                    volume.frame(height: 124)
                }
            }
            .padding(.vertical, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .frame(width: 50)
        .padding(.trailing, 12)
    }
    #endif

    private func remote(showHeader: Bool, tabletop: Bool, book: Bool = false, wide: Bool = false, compactHeight: Bool = false,
                        showsShortcuts: Bool = true, tablet: Bool = false) -> some View {
        let tabletKeyboard = tablet && mode == .keyboard
        return VStack(spacing: compactHeight ? 6 : 12) {
            remoteHeader(showTV: showHeader, showsShortcuts: showsShortcuts)
            switch model.remoteControlMode {
            case .standard, .keyboard, .keypad:
                standardMode(compactHeight: compactHeight, tabletop: tabletop, book: book, wide: wide, tablet: tablet)
            case .eyesFree:
                JoystickScreen(compactHeight: compactHeight)
            case .cursor:
                CursorScreen(compactHeight: compactHeight, wide: wide, surfaceOnly: tabletop)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .frame(maxWidth: tabletKeyboard ? 720 : wide || compactHeight ? .infinity : 600)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.adaptiveKeyboardLayout, book || tabletop || wide || tablet)
        .overlay(alignment: .bottomTrailing) { inputLog }
    }

    @ViewBuilder private func remoteHeader(showTV: Bool, showsShortcuts: Bool) -> some View {
        if showsShortcuts {
            TopBar(showsTVSelection: showTV)
        } else if showTV {
            TVSelectionButton().frame(minHeight: 40)
        }
        if showTV { StatusBanner() }
    }

    @ViewBuilder private var inputLog: some View {
        #if DEBUG
        if DemoMode.isEnabled, model.remoteControlMode != .eyesFree,
           UserDefaults.standard.bool(forKey: "demoInputLog") {
            Text("\(model.demoInputCount):\(model.demoLastInput)")
                .font(.caption.monospaced())
                .accessibilityIdentifier("demoPadInputLog")
                .allowsHitTesting(false)
        }
        #endif
    }

    private func standardMode(compactHeight: Bool, tabletop: Bool, book: Bool, wide: Bool, tablet: Bool) -> some View {
        RemoteModeLayout { navRow } controls: {
            if tablet && mode == .keyboard {
                tabletKeyboardPad
            } else if tabletop && mode == .keyboard && model.current != nil {
                tabletopKeyboard
            } else if wide && mode == .dpad {
                wideDirectionalControls
            } else if compactHeight && mode != .keyboard {
                ScrollView {
                    HStack(alignment: .top, spacing: 16) {
                        pad.frame(height: 192)
                        controls(book: book, tabletop: tabletop)
                    }
                    .padding(.horizontal, 5)
                    .padding(.bottom, 12)
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                standardControls(book: book, wide: wide, tablet: tablet)
            }
        }
    }

    private var tabletKeyboardPad: some View {
        ScrollView {
            KeyboardPadView()
                .frame(height: 460)
                .padding(.top, 8)
                .padding(.bottom, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var tabletopKeyboard: some View {
        GeometryReader { geo in
            ScrollView {
                KeyboardPadView()
                    .frame(height: max(300, geo.size.height))
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var wideDirectionalControls: some View {
        GeometryReader { geo in
            let size = min(380, max(170, geo.size.height - 24), geo.size.width * 0.55)
            ScrollView {
                HStack(spacing: 24) {
                    DPadView().frame(width: size, height: size)
                    controls(book: false).frame(maxWidth: 340)
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func standardControls(book: Bool, wide: Bool, tablet: Bool) -> some View {
        GeometryReader { geo in
            let spacing: CGFloat = geo.size.height < 620 ? 10 : 18
            let fixed: CGFloat = 192 + spacing * 2 + 28
            let padHeight = mode == .keyboard
                ? max(300, geo.size.height - (fixed - 192 - spacing))
                : min(340, max(170, geo.size.height - fixed))
            ScrollView {
                VStack(spacing: spacing) {
                    pad
                        .frame(height: padHeight)
                        .padding(.vertical, 4)
                    if mode != .keyboard { controls(book: book) }
                }
                .padding(.bottom, 20)
                .frame(maxWidth: wide ? geo.size.width * 0.88 : tablet ? 500 : 440)
                .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: tablet ? .top : .center)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var navRow: some View {
        RemoteNavigationRow(selection: Binding(get: { model.remoteControlMode }, set: model.selectRemoteMode),
                            modes: model.availableRemoteModes, enabled: model.remoteCommandsAvailable,
                            back: { sendNavigation(.back) }, home: { sendNavigation(.home) })
    }

    private func sendNavigation(_ key: RemoteKey) {
        guard model.supports(key) else { return }
        Haptics.tap()
        model.press(key)
    }

    @ViewBuilder private var pad: some View {
        switch mode {
        case .dpad: DPadView()
        case .keyboard: KeyboardPadView()
        case .keypad: KeypadView()
        }
    }

    private func controls(book: Bool, tabletop: Bool = false) -> some View {
        let showsMedia = !book && !tabletop
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                VStack(spacing: 12) {
                    RemoteKeyButton(key: .menu, symbol: "line.3.horizontal")
                    RemoteKeyButton(key: .info, symbol: "info.circle")
                }
                if book {
                    RemoteKeyButton(key: .search, symbol: "magnifyingglass")
                } else {
                    VStack(spacing: 12) {
                        RemoteKeyButton(key: .input, symbol: "rectangle.portrait.and.arrow.right")
                        RemoteKeyButton(key: .search, symbol: "magnifyingglass")
                    }
                }
                Rocker(label: "CH", up: .channelUp, down: .channelDown, upSymbol: "chevron.up", downSymbol: "chevron.down")
                if showsMedia { volume }
            }
            .frame(height: 124)

            if showsMedia {
                HStack(spacing: 12) {
                    RemoteKeyButton(key: .rewind, symbol: "backward.fill", repeats: true)
                    RemoteKeyButton(key: .playPause, symbol: "playpause.fill")
                    RemoteKeyButton(key: .fastForward, symbol: "forward.fill", repeats: true)
                    RemoteKeyButton(key: .mute, symbol: "speaker.slash.fill")
                }
                .frame(height: 56)
            }
        }
    }

    private var volume: some View {
        Rocker(label: "VOL", up: .volumeUp, down: .volumeDown, upSymbol: "plus", downSymbol: "minus")
    }

    private func handleHardwareKey(_ press: KeyPress) -> KeyPress.Result {
        let character = press.key.character
        if press.phase == .up {
            heldHardwareKeys.remove(character)
            return .ignored
        }
        if press.phase == .repeat, !heldHardwareKeys.contains(character) { return .ignored }
        let result = handleKey(press)
        if press.phase == .down, result == .handled { heldHardwareKeys.insert(character) }
        return result
    }

    /// Hardware keyboard control.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard model.remoteCommandsAvailable else { return .ignored }
        if mode == .keyboard, let result = typeKey(press) { return result }
        let key: RemoteKey? = switch press.key {
        case .upArrow: .up
        case .downArrow: .down
        case .leftArrow: .left
        case .rightArrow: .right
        case .return: .select
        case .escape, .delete: .back
        case .space: .playPause
        default:
            switch press.characters.lowercased() {
            case "h": .home
            case "m": .mute
            case "=", "+": .volumeUp
            case "-", "_": .volumeDown
            case "]": .channelUp
            case "[": .channelDown
            case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9": .digit(Int(press.characters)!)
            default: nil
            }
        }
        if press.characters == "k" {
            model.showingKeyboard = true
            return .handled
        }
        guard let key else { return .ignored }
        model.press(key)
        return .handled
    }

    /// With the keyboard pad showing, typing goes to the TV instead of triggering shortcuts.
    private func typeKey(_ press: KeyPress) -> KeyPress.Result? {
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return nil }
        switch press.key {
        case .return:
            model.typeReturn()
        case .delete:
            model.typeDelete()
        case .upArrow, .downArrow, .leftArrow, .rightArrow, .escape:
            return nil
        default:
            guard let c = press.characters.first, press.characters.count == 1, !c.isNewline,
                  c.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
            model.type(press.characters)
        }
        return .handled
    }
}

#if os(iOS)
struct RemotePaneControlsKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}
#endif

struct DuoQuickControls: View {
    @Environment(AppModel.self) private var model
    var showsInput = false
    var groupsSideBySide = false

    private let volume: [(key: RemoteKey, symbol: String, repeats: Bool)] = [
        (.volumeDown, "speaker.minus", true), (.mute, "speaker.slash.fill", false), (.volumeUp, "speaker.plus", true),
    ]
    private let playback: [(key: RemoteKey, symbol: String, repeats: Bool)] = [
        (.rewind, "backward.fill", true), (.playPause, "playpause.fill", false), (.fastForward, "forward.fill", true),
    ]

    var body: some View {
        if let device = model.current {
            let layout = groupsSideBySide ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                : AnyLayout(VStackLayout(spacing: 12))
            layout {
                group("Volume", keys: volume)
                group("Playback", keys: playback)
                if showsInput && model.supports(.input) {
                    let title = device.brand == .roku ? "TV Tuner" : "Input"
                    KeyCap(accessibilityLabel: title) { model.press(.input) } label: {
                        Label(title, systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(height: 48)
                    .disabled(!model.remoteCommandsAvailable)
                }
            }
            .id(device.id)
        }
    }

    @ViewBuilder private func group(_ title: String, keys: [(key: RemoteKey, symbol: String, repeats: Bool)]) -> some View {
        let supported = keys.filter { model.supports($0.key) }
        if !supported.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondary)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 8) {
                    ForEach(supported, id: \.key) { item in
                        RemoteKeyButton(key: item.key, symbol: item.symbol, repeats: item.repeats)
                    }
                }
                .frame(height: 48)
                .disabled(!model.remoteCommandsAvailable)
            }
        }
    }
}

// MARK: - Top bar

private struct TopBar: View {
    @Environment(AppModel.self) private var model
    var showsTVSelection = true
    var vertical = false

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            RemotePowerButton().frame(width: 48, height: 48)

            if showsTVSelection {
                TVSelectionButton()
            } else if !vertical {
                Spacer(minLength: 0)
            }

            KeyCap(shape: Circle(), accessibilityLabel: "Keyboard") {
                model.showingKeyboard = true
            } label: {
                Image(systemName: "keyboard").font(.system(size: 16, weight: .semibold))
            }
            .frame(width: 48, height: 48)

            #if os(iOS)
            if model.current != nil {
                KeyCap(shape: Circle(), accessibilityLabel: "TV Apps") {
                    model.showingApps = true
                } label: {
                    Image(systemName: "square.grid.2x2.fill").font(.system(size: 16, weight: .semibold))
                }
                .frame(width: 48, height: 48)
            }
            #endif
            SettingsButton().frame(width: 48, height: 48)
        }
    }
}

struct RemotePowerButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // Samsung TVs can use a separate full power-off command.
        KeyCap(shape: Circle(), tint: Theme.power, accessibilityLabel: "Power",
               holdAction: model.supports(.powerOff) ? { model.press(.powerOff) } : nil,
               holdName: "Turn off TV") {
            model.press(.power)
        } label: {
            Image(systemName: "power").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.power)
        }
    }
}

private struct TVSelectionButton: View {
    @Environment(AppModel.self) private var model
    var prominent = false

    var body: some View {
        Button { model.showingDevices = true } label: {
            VStack(spacing: 3) {
                if prominent {
                    Image(systemName: "tv")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                        .padding(.bottom, 8)
                }
                HStack(spacing: 5) {
                    Text(model.current?.name ?? "Choose a TV")
                        .font(prominent ? .title2.weight(.semibold) : .system(size: 17, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                }
                StatusLine(prominent: prominent)
            }
            .foregroundStyle(Theme.label)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Choose which TV to control")
    }
}

private struct StatusLine: View {
    @Environment(AppModel.self) private var model
    var prominent = false

    var body: some View {
        let (text, color): (String, Color) = switch model.state {
        case .connected: ("Connected", Theme.accent)
        case .connecting: ("Connecting…", .yellow)
        case .pairing: ("Pairing…", .yellow)
        case .unpaired: ("Not paired yet", .orange)
        case .failed: ("Not connected", Theme.power)
        case .idle: (model.current == nil ? "No TV selected" : "Ready", Theme.secondary)
        }
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(prominent ? .headline : .system(size: 12, weight: .medium)).foregroundStyle(Theme.secondary)
        }
    }
}

// MARK: - Status banner

private struct StatusBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.current == nil {
            card(symbol: "sparkle.magnifyingglass", title: "Let's find your TV",
                 message: "Just a TV Remote works with Google TV, Android TV, Roku, Samsung and LG TVs on your Wi-Fi.",
                 action: "Find TVs") { model.showingDevices = true }
        } else if let device = model.current {
            switch model.state {
            case .unpaired:
                card(symbol: "link", title: "Pair with \(device.name)",
                     message: device.brand.pairingExplanation, action: "Pair") { model.startPairing() }
            case .failed where model.isRelocating:
                card(symbol: "dot.radiowaves.left.and.right", title: "Looking for \(device.name)…",
                     message: "It may have moved to a new address on your network.", action: nil) {}
            case .failed(let message):
                card(symbol: "wifi.exclamationmark", title: "Can't reach \(device.name)",
                     message: message, action: "Try again") { model.reconnect() }
            default:
                EmptyView()
            }
        }
    }

    private func card(symbol: String, title: String, message: String, action: String?, perform: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(Theme.label)
                Text(message).font(.system(size: 13)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                if let action {
                    Button(action: perform) {
                        Text(action)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Capsule().fill(Theme.accent))
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                } else {
                    ProgressView().controlSize(.small).padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.well))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.accent.opacity(0.25), lineWidth: 1))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - Pieces

private struct Rocker: View {
    @Environment(AppModel.self) private var model
    let label: String
    let up: RemoteKey
    let down: RemoteKey
    let upSymbol: String
    let downSymbol: String

    var body: some View {
        VStack(spacing: 2) {
            KeyCap(shape: UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 6, bottomTrailingRadius: 6, topTrailingRadius: 22, style: .continuous),
                   enabled: model.supports(up), accessibilityLabel: up.accessibilityName,
                   repeatAction: model.repeatAction(for: up)) {
                model.press(up)
            } label: {
                Image(systemName: upSymbol).font(.system(size: 19, weight: .bold)).padding(.bottom, 10)
            }
            KeyCap(shape: UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 22, bottomTrailingRadius: 22, topTrailingRadius: 6, style: .continuous),
                   enabled: model.supports(down), accessibilityLabel: down.accessibilityName,
                   repeatAction: model.repeatAction(for: down)) {
                model.press(down)
            } label: {
                Image(systemName: downSymbol).font(.system(size: 19, weight: .bold)).padding(.top, 10)
            }
        }
        .overlay {
            Text(label)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(1)
                .foregroundStyle(Theme.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Theme.background))
                .overlay(Capsule().strokeBorder(.white.opacity(0.06), lineWidth: 1))
                .allowsHitTesting(false)
        }
    }
}

struct AppTile: View {
    let app: TVApp
    let style: CatalogApp?
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Button {
            Haptics.tap()
            action()
        } label: {
            ZStack {
                if let style {
                    shape.fill(style.background)
                    if let iconName = style.iconName {
                        Image(iconName)
                            .renderingMode(.original)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 56, maxHeight: 28)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .accessibilityHidden(true)
                    } else {
                        Text(style.name)
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(style.foreground)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 24)
                    }
                } else if let icon = app.iconURL {
                    shape.fill(Theme.keyTop).overlay {
                        AsyncImage(url: icon) { image in
                            image.resizable().scaledToFit().padding(8)
                        } placeholder: {
                            appName
                        }
                        .accessibilityHidden(true)
                    }
                } else {
                    KeySurface(shape: shape)
                    appName
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipShape(shape)
            .contentShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(0.08), lineWidth: 1))
            .compositingGroup()
            .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Open \(app.name)")
    }

    private var appName: some View {
        Text(app.name)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.label)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 6)
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.65), value: configuration.isPressed)
    }
}
