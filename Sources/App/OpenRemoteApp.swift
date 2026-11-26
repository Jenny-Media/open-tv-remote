import SwiftUI

@main
struct OpenRemoteApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        #if os(macOS)
        .defaultSize(width: 420, height: 900)
        .windowResizability(.contentMinSize)
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        #endif
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            pager
                .jellyfinDestinations()
        }
            .safeAreaInset(edge: .bottom) { JellyfinStatusBar() }
            #if os(iOS)
            .background {
                VolumeButtons(isEnabled: scenePhase == .active && model.current != nil) { model.press($0) }
                    .frame(width: 1, height: 1)
            }
            #endif
            #if os(macOS)
            .frame(minWidth: 380, minHeight: 760)
            #endif
            .sheet(isPresented: $model.showingDevices, onDismiss: model.presentPendingRemoteShortcut) { DevicesSheet() }
            .sheet(isPresented: $model.showingKeyboard, onDismiss: model.presentPendingRemoteShortcut) { KeyboardSheet() }
            .sheet(isPresented: $model.showingApps, onDismiss: model.presentPendingRemoteShortcut) { AppsSheet() }
            #if os(iOS)
            .sheet(isPresented: $model.showingSettings, onDismiss: model.presentPendingRemoteShortcut) { SettingsView() }
            .onOpenURL { model.handleRemoteShortcut($0) }
            #endif
            .sheet(isPresented: pairingPresented) { PairingSheet() }
            .animation(.snappy, value: model.state)
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active: model.sceneDidBecomeActive()
                case .background: model.sceneDidEnterBackground()
                default: break
                }
            }
            .task {
                if scenePhase == .active { model.sceneDidBecomeActive() }
                if model.devices.isEmpty { model.showingDevices = true }
            }
    }

    @ViewBuilder
    private var pager: some View {
        #if os(iOS) && compiler(>=6.4) && !IPHONE_SDK_27_0
        if #available(iOS 27.1, *) {
            DuoPager()
        } else {
            Pager().toolbar(.hidden)
        }
        #else
        Pager().toolbar(.hidden)
        #endif
    }

    private var pairingPresented: Binding<Bool> {
        Binding {
            if case .pairing = model.state { return true }
            return false
        } set: { presented in
            if !presented, case .pairing = model.state { model.cancelPairing() }
        }
    }
}

#if os(iOS) && compiler(>=6.4) && !IPHONE_SDK_27_0
@available(iOS 27.1, *)
private struct DuoPager: View {
    @Environment(\.toolbarVerticalEdge) private var toolbarEdge

    var body: some View {
        Pager(usesSystemToolbar: toolbarEdge != nil)
    }
}
#endif

/// The remote and the Watch page side by side; swipe (or use the switcher) to move between them.
private struct Pager: View {
    @Environment(AppModel.self) private var model
    @AppStorage("page") private var stored = 0
    @State private var page: Int? = 0
    var usesSystemToolbar = false

    private var showsRemoteToolbar: Bool { usesSystemToolbar && (page ?? 0) == 0 }

    var body: some View {
        Group {
            if model.remoteControlMode.isGestureMode && (page ?? 0) == 0 {
                RemoteScreen(usesSystemToolbar: usesSystemToolbar)
            } else {
                pages
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !model.remoteControlMode.isGestureMode || (page ?? 0) != 0 {
                PageSwitcher(page: Binding { page ?? 0 } set: { new in withAnimation(.snappy) { page = new } })
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .onAppear { page = stored }
        .onChange(of: page) { _, new in if let new { stored = new } }
        .onChange(of: stored) { _, new in if page != new { page = new } }
        #if os(iOS) && compiler(>=6.4) && !IPHONE_SDK_27_0
        .modifier(DuoRemoteToolbar(isVisible: showsRemoteToolbar))
        #endif
    }

    private var pages: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                RemoteScreen(usesSystemToolbar: usesSystemToolbar)
                    .containerRelativeFrame(.horizontal)
                    .id(0)
                WatchScreen()
                    .containerRelativeFrame(.horizontal)
                    .id(1)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page)
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)

    }
}

#if os(iOS) && compiler(>=6.4) && !IPHONE_SDK_27_0
private struct DuoRemoteToolbar: ViewModifier {
    @Environment(AppModel.self) private var model
    let isVisible: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content
                .toolbar {
                    if isVisible {
                        actions
                    }
                }
                .toolbar(isVisible ? .visible : .automatic, for: .navigationBar)
        } else {
            content
        }
    }

    @available(iOS 27.1, *)
    @ToolbarContentBuilder
    private var actions: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Power", systemImage: "power") { model.press(.power) }
                .tint(Theme.power)
                .contextMenu {
                    if model.supports(.powerOff) {
                        Button("Turn off TV", systemImage: "power") { model.press(.powerOff) }
                    }
                }
        }
        .axisBehavior(.verticalPreferred)

        ToolbarItem(placement: .topBarTrailing) {
            Button("Keyboard", systemImage: "keyboard") { model.showingKeyboard = true }
        }

        if model.current != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Button("TV Apps", systemImage: "square.grid.2x2.fill") { model.showingApps = true }
            }
            .visibilityPriority(.low)
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button("Settings", systemImage: "gearshape.fill") { model.showingSettings = true }
        }

        if model.current != nil && model.remoteControlMode.isGestureMode {
            ToolbarItemGroup(placement: .bottomBar) {
                if model.supports(.volumeUp) {
                    Button("Volume up", systemImage: "plus") { model.press(.volumeUp) }
                        .buttonRepeatBehavior(.enabled)
                }
                if model.supports(.volumeDown) {
                    Button("Volume down", systemImage: "minus") { model.press(.volumeDown) }
                        .buttonRepeatBehavior(.enabled)
                }
            }
        }
    }
}
#endif

struct PageSwitcher: View {
    static let height: CGFloat = 44
    @Binding var page: Int

    var body: some View {
        HStack(spacing: 4) {
            tab("Remote", systemImage: "av.remote", index: 0, key: "1")
            tab("Watch", systemImage: "play.rectangle.on.rectangle", index: 1, key: "2")
        }
        .padding(4)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }

    private func tab(_ title: String, systemImage: String, index: Int, key: KeyEquivalent) -> some View {
        Button {
            Haptics.tick()
            page = index
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(page == index ? Color.black : Theme.secondary)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Capsule().fill(page == index ? Theme.accent : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: .command)
        .accessibilityAddTraits(page == index ? .isSelected : [])
    }
}
