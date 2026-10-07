import SwiftUI
import TomoCore
import WidgetKit

// MARK: - Home Screen and Lock Screen widgets (issues #52, #88)
//
// Small: Tomo, its age, and a red dot when something is waiting. Medium: the same plus the level and its
// experience bar. On the Lock Screen (the first run's widget how-to points there): age and level with the bar and
// what's waiting (rectangular), the bar around Tomo's age (circular), or one line (inline); iOS draws these in one
// tint, so they're text and a gauge. The app writes a TomoGlance to the App Group whenever progress changes and asks WidgetKit
// to reload; when nothing is waiting, a second entry turns the red dot on at the next due time.
// Tomo moves the way it does on the Lock Screen (TomoMovingMascot): asking when something waits, asleep until
// the next words otherwise.

@main
struct TomoWidgetBundle: WidgetBundle {
    var body: some Widget {
        TomoWidget()
        TomoVisitLiveActivity()
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
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
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
        switch family {
        case .accessoryRectangular, .accessoryCircular, .accessoryInline:
            lockScreen.containerBackground(for: .widget) { Color.clear }
        default:
            Group {
                if family == .systemMedium { medium } else { small }
            }
            .foregroundStyle(Color.white)
            .containerBackground(for: .widget) {
                LinearGradient(colors: [Color(red: 0.07, green: 0.12, blue: 0.15), Color(red: 0.04, green: 0.05, blue: 0.07)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
    }

    private var bar: Double { min(max(glance.progress, 0), 1) }

    @ViewBuilder private var lockScreen: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: bar) { Text(glance.level) } currentValueLabel: {
                Text(glance.age).font(.system(size: 13, weight: .bold, design: .rounded)).minimumScaleFactor(0.6)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
        case .accessoryInline:
            Text(glance.waiting ? "\(glance.invite) \(glance.status)" : glance.status)
        default:
            VStack(alignment: .leading, spacing: 2) {
                Text("\(glance.age) · \(glance.level)")
                    .font(.system(size: 15, weight: .bold, design: .rounded)).widgetAccentable()
                Gauge(value: bar) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity)
                Text(glance.status).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tomo(_ size: CGFloat) -> some View {
        TomoMovingMascot(glance: glance, ready: glance.waiting, size: size)
    }

    private var small: some View {
        VStack(spacing: 2) {
            HStack {
                ageChip
                Spacer()
                if glance.waiting { redDot }
            }
            tomo(100).frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(glance.status)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.75))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            tomo(120)
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
