import SwiftUI
import TomoCore
import UIKit

// MARK: - Tap a word in Tomo's line: its word card
//
// What Tomo's whole line means comes from the pack (offline). The word's own meaning comes from the AI
// provider when one is set (TomoBrain.define), until the Zenbu dictionary provides lookups (#9). Two ways
// further: the Zenbu web dictionary, and the iPhone's built-in dictionary (UIReferenceLibraryViewController).

/// Tomo's line as words you can tap, wrapped like text.
struct TomoTappableLine: View {
    @ObservedObject var game = TomoGame.shared
    @ObservedObject var lang = TomoLanguages.shared
    let text: String
    /// Pack text (a picture round's word) is spaced already; split only on spaces.
    var spacesOnly = false

    /// Dynamic Type, up to a point: the line sits in a fixed row of Tomo's screen (TomoPhoneView).
    @ScaledMetric(relativeTo: .title) private var textScale: CGFloat = 1

    private var words: [String] { TomoWords.tokens(text, script: lang.target.script, spacesOnly: spacesOnly) }
    private var size: CGFloat { (text.count <= 8 ? 34 : text.count <= 14 ? 28 : 22) * min(max(textScale, 0.85), 1.25) }

    var body: some View {
        FlowLayout(spacing: lang.target.script == "Jpan" ? 4 : size * 0.25, lineSpacing: 4) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, w in
                Button { game.openWord(TomoWords.bare(w)) } label: {
                    Text(w)
                        .font(.system(size: size, weight: .bold, design: .rounded))
                        .underline(pattern: .dot, color: Color.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .id(text)
        // VoiceOver: the whole line, read in the target language's voice, with each word's card as an action.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken))
        .accessibilityAddTraits(.isStaticText)
        .accessibilityActions {
            ForEach(Array(words.enumerated()), id: \.offset) { _, w in
                Button(lang.learner("a11y.lookUp", ["word": TomoWords.bare(w)])) { game.openWord(TomoWords.bare(w)) }
            }
        }
    }

    private var spoken: AttributedString {
        var s = AttributedString(text)
        s.languageIdentifier = lang.target.speechLocale
        return s
    }
}

struct TomoWordSheet: View {
    @ObservedObject var game = TomoGame.shared
    @ObservedObject var lang = TomoLanguages.shared
    let word: String
    @State private var systemDictionary = false

    private var ui: LearnerPack { lang.learner }

    /// Tomo's whole line: what it means and how it reads (the pack's own, so it works offline).
    private var line: (say: String, reading: String?, meaning: String) {
        game.isChat ? (game.line.say, game.line.romanization, game.line.translation)
            : (game.round.say, game.round.romanization, game.round.meaning)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(ui("word.title").uppercased())
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(game.wordCard?.headword ?? word)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    if let reading = game.wordCard?.reading {
                        Text(reading).font(.system(size: 18)).foregroundStyle(.secondary)
                    }
                }
                if game.lookingUp {
                    Text(ui("word.loading")).foregroundStyle(.secondary)
                } else if let card = game.wordCard, card.usedAI, !card.meaning.isEmpty {
                    Text(card.meaning).font(.system(size: 20, weight: .semibold))
                    if let note = card.note { Text(note).font(.system(size: 15)).foregroundStyle(.secondary) }
                }

                // The whole line, from the pack
                VStack(alignment: .leading, spacing: 4) {
                    Text(line.say).font(.system(size: 17, weight: .semibold))
                    Text([line.reading, line.meaning].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 15)).foregroundStyle(.secondary)
                    if !game.isChat, let adult = game.round.adult {
                        Text(ui("grownUpsSay", ["x": adult])).font(.system(size: 15)).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 10) {
                    if let url = lang.target.dictionaryURL(for: game.wordCard?.headword ?? word) {
                        Link(destination: url) { pill(ui("word.open"), icon: "safari") }
                    }
                    // Always offered: with no dictionary downloaded yet, iOS's own sheet offers to get one
                    // (Japanese–English, 大辞泉, …), which a learner otherwise wouldn't find.
                    Button { systemDictionary = true } label: { pill(ui("word.openMac"), icon: "character.book.closed") }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Color.white)
        .background(Color(red: 0.07, green: 0.08, blue: 0.1).ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $systemDictionary) { SystemDictionary(term: word).ignoresSafeArea() }
    }

    private func pill(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 14).frame(height: 44)
            .background(Color.white.opacity(0.1), in: Capsule())
    }
}

/// The iPhone's built-in dictionary (the same one as Look Up), for any installed dictionary.
private struct SystemDictionary: UIViewControllerRepresentable {
    let term: String
    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: term)
    }
    func updateUIViewController(_ controller: UIReferenceLibraryViewController, context: Context) {}
}
