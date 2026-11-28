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
                    KeyCap(shape: Wedge(direction: .degrees(d.angle)), accessibilityLabel: d.key.accessibilityName,
                           repeatAction: model.repeatAction(for: d.key)) {
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
    enum PhoneLayout: Equatable {
        case adaptive, portrait, foldedPortrait, wideLandscape
    }

    enum Layout {
        case stacked
        case phone(PhoneLayout)
        case phoneKeys
        case stackedTablet(controlsSpacing: CGFloat)
        case tabletKeys
    }

    private static let defaultKeyGap: CGFloat = 6
    private static let maximumKeyHeight: CGFloat = 64
    private static let phoneClearHeight: CGFloat = 48
    private static let foldedNavigationSideInset: CGFloat = 72
    static let minimumPhoneKeyGridHeight: CGFloat = 4 * 44 + 3 * defaultKeyGap
    static let minimumTabletKeyGridWidth: CGFloat = 10 * 44 + 9 * defaultKeyGap

    private enum Layer { case letters, numbers, symbols }

    @Environment(\.adaptiveKeyboardLayout) private var adaptiveKeyboardLayout
    @Environment(AppModel.self) private var model
    @State private var shifted = false
    @State private var layer: Layer = .letters
    var layout: Layout = .stacked

    private static let digits = "1234567890".map(String.init)
    private static let letters = ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map { $0.map(String.init) }
    private static let legacySymbols = [
        ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
        ["_", "\\", "|", "~", "<", ">", "€", "£", "•"],
        [".", ",", "?", "!", "'", "`", "¥"],
    ]
    private static let punctuation = [".", ",", "?", "!", "'"]
    private static let numbers = [digits, legacySymbols[0], punctuation]
    private static let symbols = [legacySymbols[1], legacySymbols[2] + ["¥"], punctuation + ["`"]]
    private let gap = KeyboardPadView.defaultKeyGap

    var body: some View {
        Group {
            switch layout {
            case .stacked:
                VStack(spacing: 10) {
                    controls
                    keyGrid(tablet: false, inlineEditing: false)
                }
            case .phone(let posture):
                phoneKeyboard(posture)
            case .phoneKeys:
                keyGrid(tablet: false)
            case .stackedTablet(let controlsSpacing):
                VStack(spacing: controlsSpacing) {
                    TabletKeyboardNavigation()
                    keyGrid(tablet: true)
                }
            case .tabletKeys:
                keyGrid(tablet: true)
            }
        }
        #if DEBUG
        .frame(maxWidth: DemoMode.keyboardTestWidth ?? .infinity)
        #endif
    }

    private func phoneKeyboard(_ posture: PhoneLayout) -> some View {
        GeometryReader { viewport in
            let width = viewport.size.width
            let height = viewport.size.height
            let sideBySide = posture == .adaptive && width >= 480 && height < 360
            let padSize = sideBySide ? min(108, max(64, height - Self.phoneClearHeight - 8))
                                     : min(132, max(60, width - 72))
            let stackedNavigation = posture == .portrait ||
                (posture == .foldedPortrait && width < padSize + 2 * Self.foldedNavigationSideInset)
            let minimumHeight = sideBySide
                ? max(Self.minimumPhoneKeyGridHeight, padSize + 8 + Self.phoneClearHeight)
                : padSize + (stackedNavigation ? 10 + Self.phoneClearHeight : 0)
                    + (posture == .portrait ? 22 : 10) + Self.minimumPhoneKeyGridHeight
            if height < minimumHeight {
                shortPhoneKeyboard(height: height)
            } else {
                phoneKeyboardContent(posture, sideBySide: sideBySide, padSize: padSize)
            }
        }
        .clipped()
    }

    private func shortPhoneKeyboard(height: CGFloat) -> some View {
        let padSize = min(108, max(64, height))
        let typing = KeyboardSheetButton().accessibilityIdentifier("phoneKeyboardSheet")
        return ViewThatFits {
            HStack(spacing: 12) {
                DPadView().frame(width: padSize, height: padSize)
                phoneClearButton
                typing
            }
            // Fit height at the proposed width so the typing label can wrap.
            ViewThatFits(in: .vertical) {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        DPadView().frame(width: 88, height: 88)
                        phoneClearButton
                    }
                    typing
                }
                typing
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func phoneKeyboardContent(_ posture: PhoneLayout, sideBySide: Bool, padSize: CGFloat) -> some View {
        if sideBySide {
            HStack(spacing: 12) {
                VStack(spacing: 8) {
                    DPadView().frame(width: padSize, height: padSize)
                    phoneClearButton
                }
                keyGrid(tablet: false)
            }
        } else {
            let isPortrait = posture == .portrait
            VStack(spacing: isPortrait ? 22 : 10) {
                phoneKeyboardNavigation(posture, padSize: padSize)
                keyGrid(tablet: false)
                    .frame(maxHeight: isPortrait ? 4 * Self.maximumKeyHeight + 3 * gap : .infinity)
            }
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder private func phoneKeyboardNavigation(_ posture: PhoneLayout, padSize: CGFloat) -> some View {
        let pad = DPadView().frame(width: padSize, height: padSize)
        switch posture {
        case .portrait:
            VStack(spacing: 10) {
                pad
                phoneClearButton
            }
        case .foldedPortrait:
            ViewThatFits(in: .horizontal) {
                pad.padding(.horizontal, Self.foldedNavigationSideInset)
                    .overlay(alignment: .trailing) { phoneClearButton }
                VStack(spacing: 10) {
                    pad
                    phoneClearButton
                }
            }
        case .adaptive, .wideLandscape:
            HStack(spacing: 12) {
                pad
                phoneClearButton
            }
        }
    }

    private var phoneClearButton: some View {
        KeyboardClearButton().frame(width: 60, height: Self.phoneClearHeight)
    }

    private func rows(numberRow: Bool, inlineEditing: Bool = true) -> [[String]] {
        switch layer {
        case .letters: numberRow ? [Self.digits] + Self.letters : Self.letters
        case .numbers: inlineEditing ? Self.numbers : Self.legacySymbols
        case .symbols: Self.symbols
        }
    }

    private func keyGrid(tablet: Bool, inlineEditing: Bool = true) -> some View {
        GeometryReader { geo in
            let showsNumberRow = !inlineEditing || (tablet && geo.size.width >= Self.minimumTabletKeyGridWidth)
            let rows = self.rows(numberRow: showsNumberRow, inlineEditing: inlineEditing)
            // Use any extra width for spacing once all ten letter keys have 44-point targets.
            let extraWidth = max(0, geo.size.width - Self.minimumTabletKeyGridWidth)
            let keyGap = tablet ? min(9, gap + extraWidth / 9) : gap
            let keyWidth = (geo.size.width - keyGap * 9) / 10
            if inlineEditing && adaptiveKeyboardLayout && keyWidth < (tablet ? 28 : 24) {
                narrowKeys(rows)
            } else {
                fullKeys(rows, width: keyWidth, gap: keyGap, inlineEditing: inlineEditing)
            }
        }
    }

    private func fullKeys(_ rows: [[String]], width: CGFloat, gap: CGFloat, inlineEditing: Bool) -> some View {
        let wide = width * 1.5 + gap / 2
        let editingWidth = inlineEditing ? max(44, wide) : wide
        return VStack(spacing: gap) {
            ForEach(0..<(rows.count - 1), id: \.self) { i in
                HStack(spacing: gap) { characters(rows[i], width: width) }
            }
            HStack(spacing: gap) {
                layerModifier(inlineEditing: inlineEditing).frame(width: editingWidth)
                let lastRow = rows[rows.count - 1]
                let innerWidth = (10 * width + 9 * gap - 2 * editingWidth - 2 * gap - CGFloat(lastRow.count - 1) * gap)
                    / CGFloat(lastRow.count)
                HStack(spacing: gap) {
                    characters(lastRow, width: min(width, innerWidth))
                }
                .frame(maxWidth: .infinity)
                deleteButton.frame(width: editingWidth)
            }
            HStack(spacing: gap) {
                symbolsButton.frame(width: editingWidth)
                spaceButton
                if inlineEditing { returnButton.frame(width: editingWidth) }
            }
        }
        .frame(maxHeight: CGFloat(rows.count + 1) * Self.maximumKeyHeight + CGFloat(rows.count) * gap)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func narrowKeys(_ rows: [[String]]) -> some View {
        VStack(spacing: gap) {
            ScrollView { narrowKeyGrid(rows.flatMap { $0 }) }
            HStack(spacing: gap) {
                layerModifier(inlineEditing: true).frame(width: 44, height: 44)
                Spacer(minLength: 0)
                deleteButton.frame(width: 44, height: 44)
            }
            HStack(spacing: gap) {
                symbolsButton.frame(width: 44)
                spaceButton
                returnButton.frame(width: 44)
            }
            .frame(height: 44)
        }
    }

    private func narrowKeyGrid(_ keys: [String]) -> some View {
        let columns = [GridItem(.adaptive(minimum: 44), spacing: gap)]
        return LazyVGrid(columns: columns, spacing: gap) {
            ForEach(keys, id: \.self) { key in
                let text = shifted && layer == .letters ? key.uppercased() : key
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

    /// A small D-pad for moving through results, with clear, delete and Return beside it.
    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) {
                KeyboardClearButton()
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
                    KeyboardClearButton()
                    deleteButton
                    returnButton
                }
                .frame(height: 44)
            }
        }
    }

    private var deleteButton: some View {
        let deviceID = model.currentID
        let repeatDelete: (RemoteInputRequest) async -> Void = { request in
            guard request.canDispatch, model.currentID == deviceID else {
                request.cancel()
                return
            }
            await model.repeatTypeDelete(request: request)
        }
        return KeyCap(shape: keyShape, enabled: model.typesLive ? model.canSendTVDelete : !model.typed.isEmpty,
                      accessibilityLabel: "Delete", repeatAction: repeatDelete,
                      repeatRequiresCurrentConnection: model.typesLive) {
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
            let text = shifted && layer == .letters ? c.uppercased() : c
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
        KeyCap(shape: keyShape, accessibilityLabel: layer == .letters ? "Numbers and symbols" : "Letters") {
            layer = layer == .letters ? .numbers : .letters
        } label: {
            Text(layer == .letters ? "123" : "ABC").font(.system(size: 15, weight: .semibold, design: .rounded))
        }
    }

    @ViewBuilder private func layerModifier(inlineEditing: Bool) -> some View {
        if layer == .letters {
            shiftButton
        } else if inlineEditing {
            KeyCap(shape: keyShape, accessibilityLabel: layer == .numbers ? "More symbols" : "Numbers and punctuation") {
                layer = layer == .numbers ? .symbols : .numbers
            } label: {
                Text(layer == .numbers ? "#+=" : "123").font(.system(size: 15, weight: .semibold, design: .rounded))
            }
        } else {
            Color.clear
        }
    }

    private var spaceButton: some View {
        KeyCap(shape: keyShape, accessibilityLabel: "Space") { model.type(" ") } label: {
            Text("space").font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(Theme.secondary)
        }
    }
}

struct KeyboardClearButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        KeyCap(shape: RoundedRectangle(cornerRadius: 8, style: .continuous), accessibilityLabel: "Clear") {
            model.typeClear()
        } label: {
            Text("Clear").font(.system(size: 15, weight: .semibold, design: .rounded))
        }
    }
}

struct TabletKeyboardNavigation: View {
    private static let padSize: CGFloat = 150
    private static let spacing: CGFloat = 10
    private static let clearHeight: CGFloat = 48
    static let height = padSize + spacing + clearHeight

    var body: some View {
        VStack(spacing: Self.spacing) {
            DPadView().frame(width: Self.padSize, height: Self.padSize)
            KeyboardClearButton().frame(width: 64, height: Self.clearHeight)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Keypad

struct KeypadView: View {
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
                KeyCap(enabled: model.canSendTVDelete, accessibilityLabel: "Delete",
                       repeatAction: model.repeatAction(for: .backspace)) {
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
