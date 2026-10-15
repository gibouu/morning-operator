import SwiftUI

/// Existing callers keep their six cases; morning adds the dotted sunrise home mark.
enum MorningDockSymbol: Sendable, CaseIterable {
    case morning, play, pause, review, learn, history, settings
}

/// An app-owned dotted family. The parent button supplies the name and selected state.
struct MorningDockGlyph: View {
    let symbol: MorningDockSymbol

    var body: some View {
        MorningDottedIcon(systemName: name)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private var name: String {
        switch symbol {
        case .morning: "sunrise"
        case .play: "play.fill"
        case .pause: "pause.fill"
        case .review: "list.bullet"
        case .learn: "eye"
        case .history: "clock.arrow.circlepath"
        case .settings: "slider.horizontal.3"
        }
    }
}

/// A familiar call-site vocabulary rendered entirely as circles. Known system-name
/// strings select original dot patterns; there is no SF Symbol or stroke fallback.
/// Typical control size is 24–28 pt. The containing button still needs a 44 pt target.
struct MorningDottedIcon: View {
    let systemName: String
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        MorningDottedIconShape(pattern: pattern, strong: contrast == .increased)
            .fill(.foreground)
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }

    private var pattern: [String] {
        switch systemName {
        case "play", "play.fill":
            ["..x......", "..xx.....", "..xxx....", "..xxxx...", "..xxxxx..", "..xxxx...", "..xxx....", "..xx.....", "..x......"]
        case "pause", "pause.fill":
            [".........", "..x...x..", "..x...x..", "..x...x..", "..x...x..", "..x...x..", "..x...x..", "..x...x..", "........."]
        case "stop", "stop.fill":
            [".........", ".xxxxxxx.", ".xxxxxxx.", ".xxxxxxx.", ".xxxxxxx.", ".xxxxxxx.", ".xxxxxxx.", ".xxxxxxx.", "........."]
        case "checkmark", "checkmark.circle", "checkmark.circle.fill":
            ["..xxxxx..", ".x.....x.", "x......xx", "x.....x.x", "x.x..x..x", "x..xx...x", "x.......x", ".x.....x.", "..xxxxx.."]
        case "sunrise", "sunrise.fill", "sun.horizon", "sun.horizon.fill", "sun.max", "sun.max.fill":
            ["....x....", ".x..x..x.", "..xxxxx..", ".xxxxxxx.", ".xxxxxxx.", ".xxxxxxx.", "xxxxxxxxx", ".........", "..xxxxx.."]
        case "record.circle", "record.circle.fill":
            ["..xxxxx..", ".x.....x.", "x.......x", "x..xxx..x", "x..xxx..x", "x..xxx..x", "x.......x", ".x.....x.", "..xxxxx.."]
        case "eye", "eye.fill", "viewfinder":
            [".........", "...xxx...", "..x...x..", ".x..x..x.", "x..xxx..x", ".x..x..x.", "..x...x..", "...xxx...", "........."]
        case "calendar":
            ["..x...x..", ".xxxxxxx.", ".xx...xx.", ".xxxxxxx.", ".x.....x.", ".x.x.x.x.", ".x.....x.", ".x.x.x.x.", ".xxxxxxx."]
        case "list.bullet", "list.bullet.clipboard":
            [".........", ".x..xxxx.", ".........", ".........", ".x..xxxx.", ".........", ".........", ".x..xxxx.", "........."]
        case "arrow.clockwise", "clock.arrow.circlepath":
            ["..xxxxx..", ".x.....x.", "x......xx", "x.....xxx", "x........", "x........", "x.......x", ".x.....x.", "..xxxxx.."]
        case "info.circle", "info.circle.fill", "exclamationmark.circle":
            ["..xxxxx..", ".x.....x.", "x...x...x", "x.......x", "x..xx...x", "x...x...x", "x..xxx..x", ".x.....x.", "..xxxxx.."]
        case "newspaper", "newspaper.fill", "doc.text":
            [".xxxxxxx.", ".x.....x.", ".x.xxx.x.", ".x.....x.", ".x.x.x.x.", ".x.x.x.x.", ".x.....x.", ".x.xxx.x.", ".xxxxxxx."]
        case "globe", "network":
            ["..xxxxx..", ".x.x.x.x.", "x..x.x..x", "x..x.x..x", "xxxxxxxxx", "x..x.x..x", "x..x.x..x", ".x.x.x.x.", "..xxxxx.."]
        case "clock", "clock.fill":
            ["..xxxxx..", ".x.....x.", "x...x...x", "x...x...x", "x...xxx.x", "x.......x", "x.......x", ".x.....x.", "..xxxxx.."]
        case "alarm", "alarm.fill":
            [".xx...xx.", "x..xxx..x", "..x...x..", ".x..x..x.", ".x..xxx..", ".x.....x.", "..x...x..", "...xxx...", "..x...x.."]
        case "timer", "stopwatch", "stopwatch.fill":
            ["...xxx...", "....x..x.", "..xxxxx..", ".x.....x.", "x...x...x", "x...x...x", "x...xxx.x", ".x.....x.", "..xxxxx.."]
        case "slider.horizontal.3", "gearshape", "gearshape.fill":
            [".........", ".....x...", ".xxxx.xxx", ".....x...", "..x......", ".x.xxxxx.", "..x......", ".....x...", ".xxxx.xxx"]
        case "arrow.right", "chevron.right", "forward.end", "forward.end.fill":
            [".........", "....x....", ".....x...", "......x..", ".xxxxxxx.", "......x..", ".....x...", "....x....", "........."]
        case "arrow.left", "chevron.left":
            [".........", "....x....", "...x.....", "..x......", ".xxxxxxx.", "..x......", "...x.....", "....x....", "........."]
        case "plus", "plus.circle", "plus.circle.fill":
            [".........", "....x....", "....x....", "....x....", ".xxxxxxx.", "....x....", "....x....", "....x....", "........."]
        case "circle.fill":
            [".........", "...xxx...", "..xxxxx..", ".xxxxxxx.", ".xxxxxxx.", ".xxxxxxx.", "..xxxxx..", "...xxx...", "........."]
        case "circle":
            [".........", "...xxx...", "..x...x..", ".x.....x.", ".x.....x.", ".x.....x.", "..x...x..", "...xxx...", "........."]
        case "xmark", "xmark.circle", "xmark.circle.fill":
            [".........", ".x.....x.", "..x...x..", "...x.x...", "....x....", "...x.x...", "..x...x..", ".x.....x.", "........."]
        case "ellipsis", "ellipsis.circle":
            [".........", ".........", ".........", ".........", ".x..x..x.", ".........", ".........", ".........", "........."]
        case "mic", "mic.fill", "waveform":
            ["...xxx...", "...x.x...", "...x.x...", "...x.x...", ".x.xxx.x.", ".x.....x.", "..xxxxx..", "....x....", "..xxxxx.."]
        case "speaker.wave.2", "speaker.wave.2.fill":
            [".........", "....x..x.", "...xx...x", ".xxxx.x.x", ".xxxx.x.x", ".xxxx.x.x", "...xx...x", "....x..x.", "........."]
        case "bubble.left.and.bubble.right.fill", "message", "message.fill", "bubble.left":
            [".xxxxxx..", "x......x.", "x......x.", "x......x.", "x......x.", ".xxx.xxx.", "...x.x...", "...xx....", "........."]
        case "envelope", "envelope.fill", "envelope.badge", "mail":
            [".........", ".xxxxxxx.", ".xx...xx.", ".x.x.x.x.", ".x..x..x.", ".x.....x.", ".x.....x.", ".xxxxxxx.", "........."]
        case "leaf", "leaf.fill", "heart", "heart.fill":
            [".........", "..xx.xx..", ".x..x..x.", ".x.....x.", "..x...x..", "...x.x...", "....x....", ".........", "........."]
        case "moon", "moon.fill", "moon.stars", "moon.stars.fill":
            ["...xxxx..", "..xx.....", ".xx......", ".xx......", ".xx......", ".xxx.....", "..xxxx.xx", "...xxxxx.", "........."]
        case "arrow.up", "arrow.up.circle":
            ["....x....", "...xxx...", "..x.x.x..", ".x..x..x.", "....x....", "....x....", "....x....", "....x....", "........."]
        case "lock.shield", "lock.shield.fill", "lock", "lock.fill":
            ["...xxx...", "..x...x..", "..x...x..", ".xxxxxxx.", ".x.....x.", ".x..x..x.", ".x..x..x.", ".x.....x.", ".xxxxxxx."]
        case "platter.filled.top.iphone", "iphone", "iphone.gen3":
            ["..xxxxx..", "..x...x..", "..xxxxx..", "..x...x..", "..x...x..", "..x...x..", "..x...x..", "..x.x.x..", "..xxxxx.."]
        case "rectangle.on.rectangle", "rectangle.on.rectangle.angled":
            ["..xxxxxx.", "..x....x.", "xxxxxxxx.", "x.....xx.", "x.....xx.", "x.....xx.", "x.....xx.", "x.....x..", "xxxxxxx.."]
        case "chevron.down":
            [".........", ".........", ".x.....x.", "..x...x..", "...x.x...", "....x....", ".........", ".........", "........."]
        case "chevron.up":
            [".........", ".........", "....x....", "...x.x...", "..x...x..", ".x.....x.", ".........", ".........", "........."]
        case "arrow.down", "arrow.down.circle":
            [".........", "....x....", "....x....", "....x....", "....x....", ".x..x..x.", "..x.x.x..", "...xxx...", "....x...."]
        case "square.and.pencil", "pencil", "pencil.and.outline":
            [".......x.", "......xxx", ".....xxx.", "....xxx..", "...xxx...", "..xxx....", ".xxx.....", ".xx......", "........."]
        default:
            // A distinct cluster is preferable to quietly reintroducing a stroke icon.
            ["....x....", "....x....", "..x.x.x..", "...xxx...", "xxxxxxxxx", "...xxx...", "..x.x.x..", "....x....", "....x...."]
        }
    }
}

private struct MorningDottedIconShape: Shape {
    let pattern: [String]
    let strong: Bool

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let cell = side / 10
        let radius = cell * (strong ? 0.40 : 0.34)
        var path = Path()
        for (row, line) in pattern.enumerated() {
            for (column, value) in line.enumerated() where value == "x" {
                let x = rect.midX + (CGFloat(column) - 4) * cell
                let y = rect.midY + (CGFloat(row) - 4) * cell
                path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
            }
        }
        return path
    }
}
