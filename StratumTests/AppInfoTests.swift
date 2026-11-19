import XCTest
@testable import Stratum

@MainActor
final class AppInfoTests: XCTestCase {
    func testVersionComesFromTheBundleAndLooksLikeSemver() {
        XCTAssertNotEqual(AppInfo.version, "—")
        XCTAssertNotNil(AppInfo.version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression), AppInfo.version)
    }

    func testProjectLinksAreHTTPS() {
        for url in [AppInfo.author, AppInfo.repository, AppInfo.support] {
            XCTAssertEqual(url.scheme, "https")
            XCTAssertNotNil(url.host)
        }
    }

    func testUpdaterIsOnlyAvailableWhenTheBuildCarriesASigningKey() {
        let key = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? "")
            .trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(UpdateController.shared.isAvailable, !key.isEmpty)
    }
}
