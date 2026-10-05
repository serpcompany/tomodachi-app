import SwiftUI
import TomoCore
import WidgetKit

// MARK: - Home Screen widgets (issue #52)
//
// Small: Tomo, its age, and a red dot when something is waiting. Medium: the same plus the level and its
// experience bar. The app writes a TomoGlance to the App Group whenever progress changes and asks WidgetKit
// to reload; when nothing is waiting, a second entry turns the red dot on at the next due time.
// Widgets can't animate continuously: Tomo is a TomoChickStill whose pose changes with each entry.

@main
struct TomoWidgetBundle: WidgetBundle {
    var body: some Widget {
        TomoWidget()
    }
}

struct TomoWidget: Widget {
    static let kind = "TomoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: TomoTimeline()) { entry in
            TomoWidgetView(glance: entry.glance)
        }
        .configurationDisplayName(appName)
        .description(TomoGlance.load()?.about ?? "")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// The app's name, from the bundle (it's a name, not text to translate).
let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ""

struct TomoEntry: TimelineEntry {
    let date: Date
    let glance: TomoGlance
}

struct TomoTimeline: TimelineProvider {
    func placeholder(in context: Context) -> TomoEntry { TomoEntry(date: .now, glance: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (TomoEntry) -> Void) {
        completion(TomoEntry(date: .now, glance: TomoGlance.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TomoEntry>) -> Void) {
        let glance = TomoGlance.load() ?? .placeholder
        var entries = [TomoEntry(date: .now, glance: glance)]
        if let next = glance.nextDue, next > .now {
            var later = glance
            later.waiting = true
            later.status = glance.statusLater
            entries.append(TomoEntry(date: next, glance: later))
        }
        completion(Timeline(entries: entries, policy: .never))   // the app reloads it when progress changes
    }
}

struct TomoWidgetView: View {
    let glance: TomoGlance
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .systemMedium { medium } else { small }
        }
        .foregroundStyle(Color.white)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 0.07, green: 0.12, blue: 0.15), Color(red: 0.04, green: 0.05, blue: 0.07)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    /// Waiting: Tomo has something to ask. Nothing waiting: content.
    private var tomo: some View {
        TomoChickStill(state: glance.waiting ? .question : .idle, emote: glance.waiting ? nil : .happy,
                       growth: glance.growth)
    }

    private var small: some View {
        VStack(spacing: 2) {
            HStack {
                ageChip
                Spacer()
                if glance.waiting { redDot }
            }
            tomo.frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(glance.status)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.75))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            tomo.frame(width: 120, height: 120)
                .overlay(alignment: .topTrailing) { if glance.waiting { redDot } }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(appName).font(.system(size: 16, weight: .bold, design: .rounded)).lineLimit(1)
                    ageChip
                }
                Text(glance.level)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.7))
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule()
                            .fill(LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.55), Color(red: 0.2, green: 0.83, blue: 0.6)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(6, g.size.width * min(max(glance.progress, 0), 1)))
                    }
                }
                .frame(height: 6)
                Text(glance.status)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
        }
    }

    @ViewBuilder private var ageChip: some View {
        if !glance.age.isEmpty {
            Text(glance.age)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 1, green: 0.85, blue: 0.66))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Color(red: 0.29, green: 0.2, blue: 0.14), in: Capsule())
        }
    }

    private var redDot: some View {
        Circle().fill(Color(red: 1, green: 0.27, blue: 0.3)).frame(width: 12, height: 12)
    }
}
