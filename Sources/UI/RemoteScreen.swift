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
    @Environment(\.layoutDirection) private var layoutDirection
    #if os(iOS)
    @AppStorage("duo.bookRemoteOnRight") private var bookRemoteOnRight = false
    @AppStorage("ipad.remoteOnRight") private var tabletRemoteOnRight = false
    @AppStorage("ipad.mediaControlsPinned") private var tabletMediaPinned = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
            let tabletopTyping = tabletop && !tablet && mode == .keyboard
            let roomyTablet = tablet && layout.fitsTabletControlPanels && !dynamicTypeSize.isAccessibilitySize
            let hasTabletMedia = tablet && model.current != nil
            let bottomMedia = hasTabletMedia && tabletMediaPinned && !roomyTablet && !dynamicTypeSize.isAccessibilitySize
                && layout.controls.width >= 580 && layout.controls.height >= 540
            let sideMedia = hasTabletMedia && tabletMediaPinned && roomyTablet
            let mediaPin = hasTabletMedia && !bottomMedia && !sideMedia ? $tabletMediaPinned : nil
            let wide = UIDevice.current.userInterfaceIdiom == .phone && usesSystemToolbar && layout.hasWideFlatSurface
            let phoneKeyboardLayout: KeyboardPadView.PhoneLayout = switch layout.arrangement {
            case .compact where layout.controls.height > layout.controls.width:
                usesSystemToolbar && layout.controls.width < 500 ? .foldedPortrait : .portrait
            case .compact where layout.hasWideFlatSurface:
                .wideLandscape
            default:
                .adaptive
            }

            ZStack {
                HStack(alignment: .top, spacing: 0) {
                    if roomyTablet {
                        tabletLandscapeRemote(showsMedia: sideMedia, mediaPin: mediaPin)
                            .id(tabletRemoteOnRight)
                    } else if tabletopTyping {
                        tabletopKeyboardPane
                    } else {
                        VStack(spacing: 12) {
                            remote(showHeader: !tabletop, tabletop: tabletop, book: book, wide: wide,
                                   compactHeight: tabletop || layout.usesTrailingShortcuts,
                                   showsShortcuts: !usesSystemToolbar && !tabletop && !book && !layout.usesTrailingShortcuts,
                                   tablet: tablet, tabletLandscape: tablet && layout.controls.width > layout.controls.height,
                                   mediaPin: layout.usesTrailingShortcuts && !usesSystemToolbar ? nil : mediaPin,
                                   mediaAboveKeys: bottomMedia && mode == .keyboard, phoneKeyboardLayout: phoneKeyboardLayout)
                                .id(bottomMedia)
                            if bottomMedia && mode != .keyboard {
                                tabletMediaPanel(horizontal: true)
                                    .frame(maxWidth: 620)
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 8)
                            }
                        }
                        if !usesSystemToolbar && !tabletop && layout.usesTrailingShortcuts {
                            shortcutColumn(mediaPin: mediaPin)
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
                            tabletopCompanion(groupsSideBySide: companion.width >= 430, keyboard: tabletopTyping)
                        } else {
                            bookControls
                        }
                    }
                    .id([companion.minX, companion.minY, companion.width, companion.height])
                    .frame(width: companion.width, height: companion.height)
                    .position(x: companion.midX, y: companion.midY)
                }
            }
            .preference(key: RemotePaneControlsKey.self, value: book || tabletop || tablet)
            .onChange(of: layout.controls) { _, _ in heldHardwareKeys.removeAll() }
            .onChange(of: layout.arrangement) { _, _ in heldHardwareKeys.removeAll() }
            .onChange(of: usesSystemToolbar) { _, _ in heldHardwareKeys.removeAll() }
            .onChange(of: tabletRemoteOnRight) { _, _ in heldHardwareKeys.removeAll() }
            .onChange(of: tabletMediaPinned) { _, _ in heldHardwareKeys.removeAll() }
        }
    }

    private func windowLayout(in geometry: GeometryProxy) -> RemoteWindowLayout {
        #if DEBUG
        if DemoMode.showsShortTabletop && geometry.size.height > geometry.size.width {
            // The fixture reserves a 34-point hinge and leaves a 160-point controls pane.
            let division = CGRect(x: 0, y: geometry.size.height - 200, width: geometry.size.width, height: 34)
            return RemoteWindowLayout(size: geometry.size, division: division)
        }
        #endif
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
                swapSidesButton(remoteOnRight: $bookRemoteOnRight, identifier: "bookSwapSides")
            }
            .frame(maxWidth: 300)
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func tabletLandscapeRemote(showsMedia: Bool, mediaPin: Binding<Bool>?) -> some View {
        VStack(spacing: 12) {
            remoteHeader(showTV: true, showsShortcuts: !usesSystemToolbar, mediaPin: mediaPin)
                .frame(maxWidth: 620)
            GeometryReader { geo in
                let keyboard = mode == .keyboard
                let showsCompanion = showsMedia || keyboard
                let width = max(0, geo.size.width - 48)
                let companionWidth = min(248, width * 0.28, max(0, width - 24 - KeyboardPadView.minimumTabletKeyGridWidth))
                let remoteWidth = showsCompanion ? max(0, width - companionWidth - 24) : width
                HStack(spacing: 24) {
                    tabletMainControls(showsMedia: showsMedia)
                        .environment(\.layoutDirection, layoutDirection)
                        .frame(width: remoteWidth)
                        .id(showsMedia)
                        .accessibilitySortPriority(1)
                    if showsCompanion {
                        GeometryReader { panel in
                            ScrollView {
                                VStack(spacing: 18) {
                                    if keyboard {
                                        TabletKeyboardNavigation()
                                    }
                                    if showsMedia {
                                        tabletMediaPanel(horizontal: false, showsSwap: !keyboard)
                                    }
                                    if keyboard {
                                        swapSidesButton(remoteOnRight: $tabletRemoteOnRight, identifier: "ipadSwapSides")
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: panel.size.height)
                            }
                            .scrollBounceBehavior(.basedOnSize)
                        }
                        .environment(\.layoutDirection, layoutDirection)
                        .frame(width: companionWidth)
                    }
                }
                // The preference chooses a physical side in every language.
                .environment(\.layoutDirection, tabletControlDirection)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.top, 8)
        .overlay(alignment: .bottomTrailing) { inputLog }
    }

    @ViewBuilder private func tabletMainControls(showsMedia: Bool) -> some View {
        switch model.remoteControlMode {
        case .keyboard:
            tabletKeyboardControls(stacked: false)
                .frame(maxWidth: 1008)
                .environment(\.adaptiveKeyboardLayout, true)
        case .standard, .keypad:
            RemoteModeLayout {
                HStack(spacing: 12) {
                    navRow.frame(maxWidth: 480)
                    if !showsMedia {
                        swapSidesButton(remoteOnRight: $tabletRemoteOnRight, identifier: "ipadSwapSides")
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            } controls: {
                ScrollView {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 24) {
                            pad.frame(width: 320, height: 320)
                                .environment(\.layoutDirection, layoutDirection)
                            controls(book: false, tablet: true).frame(width: 192)
                                .environment(\.layoutDirection, layoutDirection)
                        }
                        .environment(\.layoutDirection, tabletControlDirection)
                        VStack(spacing: 18) {
                            pad.frame(maxWidth: 320).frame(height: 300)
                            controls(book: false, tablet: true).frame(maxWidth: 300)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxHeight: 460)
        case .eyesFree:
            JoystickScreen(compactHeight: true, navigationAlignment: tabletPadOnLeading ? .leading : .trailing,
                           swapSides: showsMedia ? nil : { tabletRemoteOnRight.toggle() })
            .frame(maxHeight: 680)
        case .cursor:
            CursorScreen(wide: true, surfaceOnly: true, scrollStripOnLeading: tabletPadOnLeading,
                         navigationAlignment: tabletPadOnLeading ? .leading : .trailing,
                         swapSides: { tabletRemoteOnRight.toggle() })
            .frame(maxHeight: 680)
        }
    }

    private var tabletPadOnLeading: Bool {
        tabletRemoteOnRight != (layoutDirection == .leftToRight)
    }

    private var tabletControlDirection: LayoutDirection {
        tabletRemoteOnRight ? .rightToLeft : .leftToRight
    }

    private func tabletMediaPanel(horizontal: Bool, showsSwap: Bool = true) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("Media Controls").font(.headline)
                    .accessibilityIdentifier("ipadPinnedMedia")
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button {
                    Haptics.tap()
                    tabletMediaPinned = false
                } label: {
                    Image(systemName: "pin.slash")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondary)
                .accessibilityLabel("Unpin Media Controls")
            }
            DuoQuickControls(showsInput: true, groupsSideBySide: horizontal, groupSpacing: 18)
            if !horizontal && showsSwap {
                swapSidesButton(remoteOnRight: $tabletRemoteOnRight, identifier: "ipadSwapSides")
            }
        }
        .padding(12)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: 24))
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

    private func tabletopCompanion(groupsSideBySide: Bool, keyboard: Bool) -> some View {
        Group {
            if keyboard {
                GeometryReader { geometry in
                    ScrollView {
                        VStack(spacing: 8) {
                            tabletopTVStatus(prominent: false)
                            tabletopKeyboardNavigation
                                #if DEBUG
                                .frame(maxWidth: DemoMode.shortTabletopCompanionWidth ?? .infinity)
                                #endif
                        }
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .bottom)
                    }
                    .defaultScrollAnchor(.bottom)
                    .scrollBounceBehavior(.basedOnSize)
                }
            } else {
                VStack(spacing: 0) {
                    GeometryReader { geometry in
                        ScrollView {
                            tabletopTVStatus(prominent: true)
                                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                    }
                    // Keep media keys next to the hinge when status appears, wraps, or scrolls.
                    tabletopMedia(groupsSideBySide: groupsSideBySide)
                }
            }
        }
        .accessibilityIdentifier("remoteTVStatusPane")
    }

    private var tabletopKeyboardNavigation: some View {
        VStack(spacing: 12) {
            navRow
            if model.current != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) {
                        DuoQuickControls()
                            .frame(width: 166)
                            .environment(\.layoutDirection, layoutDirection)
                        Spacer(minLength: 24)
                            .frame(maxWidth: 64)
                        tabletopDirectionPad
                            .environment(\.layoutDirection, layoutDirection)
                    }
                    // Keep the D-pad on the physical right in every language.
                    .environment(\.layoutDirection, .leftToRight)
                    VStack(spacing: 12) {
                        DuoQuickControls()
                        tabletopDirectionPad
                    }
                }
            } else {
                tabletopDirectionPad
            }
        }
        .frame(maxWidth: 440)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var tabletopDirectionPad: some View {
        VStack(spacing: 8) {
            DPadView().frame(width: 156, height: 156)
            KeyboardClearButton().frame(width: 64, height: 44)
        }
    }

    private func tabletopTVStatus(prominent: Bool) -> some View {
        VStack(spacing: 12) {
            TVSelectionButton(prominent: prominent)
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
    }

    @ViewBuilder private func tabletopMedia(groupsSideBySide: Bool) -> some View {
        if model.current != nil {
            DuoQuickControls(groupsSideBySide: groupsSideBySide)
                .frame(maxWidth: 440)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
    }

    private var tabletopKeyboardPane: some View {
        GeometryReader { viewport in
            Group {
                if viewport.size.height >= KeyboardPadView.minimumPhoneKeyGridHeight {
                    KeyboardPadView(layout: .phoneKeys)
                        .environment(\.adaptiveKeyboardLayout, true)
                } else {
                    KeyboardSheetButton().accessibilityIdentifier("tabletopKeyboardSheet")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .overlay(alignment: .bottomTrailing) { inputLog }
    }

    private func shortcutColumn(mediaPin: Binding<Bool>?) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                TopBar(showsTVSelection: false, vertical: true)
                if let mediaPin {
                    TabletMediaButton(pinned: mediaPin)
                } else if model.current != nil && model.remoteControlMode.isGestureMode &&
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
                        showsShortcuts: Bool = true, tablet: Bool = false, tabletLandscape: Bool = false,
                        mediaPin: Binding<Bool>? = nil,
                        mediaAboveKeys: Bool = false, phoneKeyboardLayout: KeyboardPadView.PhoneLayout = .adaptive) -> some View {
        let tabletKeyboard = tablet && mode == .keyboard
        #if os(iOS)
        let phoneKeyboard = !tablet && mode == .keyboard
        let inlineTVSelection = phoneKeyboard && compactHeight && !tabletop
        #else
        let phoneKeyboard = false
        let inlineTVSelection = false
        #endif
        let fullWidthKeyboard = phoneKeyboard && phoneKeyboardLayout == .wideLandscape
        return VStack(spacing: compactHeight ? 6 : 12) {
            if !inlineTVSelection {
                remoteHeader(showTV: showHeader, showsShortcuts: showsShortcuts, mediaPin: mediaPin)
                    .frame(maxWidth: tabletKeyboard ? 620 : .infinity)
            }
            switch model.remoteControlMode {
            case .keyboard where tablet:
                tabletKeyboardControls(stacked: true, showsMedia: mediaAboveKeys)
            case .keyboard where phoneKeyboard:
                RemoteModeLayout(spacing: compactHeight ? 8 : 12) {
                    if inlineTVSelection {
                        HStack(spacing: 12) {
                            TVSelectionButton()
                                .frame(width: 144)
                                .frame(minHeight: 44)
                            navRow
                        }
                        StatusBanner()
                    } else {
                        navRow
                    }
                } controls: {
                    KeyboardPadView(layout: .phone(phoneKeyboardLayout))
                        .frame(maxWidth: compactHeight || fullWidthKeyboard ? .infinity : 440)
                        .padding(.bottom, 6)
                }
            case .standard, .keyboard, .keypad:
                standardMode(compactHeight: compactHeight, tabletop: tabletop, book: book, wide: wide, tablet: tablet)
            case .eyesFree:
                JoystickScreen(compactHeight: compactHeight)
            case .cursor:
                #if os(iOS)
                CursorScreen(compactHeight: compactHeight, wide: wide, surfaceOnly: tabletop,
                             scrollStripOnLeading: tabletLandscape && tabletPadOnLeading,
                             swapSides: tabletLandscape ? { tabletRemoteOnRight.toggle() } : nil)
                #else
                CursorScreen(compactHeight: compactHeight, wide: wide, surfaceOnly: tabletop)
                #endif
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .frame(maxWidth: tabletKeyboard ? 860 : wide || compactHeight || fullWidthKeyboard ? .infinity : 600)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.adaptiveKeyboardLayout, book || tabletop || wide || tablet || phoneKeyboard)
        .overlay(alignment: .bottomTrailing) { inputLog }
    }

    @ViewBuilder private func remoteHeader(showTV: Bool, showsShortcuts: Bool, mediaPin: Binding<Bool>? = nil) -> some View {
        #if os(iOS)
        if let mediaPin {
            if showsShortcuts {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        TopBar(showsTVSelection: showTV).frame(minWidth: 326)
                        TabletMediaButton(pinned: mediaPin)
                    }
                    VStack(spacing: 8) {
                        if showTV { TVSelectionButton().frame(minHeight: 44) }
                        HStack {
                            TopBar(showsTVSelection: false)
                            TabletMediaButton(pinned: mediaPin)
                        }
                    }
                }
            } else if showTV {
                HStack {
                    TVSelectionButton().frame(minHeight: 44)
                    TabletMediaButton(pinned: mediaPin)
                }
            }
        } else {
            remoteHeaderShortcuts(showTV: showTV, showsShortcuts: showsShortcuts)
        }
        #else
        remoteHeaderShortcuts(showTV: showTV, showsShortcuts: showsShortcuts)
        #endif
        if showTV { StatusBanner() }
    }

    @ViewBuilder private func remoteHeaderShortcuts(showTV: Bool, showsShortcuts: Bool) -> some View {
        if showsShortcuts {
            TopBar(showsTVSelection: showTV)
        } else if showTV {
            TVSelectionButton().frame(minHeight: 40)
        }
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
        let usesCompactPad = compactHeight && mode != .keyboard
        return RemoteModeLayout {
            #if os(iOS)
            if tablet && usesCompactPad {
                HStack(spacing: 8) {
                    navRow
                    swapSidesButton(remoteOnRight: $tabletRemoteOnRight, identifier: "ipadSwapSides")
                        .labelStyle(.iconOnly)
                        .fixedSize(horizontal: true, vertical: false)
                }
            } else {
                navRow
            }
            #else
            navRow
            #endif
        } controls: {
            if wide && mode == .dpad {
                wideDirectionalControls
            } else if usesCompactPad {
                ScrollView {
                    HStack(alignment: .top, spacing: 16) {
                        pad.frame(height: 192)
                            .environment(\.layoutDirection, layoutDirection)
                        controls(book: book, tabletop: tabletop, tablet: tablet)
                            .environment(\.layoutDirection, layoutDirection)
                    }
                    #if os(iOS)
                    .environment(\.layoutDirection, tablet ? tabletControlDirection : layoutDirection)
                    #endif
                    .padding(.horizontal, 5)
                    .padding(.bottom, 12)
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                standardControls(book: book, wide: wide, tablet: tablet)
            }
        }
    }

    private func tabletKeyboardControls(stacked: Bool, showsMedia: Bool = false) -> some View {
        GeometryReader { viewport in
            #if DEBUG
            let width = min(viewport.size.width, DemoMode.keyboardTestWidth ?? .infinity)
            #else
            let width = viewport.size.width
            #endif
            let hasPortraitRoom = stacked && viewport.size.height > viewport.size.width
            let spacingScale = hasPortraitRoom ? min(1, max(0, (viewport.size.height - 680) / 320)) : 0
            let controlsSpacing = 12 + 18 * spacingScale
            let typingAreaOffset = stacked ? TabletKeyboardNavigation.height + controlsSpacing : 0
            let rowCount: CGFloat = width >= KeyboardPadView.minimumTabletKeyGridWidth ? 5 : 4
            let rowSpacing = (rowCount - 1) * 9
            let minimumPadHeight = typingAreaOffset + rowCount * 44 + rowSpacing
            let maximumPadHeight = typingAreaOffset + rowCount * 64 + rowSpacing
            // Leave the D-pad and keyboard anchored as the pinned media group moves up.
            let mediaLift = hasPortraitRoom && showsMedia ? min(56, max(0, (viewport.size.height - 860) / 6)) : 0
            VStack(spacing: 12 + 30 * spacingScale) {
                navRow.frame(maxWidth: 480)
                #if os(iOS)
                if showsMedia {
                    tabletMediaPanel(horizontal: true)
                        .frame(maxWidth: 620)
                        .padding(.bottom, mediaLift)
                }
                #endif
                GeometryReader { keyboard in
                    ScrollView {
                        KeyboardPadView(layout: stacked
                            ? .stackedTablet(controlsSpacing: controlsSpacing) : .tabletKeys)
                            .frame(height: max(minimumPadHeight, keyboard.size.height))
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(width: width)
                    .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: maximumPadHeight)
            }
            .padding(.bottom, stacked ? 8 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: stacked ? .bottom : .center)
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
                    if mode != .keyboard { controls(book: book, tablet: tablet) }
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

    private func controls(book: Bool, tabletop: Bool = false, tablet: Bool = false) -> some View {
        let showsMedia = !book && !tabletop && !tablet
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                VStack(spacing: 12) {
                    RemoteKeyButton(key: .menu, symbol: "line.3.horizontal")
                    RemoteKeyButton(key: .info, symbol: "info.circle")
                }
                if book || tablet {
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
            model.showKeyboard()
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

#if os(iOS)
private struct TabletMediaButton: View {
    @Binding var pinned: Bool
    @State private var showingControls = false

    var body: some View {
        KeyCap(shape: Circle(), accessibilityLabel: "Media Controls") {
            showingControls = true
        } label: {
            Image(systemName: "play.rectangle")
                .font(.system(size: 17, weight: .semibold))
        }
        .frame(width: 48, height: 48)
        .popover(isPresented: $showingControls) {
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Text("Media Controls").font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button {
                            showingControls = false
                        } label: {
                            Image(systemName: "xmark")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close Media Controls")
                    }
                    DuoQuickControls(showsInput: true, groupSpacing: 18)
                    Button {
                        Haptics.tap()
                        pinned.toggle()
                    } label: {
                        Label(pinned ? "Unpin Media Controls" : "Pin on iPad",
                              systemImage: pinned ? "pin.slash" : "pin")
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .foregroundStyle(.black)
                    if pinned {
                        Text("Docked when the iPad window has room.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondary)
                    }
                }
                .foregroundStyle(Theme.label)
                .padding(20)
                .frame(maxWidth: 340)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(idealWidth: 312, idealHeight: 420)
            .presentationCompactAdaptation(.sheet)
        }
    }
}
#endif

struct DuoQuickControls: View {
    @Environment(AppModel.self) private var model
    var showsInput = false
    var groupsSideBySide = false
    var groupSpacing: CGFloat = 12

    private let volume: [(key: RemoteKey, symbol: String, repeats: Bool)] = [
        (.volumeDown, "speaker.minus", true), (.mute, "speaker.slash.fill", false), (.volumeUp, "speaker.plus", true),
    ]
    private let playback: [(key: RemoteKey, symbol: String, repeats: Bool)] = [
        (.rewind, "backward.fill", true), (.playPause, "playpause.fill", false), (.fastForward, "forward.fill", true),
    ]

    var body: some View {
        if let device = model.current {
            let layout = groupsSideBySide ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                : AnyLayout(VStackLayout(spacing: groupSpacing))
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
                    .padding(.top, groupsSideBySide ? 24 : 0)
                    .disabled(!model.remoteCommandsAvailable)
                }
            }
            .id(device.id)
            // A mode change ends any press held on the shared media controls.
            .id(model.remoteControlMode)
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
                model.showKeyboard()
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
