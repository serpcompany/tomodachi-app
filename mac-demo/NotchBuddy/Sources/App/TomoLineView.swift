import CoreServices
import SwiftUI
import TomoCore

// MARK: - Mac-only word helpers (Dictionary.app, fitting a line in the card); the rest is TomoWords in TomoCore

extension TomoWords {
    /// The word's entry in the Mac's own dictionaries (Dictionary.app, offline), in the learner's language, or nil:
    /// then the word card leaves the section out, never showing an entry the learner can't read (#198). It comes from
    /// the first dictionary switched on in Dictionary's settings whose languages are the pair's, so an English speaker
    /// learning Japanese reads ウィズダム英和・和英 (ja-en) even with スーパー大辞林 ahead of it, and a Japanese speaker
    /// reads 大辞林 (ja). When none fits, or without the list (`TomoMacDictionaries`), only a learner of their own language
    /// gets the system's pick (`TomoMacDictionaries.choice`). The Zenbu dictionary replaces this (#9).
    @MainActor static func macDictionary(_ word: String, target: String, learner: String) -> String? {
        guard !word.isEmpty else { return nil }
        func entry(in dictionary: DCSDictionary?) -> String? {
            let cf = word as CFString
            let def = DCSCopyTextDefinition(dictionary, cf, CFRangeMake(0, CFStringGetLength(cf)))?.takeRetainedValue()
            return (def as String?).map { String($0.prefix(260)) }
        }
        let active = TomoMacDictionaries.active()
        switch TomoMacDictionaries.choice(active?.map(\.identifier), target: target, learner: learner) {
        case .dictionary(let i): return active.flatMap { entry(in: $0[i].dictionary) }
        case .system: return entry(in: nil)
        case .hidden: return nil
        }
    }

    /// Opens Dictionary.app on the word (all installed dictionaries, including bilingual ones).
    static func openMacDictionary(_ word: String) {
        let q = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? word
        if let url = URL(string: "dict://\(q)") { NSWorkspace.shared.open(url) }
    }

    // Word layout constants shared by measuring and drawing, so the fit is exact.
    static let wordPadding: CGFloat = 2              // each side of a clickable word
    static let lineSpacing: CGFloat = 2
    static func wordSpacing(script: String, size: CGFloat) -> CGFloat { script == "Jpan" ? 2 : size * 0.2 }

    static func lineFont(_ size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .bold)
        return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    }

    /// The largest font size (24 → 15 pt) at which the words, laid out exactly like `TomoLineView`
    /// (per-word padding, gaps, wrapping), fit in `box`.
    static func fittingSize(_ words: [String], script: String, in box: CGSize, maxSize: CGFloat = 24) -> CGFloat {
        for size: CGFloat in [28, 26, 24, 22, 20, 18, 17, 16, 15] where size <= maxSize {
            let font = lineFont(size)
            let gap = wordSpacing(script: script, size: size)
            var lines = 1, x: CGFloat = 0
            for w in words {
                let width = ceil((w as NSString).size(withAttributes: [.font: font]).width) + wordPadding * 2
                if width > box.width { lines = .max / 2; break }      // one word wider than the box: smaller size
                if x > 0 && x + width > box.width { lines += 1; x = 0 }
                x += width + gap
            }
            let lineHeight = ceil(font.ascender - font.descender + font.leading)
            if CGFloat(lines) * lineHeight + CGFloat(lines - 1) * lineSpacing <= box.height { return size }
        }
        return 15
    }
}

/// The dictionaries switched on in Dictionary's settings, in its order, with their languages. DictionaryServices
/// publishes only the lookup, which takes the first of them with an entry, so a monolingual dictionary ahead of a
/// bilingual one always wins. Choosing one takes two calls it doesn't publish (`DCSGetActiveDictionaries`,
/// `DCSDictionaryGetIdentifier`), found at run time: no list if they're gone or return something else. Fine for the
/// Developer ID build; a Mac App Store build drops them (mac-demo/app-store.md).
@MainActor
enum TomoMacDictionaries {
    struct Active { let dictionary: DCSDictionary; let identifier: String }
    /// What the word card shows: that dictionary's entry, the system's pick (the first active one with an entry), or
    /// no section.
    enum Choice: Equatable { case dictionary(Int), system, hidden }

    // Both return CF objects of a type checked before use (`active(_:identifier:)`), not the types they return today.
    private typealias ActiveList = @convention(c) () -> Unmanaged<CFTypeRef>?
    private typealias Identifier = @convention(c) (DCSDictionary) -> Unmanaged<CFTypeRef>?
    private static let services = dlopen(
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/DictionaryServices.framework/DictionaryServices",
        RTLD_LAZY)
    private static let activeList = dlsym(services, "DCSGetActiveDictionaries")
        .map { unsafeBitCast($0, to: ActiveList.self) }
    private static let identifier = dlsym(services, "DCSDictionaryGetIdentifier")
        .map { unsafeBitCast($0, to: Identifier.self) }

    /// The dictionaries switched on, in Dictionary's order, with their identifiers; nil without the list.
    static func active() -> [Active]? {
        guard let activeList, let identifier else { return nil }
        return active(activeList()?.takeUnretainedValue()) { identifier($0)?.takeUnretainedValue() }
    }

    /// The list from what `DCSGetActiveDictionaries` returned, checked before anything goes back to DictionaryServices,
    /// so a macOS that changes these calls gets no list (no section, or the system's pick) instead of a crash: nil unless
    /// it's an array whose every element is an object other than a string; a dictionary whose identifier isn't a
    /// string is left out.
    static func active(_ list: CFTypeRef?, identifier: (DCSDictionary) -> CFTypeRef?) -> [Active]? {
        guard let list, CFGetTypeID(list) == CFArrayGetTypeID() else { return nil }
        let array = unsafeBitCast(list, to: CFArray.self)
        var dictionaries: [Active] = []
        for i in 0..<CFArrayGetCount(array) {
            guard let value = CFArrayGetValueAtIndex(array, i) else { return nil }
            let object = Unmanaged<CFTypeRef>.fromOpaque(value).takeUnretainedValue()
            guard CFGetTypeID(object) != CFStringGetTypeID() else { return nil }
            let dictionary = unsafeBitCast(object, to: DCSDictionary.self)
            guard let id = identifier(dictionary), CFGetTypeID(id) == CFStringGetTypeID() else { continue }
            dictionaries.append(Active(dictionary: dictionary, identifier: unsafeBitCast(id, to: CFString.self) as String))
        }
        return dictionaries
    }

    /// The languages an Apple dictionary's identifier names: com.apple.dictionary.ja-en.WISDOM → ja, en;
    /// com.apple.dictionary.ja.Daijirin → ja; com.apple.dictionary.zh_CN-en.OCD → zh, en. Nil when it names none
    /// (com.apple.dictionary.NOAD) or isn't Apple's.
    static func languages(_ identifier: String) -> Set<String>? {
        let prefix = "com.apple.dictionary."
        guard identifier.hasPrefix(prefix),
              let part = identifier.dropFirst(prefix.count).split(separator: ".").first else { return nil }
        let codes = part.split(separator: "-").map { String($0.prefix { $0 != "_" }) }
        guard codes.allSatisfy({ (2...3).contains($0.count) && $0.allSatisfy { $0.isASCII && $0.isLowercase } })
        else { return nil }
        return Set(codes)
    }

    /// What a learner of `target` who reads `learner` gets, from the active dictionaries' identifiers in Dictionary's
    /// order (nil without the list): the first whose languages are just the pair's (ja-en for English, ja for
    /// Japanese), never a monolingual one in a language they don't read. With none, a learner of their own language
    /// gets the system's pick, anyone else no section.
    static func choice(_ identifiers: [String]?, target: String, learner: String) -> Choice {
        let pair: Set = [target, learner]
        if let i = identifiers?.firstIndex(where: { languages($0) == pair }) { return .dictionary(i) }
        return target == learner ? .system : .hidden
    }
}

// MARK: - Tomo's line as clickable words

struct TomoLineView: View {
    @ObservedObject public var game: TomoGame
    @ObservedObject public var lang = TomoLanguages.shared
    /// Highlighted words (drag across them); the card shows "I don't understand" for these.
    @Binding public var selection: ClosedRange<Int>?
    /// The fixed box the line must fit in (TomoGrid.lineRow / wordRow).
    let size: CGSize
    /// What Tomo said (the talking line, or a picture round's word).
    let text: String
    var maxSize: CGFloat = 24
    /// Drag-to-highlight for "I don't understand" (talking stage only).
    var selectable = true
    /// Split only on spaces (pack text such as picture-round words).
    var spacesOnly = false
    @State private var frames: [Int: CGRect] = [:]
    @State private var dragStart: Int?
    @State private var hovered: Int?

    private var words: [String] { TomoWords.tokens(text, script: lang.target.script, spacesOnly: spacesOnly) }
    /// The largest size at which the line fits the box, measured the way it's drawn.
    private var fontSize: CGFloat { TomoWords.fittingSize(words, script: lang.target.script, in: size, maxSize: maxSize) }

    var body: some View {
        FlowLayout(spacing: TomoWords.wordSpacing(script: lang.target.script, size: fontSize),
                   lineSpacing: TomoWords.lineSpacing) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                Text(w)
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .fixedSize()
                    .padding(.horizontal, TomoWords.wordPadding)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(selection?.contains(i) == true ? Color(hex: "#6366F1").opacity(0.45)
                                  : hovered == i ? Color.white.opacity(0.1) : .clear)
                    )
                    .overlay(alignment: .bottom) {
                        if hovered == i { Rectangle().fill(Color.white.opacity(0.5)).frame(height: 1.5).offset(y: 1) }
                    }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("tomoLine")) } action: { frames[i] = $0 }
                    .onHover { hovered = $0 ? i : (hovered == i ? nil : hovered) }
            }
        }
        .coordinateSpace(name: "tomoLine")
        .onChange(of: game.cardRequest) { _, i in
            guard let i, words.indices.contains(i) else { return }
            game.openWord(TomoWords.bare(words[i]))
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("tomoLine"))
                .onChanged { g in
                    guard let here = index(at: g.location) else { return }
                    if dragStart == nil { dragStart = index(at: g.startLocation) ?? here }
                    if selectable, hypot(g.translation.width, g.translation.height) > 4, let s = dragStart {
                        selection = min(s, here)...max(s, here)
                    }
                }
                .onEnded { g in
                    defer { dragStart = nil }
                    let moved = hypot(g.translation.width, g.translation.height) > 4
                    if !moved, let i = index(at: g.location) {        // click one word → word card
                        selection = nil
                        game.openWord(TomoWords.bare(words[i]))
                    }
                }
        )
        .id(text)
    }

    private func index(at p: CGPoint) -> Int? {
        frames.first { $0.value.insetBy(dx: -3, dy: -3).contains(p) }?.key
    }
}

