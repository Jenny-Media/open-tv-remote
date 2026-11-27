import SwiftUI

struct RemoteGuide: View {
    let showsCursor: Bool

    var body: some View {
        List {
            guideRow("Switch controls", symbol: RemoteControlMode.standard.symbol,
                     text: "Use the switcher between Back and Home to choose Directional pad, Keyboard, Number pad or Eyes-free.")
            guideRow("Use the joystick", symbol: RemoteControlMode.eyesFree.symbol,
                     text: "Drag from anywhere on the pad to move. Tap for OK or hold in a direction to repeat.")
            if showsCursor {
                guideRow("Use the cursor", symbol: RemoteControlMode.cursor.symbol,
                         text: "Drag to move the pointer and tap to click. Use the strip beside the pad to scroll.")
            }
            guideRow("Open a TV app", symbol: "square.grid.2x2",
                     text: "Open TV Apps and choose an app to launch on your TV.")
        }
        .navigationTitle("How to use the remote")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func guideRow(_ title: String, symbol: String, text: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.accent)
        }
    }
}

struct RemoteGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    let showsCursor: Bool

    var body: some View {
        NavigationStack {
            RemoteGuide(showsCursor: showsCursor)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 320)
        #endif
    }
}
