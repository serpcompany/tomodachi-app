import SwiftUI
import TomoCore
import WidgetKit

// MARK: - Home Screen and Lock Screen widgets (issues #52, #88)
//
// They say what Tomo is doing, never how many words are waiting (decisions.md, 2026-10-11): it wants to play, lit in
// the moment's amber as small Tomo glows on the Mac (TomoMoment), or it rests until a time ("Back at 10:12").
// Small: Tomo, its age, and what it's doing. Medium: the same plus the level and its experience bar. On the Lock
// Screen (the first run's widget how-to points there): age and level with the bar and what Tomo's doing
// (rectangular), the bar around Tomo's age (circular), or one line (inline); iOS draws these in one tint, so they're
// text and a gauge. The app writes a TomoGlance to the App Group whenever progress changes and asks WidgetKit to
// reload; when Tomo rests, a second entry has it want to play at the next due time (`cameDue`).
// Tomo moves the way it does on the Lock Screen (TomoMovingMascot): asking when it wants to play, asleep otherwise.

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
            entries.append(TomoEntry(date: next, glance: glance.cameDue))
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
                LinearGradient(colors: [TomoGlanceLight.wash(Color(red: 0.07, green: 0.12, blue: 0.15), glance.light),
                                        Color(red: 0.04, green: 0.05, blue: 0.07)],
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
            if glance.waiting { Text("\(glance.invite) \(glance.status)") } else { TomoGlanceLine.text(glance) }
        default:
            VStack(alignment: .leading, spacing: 2) {
                Text("\(glance.age) · \(glance.level)")
                    .font(.system(size: 15, weight: .bold, design: .rounded)).widgetAccentable()
                Gauge(value: bar) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity)
                TomoGlanceLine.text(glance).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Tomo, in the moment's light: an amber glow behind it while it wants to play, as on the Mac.
    private func tomo(_ size: CGFloat) -> some View {
        TomoMovingMascot(glance: glance, ready: glance.waiting, size: size)
            .background { TomoGlanceLight.glow(glance.light, size: size) }
    }

    private var small: some View {
        VStack(spacing: 2) {
            HStack {
                ageChip
                Spacer()
            }
            tomo(100).frame(maxWidth: .infinity, maxHeight: .infinity)
            TomoGlanceLine(glance: glance, size: 12, lines: 1)
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            tomo(120)
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
                TomoGlanceLine(glance: glance, size: 14, lines: 2)
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
}

/// What Tomo is doing, in one line: it wants to play (in the moment's colour), or it rests until a time ("Back at
/// 10:12", the time filled in from `nextDue`), else "Tomo is resting". Never how many words.
struct TomoGlanceLine: View {
    let glance: TomoGlance
    let size: CGFloat
    let lines: Int

    var body: some View {
        Self.text(glance)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(glance.waiting ? (glance.light?.color ?? .white) : Color.white.opacity(0.75))
            .lineLimit(lines).minimumScaleFactor(0.7)
    }

    /// The words alone (the Lock Screen draws them in its own tint).
    static func text(_ glance: TomoGlance) -> Text {
        if !glance.waiting, let next = glance.nextDue, next > .now {
            let parts = glance.nextLabel.components(separatedBy: "{time}")
            return Text(parts[0]) + Text(next, style: .time) + Text(parts.count > 1 ? parts[1] : "")
        }
        return Text(glance.status)
    }
}

/// The moment's light where iOS draws Tomo: the colours TomoMoment gives the Mac's card and notch.
enum TomoGlanceLight {
    /// A soft glow behind Tomo, as small Tomo's call glow on the Mac: none without a moment.
    @ViewBuilder static func glow(_ moment: TomoMoment?, size: CGFloat) -> some View {
        if let moment {
            RadialGradient(colors: [moment.color.opacity(0.5 * moment.strength), moment.color.opacity(0)],
                           center: .center, startRadius: 0, endRadius: size * 0.62)
                .frame(width: size * 1.3, height: size * 1.3)
        }
    }

    /// A background washed a little toward the moment's colour, as the Mac's island washes in it.
    static func wash(_ base: Color, _ moment: TomoMoment?, amount: Double = 0.22) -> Color {
        guard let moment else { return base }
        return base.mix(with: moment.color, by: amount * moment.strength)
    }
}
