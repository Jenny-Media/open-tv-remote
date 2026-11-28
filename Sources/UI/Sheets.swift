import SwiftUI

// MARK: - Pairing

struct PairingSheet: View {
    @Environment(AppModel.self) private var model
    @State private var code = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                    Capsule().fill(.white.opacity(0.15)).frame(width: 40, height: 5).padding(.top, 10)
                    switch model.state {
                    case .pairing(.enterCode(let length, _)):
                        enterCode(length: length)
                    case .pairing(.verifying):
                        waiting(title: "Checking the code…", message: " ")
                    case .pairing(.acceptOnTV):
                        waiting(title: "Check your TV",
                                message: "Use your TV remote to approve the pairing request on the TV screen.")
                    default:
                        waiting(title: "Talking to your TV…", message: " ")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            #if os(iOS)
            .scrollDismissesKeyboard(.never)
            #endif

            if let pairingError {
                Text(pairingError)
                    .font(.footnote)
                    .foregroundStyle(Theme.power)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button {
                model.cancelPairing()
            } label: {
                Text("Cancel")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .interactiveDismissDisabled()
        #if os(macOS)
        .frame(width: 400, height: 380)
        #endif
    }

    private var pairingError: String? {
        guard case .pairing(.enterCode(_, let error)) = model.state else { return nil }
        return error
    }

    private func enterCode(length: Int) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "tv.badge.wifi").font(.system(size: 34, weight: .semibold)).foregroundStyle(Theme.accent)
            Text("Enter the code on your TV").font(.system(size: 22, weight: .bold, design: .rounded))
            ZStack {
                TextField("", text: $code)
                    .focused($fieldFocused)
                    .accessibilityLabel("Pairing code")
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.characters)
                    .keyboardType(.asciiCapable)
                    #endif
                    .opacity(0.02)
                    .onChange(of: code) { _, new in
                        let cleaned = String(new.uppercased().filter(\.isHexDigit).prefix(length))
                        if cleaned != new {
                            code = cleaned
                            return
                        }
                        if cleaned.count == length { model.submitPairingCode(cleaned) }
                    }
                HStack(spacing: 8) {
                    ForEach(0..<length, id: \.self) { i in
                        let chars = Array(code)
                        Text(i < chars.count ? String(chars[i]) : "")
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .frame(width: 44, height: 56)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.well))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(i == chars.count ? Theme.accent : .white.opacity(0.08), lineWidth: i == chars.count ? 2 : 1))
                    }
                }
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture { fieldFocused = true }
            if pairingError == nil {
                Text("Codes use the numbers 0–9 and the letters A–F.").font(.footnote).foregroundStyle(Theme.secondary)
            }
        }
        .onAppear {
            code = ""
            fieldFocused = true
        }
        .onChange(of: pairingError) { _, _ in code = "" }
    }

    private func waiting(title: String, message: String) -> some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large).padding(.bottom, 6)
            Text(title).font(.system(size: 22, weight: .bold, design: .rounded))
            Text(message).font(.subheadline).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }
}

// MARK: - Keyboard

struct KeyboardSheetButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            Haptics.tap()
            model.showKeyboard(continuingPadEditing: true)
        } label: {
            Label("Type on your TV", systemImage: "keyboard")
                .font(.headline)
                .frame(minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .foregroundStyle(.black)
    }
}

struct KeyboardSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var text = ""
    @State private var sendFailed = false
    @FocusState private var focused: Bool
    var continuesPadEditing = false

    private var usesPadDraft: Bool { continuesPadEditing && !model.typesLive }
    private var tracksLiveText: Bool { continuesPadEditing && model.typesLive }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Type on your TV").font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.plain).foregroundStyle(Theme.accent).fontWeight(.semibold)
            }
            if continuesPadEditing {
                ScrollView { fields }
                    .scrollBounceBehavior(.basedOnSize)
            } else {
                fields
                Spacer(minLength: 0)
            }
        }
        .padding(20)
        .background(Theme.background.ignoresSafeArea())
        .onAppear { focused = true }
        #if os(iOS)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize && continuesPadEditing
                             ? [.large] : [.height(tracksLiveText ? 260 : 210)])
        .presentationCompactAdaptation(continuesPadEditing ? .fullScreenCover : .automatic)
        #else
        .frame(width: 400, height: 180)
        #endif
    }

    private var fields: some View {
        @Bindable var model = model
        let deviceID = model.currentID
        return VStack(spacing: 16) {
            HStack(spacing: 10) {
                TextField("Search or type…", text: usesPadDraft ? $model.typed : $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .onSubmit { send(playsFeedback: false) }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.well))
                KeyCap(shape: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous),
                       enabled: usesPadDraft ? !model.typed.isEmpty : model.canSendTVDelete,
                       accessibilityLabel: usesPadDraft ? "Delete draft character" : "Delete on TV",
                       repeatAction: repeatDelete, repeatRequiresCurrentConnection: !usesPadDraft) {
                    if continuesPadEditing { model.typeDelete() }
                    else { model.press(.backspace) }
                } label: {
                    Image(systemName: "delete.left").font(.system(size: 17, weight: .semibold))
                }
                .frame(width: 52, height: 48)
                .environment(\.remoteRepeatIsCurrent, { requiresCurrentConnection in
                    model.showingKeyboard && model.currentID == deviceID &&
                        (!requiresCurrentConnection || !model.isConnectionPaused)
                })
                Button {
                    send(playsFeedback: true)
                } label: {
                    Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(Theme.accent))
                }
                .buttonStyle(PressScaleStyle())
                .disabled((usesPadDraft ? model.typed : text).isEmpty)
                .accessibilityLabel("Send text")
            }
            if tracksLiveText {
                Button("Return on TV", systemImage: "return") {
                    send(playsFeedback: true, returnsOnTV: true)
                }
                .buttonStyle(.bordered)
                .disabled(!model.canReturnOnTV)
            }
            Text(sendFailed ? "Couldn’t send text. Check your TV connection and try again."
                            : "Select a search box on your TV first, then type here.")
                .font(.footnote)
                .foregroundStyle(sendFailed ? Theme.power : Theme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var repeatDelete: (RemoteInputRequest) async -> Void {
        if continuesPadEditing {
            return { request in await model.repeatTypeDelete(request: request, fromKeyboardSheet: true) }
        }
        return model.repeatAction(for: .backspace)
    }

    /// Sends the whole text at once, then gets out of the way so the TV's search can be navigated.
    private func send(playsFeedback: Bool, returnsOnTV: Bool = false) {
        let text = usesPadDraft ? model.typed : self.text
        guard returnsOnTV ? model.canReturnOnTV : !text.isEmpty else { return }
        if playsFeedback { Haptics.tap() }
        if continuesPadEditing {
            if !text.isEmpty, !model.submitKeyboardPadText(text) {
                sendFailed = true
                return
            }
            if returnsOnTV { model.typeReturn() }
        } else {
            model.sendText(text)
        }
        dismiss()
    }
}

// MARK: - Apps

struct AppsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TVAppGrid { dismiss() }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Apps")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await model.refreshApps() }
        }
        #if os(macOS)
        .frame(minWidth: 360, idealWidth: 380, maxWidth: 400, minHeight: 480)
        #endif
    }
}

private struct TVAppGrid: View {
    @Environment(AppModel.self) private var model
    @State private var launchRejected = false
    var onLaunch: () -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                ForEach(model.allApps, id: \.app.id) { entry in
                    AppTile(app: entry.app, style: entry.style, height: 72) {
                        if model.launch(entry.app) {
                            onLaunch()
                        } else {
                            launchRejected = true
                        }
                    }
                }
            }
            .padding(20)
            if model.installedApps == nil {
                Text("Your TV doesn't share its app list, so these are popular apps. Ones that aren't installed won't open.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 20)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if launchRejected {
                Text("Pair with your TV to open apps.")
                    .font(.callout)
                    .foregroundStyle(Theme.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Theme.well)
            }
        }
        .onChange(of: model.currentID) { _, _ in launchRejected = false }
    }
}
