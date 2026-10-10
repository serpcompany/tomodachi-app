import SwiftUI

// MARK: - About: the version, the privacy policy, support, and the credits (the same on the Mac and the iPhone)
//
// The credits must be visible wherever the app ships: the word data is CC BY (Wordbank, NINJAL), JMdict is CC BY-SA,
// and blobatar and Coucou are MIT. Each credit's text is in ui.<id>.json (`about.credit.<id>` and `.body`); its link
// is below. Tomo here is the app's mascot, drawn live.

public struct TomoAboutScreen: View {
    @ObservedObject var lang = TomoLanguages.shared

    public init() {}

    /// Where the links go. The privacy policy and support pages are the App Store listing's (ios-demo/metadata).
    public enum Links {
        public static let privacy = URL(string: "https://zenbujapanese.com/privacy")!
        public static let support = URL(string: "https://zenbujapanese.com/support")!
    }

    /// Everything Tomodachi is built on that asks for credit, with where it comes from.
    static let credits: [(id: String, url: URL)] = [
        ("wordbank", URL(string: "https://wordbank.stanford.edu/")!),
        ("ninjal", URL(string: "https://mmsrv.ninjal.ac.jp/bev/")!),
        ("jmdict", URL(string: "https://www.edrdg.org/edrdg/licence.html")!),
        ("blobatar", URL(string: "https://github.com/Alain00/blobatar")!),
        ("coucou", URL(string: "https://github.com/Louis-CFM/coucou")!),
    ]

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Tomodachi"
    }

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    public var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    TomoLiveAvatar(size: 96, look: .mascot, material: .classic, growth: 0)
                    Text(appName).font(.title2.bold())
                    Text(lang.learner("about.by")).font(.callout.weight(.medium)).foregroundStyle(.secondary)
                    Text(lang.learner("about.version", ["v": version])).font(.callout).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(lang.learner("about.tagline")).multilineTextAlignment(.center).padding(.top, 4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }

            Section {
                link(lang.learner("about.privacy"), icon: "hand.raised.fill", to: Links.privacy)
                link(lang.learner("about.support"), icon: "questionmark.bubble.fill", to: Links.support)
            } footer: {
                Text(lang.learner("about.feedback")).font(.caption).foregroundStyle(.secondary)
            }

            Section(lang.learner("about.credits")) {
                ForEach(Self.credits, id: \.id) { credit in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(lang.learner("about.credit.\(credit.id)")).font(.headline)
                            Text(lang.learner("about.credit.\(credit.id).body"))
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        Spacer(minLength: 4)
                        Link(destination: credit.url) {
                            Image(systemName: "arrow.up.right.square").font(.system(size: 15))
                        }
                        .help(lang.learner("about.open"))
                        .accessibilityLabel(lang.learner("about.open"))
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func link(_ title: String, icon: String, to url: URL) -> some View {
        Link(destination: url) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
    }
}
