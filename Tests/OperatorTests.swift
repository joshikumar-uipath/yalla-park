import XCTest
@testable import DXBPark

/// Multi-operator contracts. The SMS bodies are exact strings the operators'
/// gateways parse — a single wrong space is a failed payment, so these tests
/// pin the field-verified formats character by character.
final class OperatorTests: XCTestCase {
    private let plate = PlateProfile(emirate: .dubai, letters: "BB", number: "60925")

    // MARK: - Parkonic SMS format (field-verified ticket 235924201)

    func testParkonicBodyMatchesFieldVerifiedFormat() {
        XCTAssertEqual(ParkonicRules.smsBody(plate: plate, zone: "P105", hours: 1),
                       "DXBBB 60925 P105 1")
    }

    func testParkonicBodyRestoresMissingPPrefix() {
        XCTAssertEqual(ParkonicRules.smsBody(plate: plate, zone: "105", hours: 2),
                       "DXBBB 60925 P105 2")
    }

    func testParkonicPlateForOtherEmirate() {
        let sharjahPlate = PlateProfile(emirate: .sharjah, letters: "A", number: "12345")
        XCTAssertEqual(sharjahPlate.parkonicPlate, "SHJA 12345")
    }

    func testParkinBodyUnchangedByRefactor() {
        XCTAssertEqual(ParkinRules.smsBody(plate: plate.parkinPlate, zone: "318C", hours: 2),
                       "BB60925 318C 2")
    }

    func testOperatorRouting() {
        XCTAssertEqual(ParkingOperator.parkin.smsNumber, "7275")
        XCTAssertEqual(ParkingOperator.parkonic.smsNumber, "6670")
        XCTAssertEqual(ParkingOperator.parkonic.smsBody(plate: plate, zone: "P105", hours: 1),
                       "DXBBB 60925 P105 1")
        XCTAssertEqual(ParkingOperator.parkin.smsBody(plate: plate, zone: "318C", hours: 1),
                       "BB60925 318C 1")
    }

    // MARK: - P-zone validation

    func testParkonicZoneValidation() {
        XCTAssertTrue(ParkonicRules.isValidZone("P105"))
        XCTAssertTrue(ParkonicRules.isValidZone("p105"))
        XCTAssertTrue(ParkonicRules.isValidZone("105"))
        XCTAssertFalse(ParkonicRules.isValidZone(""))
        XCTAssertFalse(ParkonicRules.isValidZone("P"))
        XCTAssertFalse(ParkonicRules.isValidZone("318C"))
        XCTAssertFalse(ParkonicRules.isValidZone("PABC"))
    }

    func testParkonicExtendIsBareYReply() {
        XCTAssertEqual(ParkonicRules.extendReply, "Y")
    }

    // MARK: - Community → operator mapping

    func testParkonicCommunities() {
        XCTAssertTrue(ParkonicRules.isParkonicCommunity(681), "JVC / Al Barsha South Fourth")
        XCTAssertTrue(ParkonicRules.isParkonicCommunity(626), "DSO / Nadd Hessa")
        XCTAssertTrue(ParkonicRules.isParkonicCommunity(591), "The Gardens / Jabal Ali First")
        XCTAssertFalse(ParkonicRules.isParkonicCommunity(318), "Al Karama stays Parkin")
        XCTAssertFalse(ParkonicRules.isParkonicCommunity(248), "Al Qusais stays Parkin")
    }

    func testParkonicCommunitiesExistInBundledPolygons() {
        let numbers = Set(ZoneLocator.communities.map(\.number))
        for community in ParkonicRules.communities {
            XCTAssertTrue(numbers.contains(community),
                          "Parkonic community \(community) must exist in the polygon dataset")
        }
    }

    // MARK: - Legacy plate migration

    func testLegacyPlateParsing() {
        let a = PlateProfile.parseLegacy("A44821")
        XCTAssertEqual(a.letters, "A"); XCTAssertEqual(a.number, "44821")
        let b = PlateProfile.parseLegacy("bb 60925")
        XCTAssertEqual(b.letters, "BB"); XCTAssertEqual(b.number, "60925")
        let c = PlateProfile.parseLegacy("60925")
        XCTAssertEqual(c.letters, ""); XCTAssertEqual(c.number, "60925")
    }

    func testMigrationFillsStructuredKeysOnce() {
        let defaults = UserDefaults(suiteName: "OperatorTests-\(UUID().uuidString)")!
        defaults.set("A44821", forKey: "plate")
        PlateStore.migrateIfNeeded(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "plateLetters"), "A")
        XCTAssertEqual(defaults.string(forKey: "plateNumber"), "44821")
        XCTAssertEqual(defaults.string(forKey: "plateEmirate"), "DXB")
        // Second run must not clobber user edits.
        defaults.set("B", forKey: "plateLetters")
        PlateStore.migrateIfNeeded(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "plateLetters"), "B")
    }

    func testPlateProfileFormats() {
        XCTAssertEqual(plate.parkinPlate, "BB60925")
        XCTAssertEqual(plate.parkonicPlate, "DXBBB 60925")
        XCTAssertTrue(plate.isComplete)
        XCTAssertFalse(PlateProfile(emirate: .dubai, letters: "A", number: "").isComplete)
    }
}
