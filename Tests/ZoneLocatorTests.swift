import XCTest
import CoreLocation
@testable import DXBPark

/// The GPS → zone-number lookup. Ground truths verified against public
/// directories: zones 318x are Al Karama, community #318; 248 is Al Qusais
/// Industrial Fifth.
final class ZoneLocatorTests: XCTestCase {

    func testDatasetLoadsAllCommunities() {
        XCTAssertEqual(ZoneLocator.communities.count, 225)
        XCTAssertTrue(ZoneLocator.communities.allSatisfy { !$0.name.isEmpty && $0.number > 0 })
    }

    func testAlKaramaResolvesToZone318() {
        let karama = CLLocationCoordinate2D(latitude: 25.2478, longitude: 55.3061)
        let community = ZoneLocator.community(at: karama)
        XCTAssertEqual(community?.number, 318)
        XCTAssertEqual(community?.displayName, "Al Karama")
    }

    func testKnownCommunityNumbersExist() {
        let numbers = Set(ZoneLocator.communities.map(\.number))
        XCTAssertTrue(numbers.contains(318)) // Al Karama
        XCTAssertTrue(numbers.contains(248)) // Al Qusais Ind. Fifth
        XCTAssertTrue(numbers.contains(334)) // Al Satwa
    }

    func testDefaultMapCenterResolvesToABarshaDistrict() {
        // The app's pre-fix camera default (Al Barsha).
        let barsha = CLLocationCoordinate2D.alBarsha
        let community = ZoneLocator.community(at: barsha)
        XCTAssertNotNil(community)
        XCTAssertTrue(community!.displayName.localizedCaseInsensitiveContains("Barsha"))
    }

    func testOpenSeaResolvesToNothing() {
        let gulf = CLLocationCoordinate2D(latitude: 25.35, longitude: 54.8)
        XCTAssertNil(ZoneLocator.community(at: gulf))
    }

    func testLookupIsFastEnoughForThePipeline() {
        let karama = CLLocationCoordinate2D(latitude: 25.2478, longitude: 55.3061)
        _ = ZoneLocator.community(at: karama) // warm the lazy load
        measure {
            for _ in 0..<50 { _ = ZoneLocator.community(at: karama) }
        }
    }
}
