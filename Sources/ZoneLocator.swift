import Foundation
import CoreLocation

/// GPS → Parkin zone *number*, fully on-device.
///
/// Parkin zone numbers are Dubai's official community (district) numbers —
/// e.g. community 318 = Al Karama = zones 318A/B/C/D/W. The bundled dataset
/// (Resources/dubai-communities.json, from Dubai's open community polygons)
/// holds all 225 district polygons, so a point-in-polygon test yields the zone
/// number with no network call. The letter suffix (tariff band) is NOT
/// derivable from open data — the UI asks the user to pick it off the sign,
/// and zone memory / recents close the gap on repeat visits.
struct Community {
    let number: Int
    let name: String
    /// MultiPolygon: polygons → rings (first = outer, rest = holes) → [lon, lat].
    let polygons: [[[[Double]]]]
    let boundingBox: (minLon: Double, minLat: Double, maxLon: Double, maxLat: Double)

    /// Display name: "AL KARAMA" → "Al Karama".
    var displayName: String { name.capitalized }
}

enum ZoneLocator {
    static let communities: [Community] = load()

    /// The community containing the coordinate, or nil (open desert, sea, off-Dubai).
    static func community(at coordinate: CLLocationCoordinate2D) -> Community? {
        let lon = coordinate.longitude, lat = coordinate.latitude
        return communities.first { c in
            guard lon >= c.boundingBox.minLon, lon <= c.boundingBox.maxLon,
                  lat >= c.boundingBox.minLat, lat <= c.boundingBox.maxLat else { return false }
            return c.polygons.contains { rings in
                guard let outer = rings.first, contains(ring: outer, lon: lon, lat: lat) else { return false }
                let inHole = rings.dropFirst().contains { contains(ring: $0, lon: lon, lat: lat) }
                return !inHole
            }
        }
    }

    /// Ray casting, even-odd rule.
    private static func contains(ring: [[Double]], lon: Double, lat: Double) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let (xi, yi) = (ring[i][0], ring[i][1])
            let (xj, yj) = (ring[j][0], ring[j][1])
            if (yi > lat) != (yj > lat),
               lon < (xj - xi) * (lat - yi) / (yj - yi) + xi {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    private static func load() -> [Community] {
        guard let url = Bundle.main.url(forResource: "dubai-communities", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["communities"] as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let number = entry["n"] as? Int,
                  let name = entry["name"] as? String,
                  let polys = entry["polys"] as? [[[[Double]]]] else { return nil }
            var minLon = Double.infinity, minLat = Double.infinity
            var maxLon = -Double.infinity, maxLat = -Double.infinity
            for rings in polys {
                for point in rings.first ?? [] {
                    minLon = min(minLon, point[0]); maxLon = max(maxLon, point[0])
                    minLat = min(minLat, point[1]); maxLat = max(maxLat, point[1])
                }
            }
            return Community(number: number, name: name, polygons: polys,
                             boundingBox: (minLon, minLat, maxLon, maxLat))
        }
    }
}
