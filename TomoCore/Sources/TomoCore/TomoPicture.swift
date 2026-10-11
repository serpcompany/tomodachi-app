import SwiftUI

// MARK: - A picture that reads on its card (#195)
//
// Words are pictures (emoji): the choices of a picture round, and a word's picture on the Words list, in the garden and
// the diary. On a dark card a dark picture all but disappears (the black bird, 🐦‍⬛), so it gets a soft light disc
// behind it; the picture itself never changes. Which pictures are dark is measured from their own pixels, once each,
// so a new pack's pictures are covered with no list to keep.

@MainActor
public enum TomoPicture {
    /// A picture is dark when more than this share of it would vanish on a dark card.
    static let darkShare = 0.5

    /// The share of a picture, by area, that is too dark to see on a dark card: pixels under 0.05 relative luminance,
    /// which is less than 1.6:1 against the island's tile. 0 to 1; measured once per picture.
    public static func shareTooDark(_ emoji: String) -> Double {
        if let share = measured[emoji] { return share }
        let share = measure(emoji) ?? 0   // can't draw it: no disc
        measured[emoji] = share
        return share
    }

    /// Whether a picture gets the light disc: only a dark one, and only on a dark card.
    public static func needsBacking(_ emoji: String, onDark: Bool) -> Bool {
        onDark && shareTooDark(emoji) > darkShare
    }

    private static var measured: [String: Double] = [:]

    private static func measure(_ emoji: String) -> Double? {
        let renderer = ImageRenderer(content: Text(emoji).font(.system(size: 32)))
        renderer.scale = 1
        guard let image = renderer.cgImage, image.width > 0, image.height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        func linear(_ v: UInt8, _ alpha: Double) -> Double {
            let c = min(1, Double(v) / 255 / alpha)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        var dark = 0.0, all = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[i + 3]) / 255
            guard alpha > 0.1 else { continue }
            let luminance = 0.2126 * linear(pixels[i], alpha) + 0.7152 * linear(pixels[i + 1], alpha)
                + 0.0722 * linear(pixels[i + 2], alpha)
            all += alpha
            if luminance < 0.05 { dark += alpha }
        }
        return all > 0 ? dark / all : nil
    }
}

/// A word's picture. On a dark card (the island's and the iPhone's play card, always; the screens in dark mode) a dark
/// picture sits on a soft light disc, so it reads like the others.
public struct TomoPictureView: View {
    let emoji: String
    let size: CGFloat
    let darkCard: Bool
    @Environment(\.colorScheme) private var scheme

    /// `darkCard`: the card is dark whatever the appearance (the island, the iPhone's play screen); otherwise the
    /// screen's own light or dark mode decides.
    public init(_ emoji: String, size: CGFloat, darkCard: Bool = false) {
        self.emoji = emoji
        self.size = size
        self.darkCard = darkCard
    }

    public var body: some View {
        Text(emoji).font(.system(size: size))
            .background {
                if TomoPicture.needsBacking(emoji, onDark: darkCard || scheme == .dark) {
                    Circle()
                        .fill(RadialGradient(colors: [.white.opacity(0.85), .white.opacity(0.6), .white.opacity(0)],
                                             center: .center, startRadius: 0, endRadius: size * 0.8))
                        .frame(width: size * 1.6, height: size * 1.6)
                }
            }
    }
}

extension TomoPicture {
    /// The rule (TOMO_SELFTEST, swift test): the black bird gets the disc on a dark card and nothing does on a light one;
    /// a bright picture never does; and at most a few of the packs' pictures are dark.
    public static func selfTest(_ check: (Bool, String) -> Void) {
        let bird = "\u{1F426}\u{200D}\u{2B1B}", corn = "\u{1F33D}", gorilla = "\u{1F98D}"
        check(needsBacking(bird, onDark: true) && !needsBacking(bird, onDark: false),
              "pictures: the black bird gets a light disc on a dark card (\(Int(shareTooDark(bird) * 100))% too dark), none on a light one")
        check(!needsBacking(corn, onDark: true) && !needsBacking(gorilla, onDark: true),
              "pictures: corn and the gorilla read on a dark card as they are (\(Int(shareTooDark(corn) * 100))%, \(Int(shareTooDark(gorilla) * 100))% too dark)")
        let pictures = Set(TomoLanguages.shared.targets.flatMap { pack in
            pack.levels.flatMap { ($0.rounds ?? []).flatMap { [$0.answer].compactMap { $0 } + ($0.choices ?? []) } }
        } + TomoNeed.allCases.map(\.emoji))
        let dark = pictures.filter { needsBacking($0, onDark: true) }.sorted()
        check(!pictures.isEmpty && dark.count * 10 <= pictures.count,
              "pictures: \(dark.count) of the packs' \(pictures.count) pictures get the disc on a dark card: \(dark.joined(separator: " "))")
    }
}
