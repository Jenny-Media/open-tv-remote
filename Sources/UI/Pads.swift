import SwiftUI

enum PadMode: String, CaseIterable, Identifiable {
    case dpad, keyboard, keypad
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .dpad: "dpad.fill"
        case .keyboard: "keyboard.fill"
        case .keypad: "circle.grid.3x3.fill"
        }
    }

    var title: String {
        switch self {
        case .dpad: "Directional pad"
        case .keyboard: "Keyboard"
        case .keypad: "Number pad"
        }
    }
}

// MARK: - D-pad

struct Wedge: InsettableShape {
    var direction: Angle
    var innerRatio: CGFloat = 0.44
    var gap: Angle = .degrees(2.2)
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let outer = r - insetAmount
        let inner = r * innerRatio + insetAmount
        let start = direction - .degrees(45) + gap
        let end = direction + .degrees(45) - gap
        var p = Path()
        p.addArc(center: c, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        p.addArc(center: c, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> Wedge {
        var w = self
        w.insetAmount += amount
        return w
    }
}

struct DPadView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.cancellableRemoteRepeats) private var cancellableRepeats

    private let directions: [(key: RemoteKey, angle: Double, symbol: String)] = [
        (.right, 0, "chevron.right"),
        (.down, 90, "chevron.down"),
        (.left, 180, "chevron.left"),
        (.up, 270, "chevron.up"),
    ]

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = size / 2
            let iconDistance = radius * (1 + 0.44) / 2
            ZStack {
                Circle()
                    .fill(Theme.well)
                    .overlay(Circle().strokeBorder(.white.opacity(0.04), lineWidth: 1))
                    .padding(-6)

                ForEach(directions, id: \.angle) { d in
                    KeyCap(shape: Wedge(direction: .degrees(d.angle)), repeats: true,
                           accessibilityLabel: d.key.accessibilityName,
                           repeatAction: model.repeatAction(for: d.key, enabled: cancellableRepeats)) {
                        model.press(d.key)
                    } label: {
                        Image(systemName: d.symbol)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.secondary)
                            .offset(x: cos(d.angle * .pi / 180) * iconDistance,
                                    y: sin(d.angle * .pi / 180) * iconDistance)
                    }
                }

                KeyCap(shape: Circle(), accessibilityLabel: "OK") {
                    model.press(.select)
                } label: {
                    Text("OK").font(.system(size: 22, weight: .bold, design: .rounded))
                }
                .frame(width: size * 0.40, height: size * 0.40)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Keyboard

struct KeyboardPadView: View {
    @Environment(\.cancellableRemoteRepeats) private var cancellableRepeats
    @Environment(AppModel.self) private var model
    @State private var shifted = false
    @State private var symbols = false

    // The last row of each layer sits between shift (or a spacer) and delete.
    private static let letters = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
    ] + ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map { $0.map(String.init) }
    private static let others = [
        ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
        ["_", "\\", "|", "~", "<", ">", "€", "£", "•"],
        [".", ",", "?", "!", "'", "`", "¥"],
    ]
    private let gap: CGFloat = 6

    var body: some View {
        VStack(spacing: 10) {
            controls
            GeometryReader { geo in
                let rows = symbols ? Self.others : Self.letters
                let keyWidth = (geo.size.width - gap * 9) / 10
                if cancellableRepeats && keyWidth < 24 {
                    narrowKeys(rows)
                } else {
                    fullKeys(rows, width: keyWidth)
                }
            }
        }
        #if DEBUG
        .frame(maxWidth: DemoMode.keyboardTestWidth ?? .infinity)
        #endif
    }

    private func fullKeys(_ rows: [[String]], width: CGFloat) -> some View {
        // Shift and Delete fill the space left by the shorter letter row.
        let wide = width * 1.5 + gap / 2
        return VStack(spacing: gap) {
            ForEach(0..<3) { i in
                HStack(spacing: gap) { characters(rows[i], width: width) }
            }
            HStack(spacing: gap) {
                if symbols { Color.clear.frame(width: wide) }
                else { shiftButton.frame(width: wide) }
                characters(rows[3], width: width)
                deleteButton.frame(width: wide)
            }
            HStack(spacing: gap) {
                symbolsButton.frame(width: wide)
                spaceButton
            }
        }
        .frame(maxHeight: 5 * 64 + 4 * gap)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func narrowKeys(_ rows: [[String]]) -> some View {
        let keys = symbols ? rows.flatMap { $0 } : rows.dropFirst().flatMap { $0 } + rows[0]
        let columns = [GridItem(.adaptive(minimum: 44), spacing: gap)]
        return VStack(spacing: gap) {
            HStack(spacing: gap) {
                symbolsButton
                if !symbols { shiftButton }
                spaceButton
            }
            .frame(height: 44)
            ScrollView {
                LazyVGrid(columns: columns, spacing: gap) {
                    ForEach(keys, id: \.self) { key in
                        let text = shifted && !symbols ? key.uppercased() : key
                        Button {
                            Haptics.tap()
                            typeCharacter(text)
                        } label: {
                            Text(text)
                                .font(.system(size: 19, weight: .medium, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(KeySurface(shape: keyShape))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// A small D-pad for moving through results, with clear, delete and Return beside it.
    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) {
                clearButton
                    .frame(minWidth: 44)
                    .frame(height: 52)
                    .frame(maxWidth: .infinity, maxHeight: 114, alignment: .top)
                DPadView().frame(width: 150, height: 150)
                VStack(spacing: 10) {
                    deleteButton.frame(height: 52)
                    returnButton.frame(height: 52)
                }
                .frame(minWidth: 44, maxWidth: .infinity)
            }
            .frame(height: 150)

            VStack(spacing: 8) {
                DPadView().frame(width: 108, height: 108)
                HStack(spacing: 6) {
                    clearButton
                    deleteButton
                    returnButton
                }
                .frame(height: 44)
            }
        }
    }

    private var clearButton: some View {
        KeyCap(shape: keyShape, accessibilityLabel: "Clear") { model.typeClear() } label: {
            Text("Clear").font(.system(size: 15, weight: .semibold, design: .rounded))
        }
    }

    private var deleteButton: some View {
        let deviceID = model.currentID
        let repeatDelete: ((RemoteInputRequest) async -> Void)? = cancellableRepeats ? { request in
            guard request.canDispatch, model.currentID == deviceID else {
                request.cancel()
                return
            }
            await model.repeatTypeDelete(request: request)
        } : nil
        return KeyCap(shape: keyShape, repeats: true, accessibilityLabel: "Delete", repeatAction: repeatDelete) {
            model.typeDelete()
        } label: {
            Image(systemName: "delete.left").font(.system(size: 16, weight: .semibold))
        }
    }

    private var returnButton: some View {
        KeyCap(shape: keyShape, accessibilityLabel: "Return") { model.typeReturn() } label: {
            Image(systemName: "return").font(.system(size: 16, weight: .semibold))
        }
    }

    private var keyShape: RoundedRectangle { RoundedRectangle(cornerRadius: 8, style: .continuous) }

    private func characters(_ row: [String], width: CGFloat) -> some View {
        ForEach(row, id: \.self) { c in
            let text = shifted && !symbols ? c.uppercased() : c
            KeyCap(shape: keyShape, accessibilityLabel: text) {
                typeCharacter(text)
            } label: {
                Text(text).font(.system(size: 19, weight: .medium, design: .rounded))
            }
            .frame(width: width)
        }
    }

    private func typeCharacter(_ text: String) {
        model.type(text)
        shifted = false
    }

    private var shiftButton: some View {
        KeyCap(shape: keyShape, accessibilityLabel: "Shift") { shifted.toggle() } label: {
            Image(systemName: shifted ? "shift.fill" : "shift").font(.system(size: 16, weight: .semibold))
        }
    }

    private var symbolsButton: some View {
        KeyCap(shape: keyShape, accessibilityLabel: symbols ? "Letters" : "Numbers and symbols") {
            symbols.toggle()
        } label: {
            Text(symbols ? "ABC" : "123").font(.system(size: 15, weight: .semibold, design: .rounded))
        }
    }

    private var spaceButton: some View {
        KeyCap(shape: keyShape, accessibilityLabel: "Space") { model.type(" ") } label: {
            Text("space").font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(Theme.secondary)
        }
    }
}

// MARK: - Keypad

struct KeypadView: View {
    @Environment(\.cancellableRemoteRepeats) private var cancellableRepeats
    @Environment(AppModel.self) private var model

    var body: some View {
        // Rows stretch to fill whatever height the pad gets.
        Grid(horizontalSpacing: 12, verticalSpacing: 10) {
            ForEach(0..<3) { row in
                GridRow {
                    ForEach(1...3, id: \.self) { col in digit(row * 3 + col) }
                }
            }
            GridRow {
                KeyCap(accessibilityLabel: "Back") { model.press(.back) } label: {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 18, weight: .semibold))
                }
                digit(0)
                KeyCap(repeats: true, enabled: model.supports(.backspace), accessibilityLabel: "Delete",
                       repeatAction: model.repeatAction(for: .backspace, enabled: cancellableRepeats)) {
                    model.press(.backspace)
                } label: {
                    Image(systemName: "delete.left").font(.system(size: 18, weight: .semibold))
                }
            }
        }
    }

    private func digit(_ n: Int) -> some View {
        KeyCap(enabled: model.supports(.digit(n)), accessibilityLabel: "\(n)") { model.press(.digit(n)) } label: {
            Text("\(n)").font(.system(size: 24, weight: .semibold, design: .rounded))
        }
    }
}
