import Foundation

struct RemoteWindowLayout {
    enum Arrangement: Equatable {
        case compact
        case book
        case tabletop
    }

    let controls: CGRect
    let companion: CGRect?
    let arrangement: Arrangement

    var usesTrailingShortcuts: Bool {
        arrangement != .book && controls.width >= 440 && controls.height < 440 && controls.width > controls.height
    }

    init(size: CGSize, division: CGRect?, occlusions: [CGRect] = []) {
        let window = CGRect(origin: .zero, size: size)
        let fold = division?.intersection(window)
        let horizontalFold = division.map { $0.width > $0.height } ?? false
        let spacing: CGFloat = 12
        let remote: CGRect
        let extra: CGRect?
        let arrangement: Arrangement
        if let fold, !fold.isNull, horizontalFold,
           fold.minY >= 120, window.maxY - fold.maxY >= 120 {
            remote = CGRect(x: 0, y: fold.maxY + spacing / 2,
                            width: size.width, height: size.height - fold.maxY - spacing / 2)
            extra = CGRect(x: 0, y: 0, width: size.width, height: fold.minY - spacing / 2)
            arrangement = .tabletop
        } else if let fold, !fold.isNull, !horizontalFold,
                  fold.minX >= 210, window.maxX - fold.maxX >= 210 {
            remote = CGRect(x: 0, y: 0, width: fold.minX - spacing / 2, height: size.height)
            extra = CGRect(x: fold.maxX + spacing / 2, y: 0,
                           width: size.width - fold.maxX - spacing / 2, height: size.height)
            arrangement = .book
        } else if let fold, !fold.isNull {
            // A narrow Split View can include only one usable side of the fold.
            if horizontalFold {
                let topHeight = fold.minY
                let bottomHeight = size.height - fold.maxY
                remote = bottomHeight >= topHeight
                    ? CGRect(x: 0, y: fold.maxY, width: size.width, height: bottomHeight)
                    : CGRect(x: 0, y: 0, width: size.width, height: topHeight)
            } else {
                let leadingWidth = fold.minX
                let trailingWidth = size.width - fold.maxX
                remote = leadingWidth >= trailingWidth
                    ? CGRect(x: 0, y: 0, width: leadingWidth, height: size.height)
                    : CGRect(x: fold.maxX, y: 0, width: trailingWidth, height: size.height)
            }
            extra = nil
            arrangement = .compact
        } else {
            remote = window
            extra = nil
            arrangement = .compact
        }

        controls = Self.avoiding(occlusions, in: remote)
        companion = extra.map { Self.avoiding(occlusions, in: $0) }
        self.arrangement = arrangement
    }

    /// Reserved camera regions can appear while the window keeps the same size.
    /// Leave the largest unobstructed rectangle for each pane.
    private static func avoiding(_ occlusions: [CGRect], in initial: CGRect) -> CGRect {
        occlusions.reduce(initial) { area, occlusion in
            let covered = area.intersection(occlusion)
            guard !covered.isNull, !covered.isEmpty else { return area }
            let candidates = [
                CGRect(x: area.minX, y: area.minY, width: covered.minX - area.minX, height: area.height),
                CGRect(x: covered.maxX, y: area.minY, width: area.maxX - covered.maxX, height: area.height),
                CGRect(x: area.minX, y: area.minY, width: area.width, height: covered.minY - area.minY),
                CGRect(x: area.minX, y: covered.maxY, width: area.width, height: area.maxY - covered.maxY),
            ]
            return candidates.max { $0.width * $0.height < $1.width * $1.height } ?? area
        }
    }
}
