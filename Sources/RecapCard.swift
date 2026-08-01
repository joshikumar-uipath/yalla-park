import SwiftUI
import SwiftData

/// Task 4 — the shareable "Yalla Park, this year" recap. Every figure comes
/// from confirmed data; the fines-dodged number IS the ledger's decisive
/// total, and all money copy stays tentative ("~").

struct RecapStats: Equatable {
    var timesParked = 0
    var spentAED = Decimal(0)
    var likelySaves = 0
    var savedAED = Decimal(0)
    var topZone: String?
    var topZoneCount = 0
    var longestSessionHours = 0
    var busiestWeekday: String?

    static func compute(sessions: [Session], totals: SavingsTotals,
                        calendar: Calendar = .current) -> RecapStats {
        let confirmed = sessions.filter(\.userConfirmedPaid)
        var stats = RecapStats()
        stats.timesParked = confirmed.count
        stats.spentAED = SavingsStats.estimatedSpendAED(sessions: sessions)
        stats.likelySaves = totals.likelySaves
        stats.savedAED = totals.avoidedAED

        let zoneCounts = Dictionary(grouping: confirmed.map(\.zoneCode).filter { !$0.isEmpty },
                                    by: { $0 }).mapValues(\.count)
        if let top = zoneCounts.sorted(by: {
            $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }).first {
            stats.topZone = top.key
            stats.topZoneCount = top.value
        }

        stats.longestSessionHours = confirmed.map(\.durationHours).max() ?? 0

        let weekdayCounts = Dictionary(grouping: confirmed.map {
            calendar.component(.weekday, from: $0.startedAt) }, by: { $0 }).mapValues(\.count)
        if let top = weekdayCounts.sorted(by: {
            $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }).first {
            stats.busiestWeekday = calendar.weekdaySymbols[top.key - 1]
        }
        return stats
    }
}

// MARK: - The card itself (rendered to an image for sharing)

struct RecapCardView: View {
    let stats: RecapStats
    let year: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("P")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                Text("Yalla Park")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Text(String(year))
                    .font(.system(size: 17, weight: .bold))
                    .opacity(0.85)
            }

            Spacer()

            Text("\(stats.timesParked)")
                .font(.system(size: 84, weight: .heavy))
                .kerning(-2)
            Text("times parked without a fine on my mind")
                .font(.system(size: 16, weight: .semibold))
                .opacity(0.9)

            VStack(alignment: .leading, spacing: 10) {
                recapRow("shield.checkered",
                         "\(stats.likelySaves) fine\(stats.likelySaves == 1 ? "" : "s") likely dodged · ~AED \(formatAED(stats.savedAED))")
                recapRow("banknote", "~AED \(formatAED(stats.spentAED)) paid in parking")
                if let zone = stats.topZone {
                    recapRow("mappin.and.ellipse", "Zone \(zone) · parked \(stats.topZoneCount)×")
                }
                if stats.longestSessionHours > 0 {
                    recapRow("clock", "longest stay \(stats.longestSessionHours)h")
                }
                if let day = stats.busiestWeekday {
                    recapRow("calendar", "busiest day \(day)")
                }
            }
            .padding(.top, 22)

            Spacer()

            Text("yalla park · dubai · figures are estimates")
                .font(.system(size: 11, weight: .medium))
                .opacity(0.7)
        }
        .foregroundStyle(.white)
        .padding(26)
        .frame(width: 360, height: 500)
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
                               center: UnitPoint(x: 0.9, y: 0.05),
                               startRadius: 0, endRadius: 260)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func recapRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 20)
            Text(text)
                .font(.system(size: 15, weight: .semibold))
        }
    }
}

// MARK: - Screen: preview + share

struct RecapScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var sessions: [Session]

    private var stats: RecapStats {
        RecapStats.compute(sessions: sessions, totals: SavingsStats.totals(in: modelContext))
    }
    private var year: Int { Calendar.current.component(.year, from: .now) }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                RecapCardView(stats: stats, year: year)
                    .shadow(color: Theme.coral.opacity(0.35), radius: 24, y: 12)

                if let image = renderedImage() {
                    ShareLink(item: image,
                              preview: SharePreview("Yalla Park \(year)", image: image)) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share")
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.coral, in: RoundedRectangle(cornerRadius: 16))
                        .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 24)
                }
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.passCanvasTop.ignoresSafeArea())
        .navigationTitle("Your year")
        .navigationBarTitleDisplayMode(.inline)
    }

    @MainActor
    private func renderedImage() -> Image? {
        let renderer = ImageRenderer(content: RecapCardView(stats: stats, year: year))
        renderer.scale = 3
        guard let uiImage = renderer.uiImage else { return nil }
        return Image(uiImage: uiImage)
    }
}
