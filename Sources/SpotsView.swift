import SwiftUI
import SwiftData

struct SpotsView: View {
    @Query(sort: \Spot.lastParkedAt, order: .reverse) private var spots: [Spot]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Group {
                if spots.isEmpty {
                    ContentUnavailableView(
                        "No spots yet",
                        systemImage: "mappin.slash",
                        description: Text("Park somewhere and pay once — the zone is remembered and auto-filled next time.")
                    )
                } else {
                    List {
                        ForEach(spots) { spot in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(spot.name)
                                    .font(.system(size: 16, weight: .semibold))
                                HStack(spacing: 6) {
                                    Text("Zone \(spot.zoneCode)")
                                    Text("·")
                                    Text("parked \(spot.timesParked)×")
                                    Text("·")
                                    Text(spot.lastParkedAt.formatted(.relative(presentation: .named)))
                                }
                                .font(.system(size: 13.5))
                                .foregroundStyle(Theme.labelSecondary)
                            }
                            .padding(.vertical, 2)
                        }
                        .onDelete { indexSet in
                            for index in indexSet { modelContext.delete(spots[index]) }
                        }
                    }
                }
            }
            .navigationTitle("My Spots")
        }
    }
}
