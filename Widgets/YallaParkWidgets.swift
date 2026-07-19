import WidgetKit
import SwiftUI
import ActivityKit

@main
struct YallaParkWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ParkNowWidget()
        ParkingLiveActivity()
    }
}

// MARK: - Live Activity: the lock-screen / Dynamic Island parking meter

struct ParkingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ParkingActivityAttributes.self) { context in
            LockScreenMeter(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 7) {
                        BrandChip()
                        Text("Zone \(context.attributes.zoneCode)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.startedAt...context.state.expiresAt,
                         countsDown: true)
                        .font(.system(size: 22, weight: .bold))
                        .monospacedDigit()
                        .frame(width: 76)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(Theme.coral)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ProgressView(timerInterval: context.state.startedAt...context.state.expiresAt,
                                     countsDown: true, label: { EmptyView() },
                                     currentValueLabel: { EmptyView() })
                            .progressViewStyle(.linear)
                            .tint(Theme.coral)
                        Text("expires \(context.state.expiresAt.formatted(date: .omitted, time: .shortened)) · tap to extend")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            } compactLeading: {
                Image(systemName: "parkingsign")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.coral)
            } compactTrailing: {
                Text(timerInterval: context.state.startedAt...context.state.expiresAt,
                     countsDown: true)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .frame(width: 46)
                    .foregroundStyle(Theme.coral)
            } minimal: {
                Image(systemName: "parkingsign")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.coral)
            }
            .widgetURL(URL(string: "dxbpark://parked"))
            .keylineTint(Theme.coral)
        }
    }
}

private struct LockScreenMeter: View {
    let context: ActivityViewContext<ParkingActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                BrandChip()
                Text("Yalla Park")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("Zone \(context.attributes.zoneCode)")
                    .font(.system(size: 14, weight: .semibold))
                    .opacity(0.92)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(timerInterval: context.state.startedAt...context.state.expiresAt,
                     countsDown: true)
                    .font(.system(size: 40, weight: .bold))
                    .monospacedDigit()
                    .kerning(-1)
                Spacer()
                Text("expires \(context.state.expiresAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 13, weight: .medium))
                    .opacity(0.9)
            }
            .padding(.top, 10)

            ProgressView(timerInterval: context.state.startedAt...context.state.expiresAt,
                         countsDown: true, label: { EmptyView() },
                         currentValueLabel: { EmptyView() })
                .progressViewStyle(.linear)
                .tint(.white)
                .padding(.top, 8)
        }
        .foregroundStyle(.white)
        .padding(18)
        .activityBackgroundTint(nil)
        .background(
            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: 0xFB4E2A), location: 0),
                        .init(color: Color(hex: 0xFF6E3C), location: 0.55),
                        .init(color: Color(hex: 0xFF5168), location: 1),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                RadialGradient(colors: [Color(hex: 0xFF9A54), .clear],
                               center: UnitPoint(x: 0.85, y: 0),
                               startRadius: 0, endRadius: 180)
            }
        )
    }
}

private struct BrandChip: View {
    var body: some View {
        Text("P")
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(.white.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Home-screen widget: manual backup for the Shortcut automation,
// or a live countdown meter while a paid session is running.

struct ParkNowEntry: TimelineEntry {
    let date: Date
    let session: WidgetSession?
}

struct ParkNowProvider: TimelineProvider {
    func placeholder(in context: Context) -> ParkNowEntry {
        ParkNowEntry(date: .now, session: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (ParkNowEntry) -> Void) {
        completion(ParkNowEntry(date: .now, session: WidgetSessionStore.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ParkNowEntry>) -> Void) {
        if let session = WidgetSessionStore.load() {
            // One entry is enough — Text(timerInterval:) ticks by itself.
            // At expiry, WidgetKit asks again and we fall back to the park button.
            completion(Timeline(entries: [ParkNowEntry(date: .now, session: session)],
                                policy: .after(session.expiresAt)))
        } else {
            completion(Timeline(entries: [ParkNowEntry(date: .now, session: nil)], policy: .never))
        }
    }
}

struct ParkNowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSessionStore.widgetKind, provider: ParkNowProvider()) { entry in
            ParkNowView(entry: entry)
        }
        .configurationDisplayName("Yalla Park")
        .description("One tap to pay — and a live meter while you're parked.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct ParkNowView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ParkNowEntry

    var body: some View {
        Group {
            switch (family, entry.session) {
            case (.accessoryCircular, let session?):
                VStack(spacing: 1) {
                    Image(systemName: "parkingsign")
                        .font(.system(size: 12, weight: .bold))
                    Text(timerInterval: entry.date...session.expiresAt, countsDown: true)
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                }
                .widgetURL(URL(string: "dxbpark://extend"))
            case (.accessoryCircular, nil):
                Image(systemName: "parkingsign")
                    .font(.system(size: 22, weight: .bold))
                    .widgetURL(URL(string: "dxbpark://parked"))
            case (_, let session?):
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 5) {
                        BrandChip()
                        Text("Zone \(session.zoneCode)")
                            .font(.system(size: 12, weight: .semibold))
                            .opacity(0.92)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer()
                    Text(timerInterval: entry.date...session.expiresAt, countsDown: true)
                        .font(.system(size: 30, weight: .bold))
                        .monospacedDigit()
                        .kerning(-0.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    ProgressView(timerInterval: session.startedAt...session.expiresAt,
                                 countsDown: true, label: { EmptyView() },
                                 currentValueLabel: { EmptyView() })
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .padding(.top, 4)
                    Text("tap to extend")
                        .font(.system(size: 11, weight: .medium))
                        .opacity(0.8)
                        .padding(.top, 5)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .widgetURL(URL(string: "dxbpark://extend"))
            default:
                VStack(spacing: 8) {
                    Image(systemName: "car.fill")
                        .font(.system(size: 26, weight: .semibold))
                    Text("I just parked")
                        .font(.system(size: 14, weight: .bold))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .widgetURL(URL(string: "dxbpark://parked"))
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0xFB4E2A), location: 0),
                    .init(color: Color(hex: 0xFF6E3C), location: 0.55),
                    .init(color: Color(hex: 0xFF5168), location: 1),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }
}
