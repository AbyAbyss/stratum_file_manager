import XCTest
@testable import Stratum

final class WallpaperLocatorTests: XCTestCase {
    private let support = URL(fileURLWithPath: "/tmp/wallpaper-support", isDirectory: true)

    private func store(choice: [String: Any], slot: String = "Linked") throws -> Data {
        let root: [String: Any] = ["AllSpacesAndDisplays": [slot: ["Content": ["Choices": [choice]]]]]
        return try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
    }

    func testAerialWallpaperResolvesToItsThumbnail() throws {
        let config = try PropertyListSerialization.data(fromPropertyList: ["assetID": "ABC-123"], format: .binary, options: 0)
        let data = try store(choice: ["Provider": "com.apple.wallpaper.choice.aerials", "Files": [], "Configuration": config])
        XCTAssertEqual(
            WallpaperLocator.imageURL(fromStore: data, supportDirectory: support)?.path,
            "/tmp/wallpaper-support/aerials/thumbnails/ABC-123.png"
        )
    }

    func testPictureWallpaperResolvesToItsFile() throws {
        let data = try store(choice: ["Files": [["relative": "file:///Users/me/Pictures/hills.jpg"]]], slot: "Desktop")
        XCTAssertEqual(WallpaperLocator.imageURL(fromStore: data, supportDirectory: support)?.path, "/Users/me/Pictures/hills.jpg")
    }

    func testUnreadableStoreGivesNothing() {
        XCTAssertNil(WallpaperLocator.imageURL(fromStore: Data("not a plist".utf8), supportDirectory: support))
    }
}
