import XCTest
@testable import Stratum

final class Milestone2Tests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("StratumM2Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        tempRoot = base
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    func testProtectedPathsGuardrail() {
        XCTAssertTrue(ProtectedPaths.isProtected("/"))
        XCTAssertTrue(ProtectedPaths.isProtected("/System"))
        XCTAssertTrue(ProtectedPaths.isProtected("/System/Library"))
        XCTAssertTrue(ProtectedPaths.isProtected("/Users"))
        XCTAssertTrue(ProtectedPaths.isProtected(FileManager.default.homeDirectoryForCurrentUser.path))
        XCTAssertFalse(ProtectedPaths.isProtected(tempRoot.path))

        // Attempting to move a protected path to Trash must fail without touching disk
        let outcome = DeleteService.moveToTrash([DeleteTargetItem(path: "/System", sizeBytes: 100)])
        XCTAssertTrue(outcome.removed.isEmpty)
        XCTAssertEqual(outcome.failed.count, 1)
    }

    func testTrashAndRestoreRoundtrip() throws {
        let testFile = tempRoot.appendingPathComponent("TrashRoundtrip.txt")
        let payload = Data("Hello Stratum Trash Undo".utf8)
        try payload.write(to: testFile)

        XCTAssertTrue(FileManager.default.fileExists(atPath: testFile.path))

        let outcome = DeleteService.moveToTrash([
            DeleteTargetItem(path: testFile.path, sizeBytes: Int64(payload.count))
        ])

        XCTAssertEqual(outcome.removed.count, 1)
        XCTAssertTrue(outcome.failed.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: testFile.path))

        let restoredCount = DeleteService.restoreFromTrash(outcome.trashURLs)
        XCTAssertEqual(restoredCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: testFile.path))
        let restoredData = try Data(contentsOf: testFile)
        XCTAssertEqual(restoredData, payload)
    }

    @MainActor
    func testCopyfileCloneAndConflictPolicies() async throws {
        let srcDir = tempRoot.appendingPathComponent("src", isDirectory: true)
        let dstDir = tempRoot.appendingPathComponent("dst", isDirectory: true)
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dstDir, withIntermediateDirectories: true)

        let srcFile = srcDir.appendingPathComponent("DesignSpec.pdf")
        let data1 = Data(repeating: 0x41, count: 64 * 1024)
        try data1.write(to: srcFile)

        // 1. Initial copy via TransferQueueEngine (<copyfile.h> with COPYFILE_CLONE)
        let exp1 = expectation(description: "First copy completes")
        TransferQueueEngine.shared.enqueueTransfer(
            kind: .copy,
            sourceURLs: [srcFile],
            to: dstDir,
            conflictPolicy: .keepBoth
        ) {
            exp1.fulfill()
        }
        await fulfillment(of: [exp1], timeout: 5.0)

        let copied1 = dstDir.appendingPathComponent("DesignSpec.pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copied1.path))
        XCTAssertEqual(try Data(contentsOf: copied1).count, data1.count)

        // 2. Second copy with .keepBoth should create "DesignSpec 2.pdf"
        let exp2 = expectation(description: "KeepBoth copy completes")
        TransferQueueEngine.shared.enqueueTransfer(
            kind: .copy,
            sourceURLs: [srcFile],
            to: dstDir,
            conflictPolicy: .keepBoth
        ) {
            exp2.fulfill()
        }
        await fulfillment(of: [exp2], timeout: 5.0)

        let copied2 = dstDir.appendingPathComponent("DesignSpec 2.pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copied2.path))

        // 3. Copy with .skip should leave existing file untouched and not create "DesignSpec 3.pdf"
        let exp3 = expectation(description: "Skip copy completes")
        TransferQueueEngine.shared.enqueueTransfer(
            kind: .copy,
            sourceURLs: [srcFile],
            to: dstDir,
            conflictPolicy: .skip
        ) {
            exp3.fulfill()
        }
        await fulfillment(of: [exp3], timeout: 5.0)

        let copied3 = dstDir.appendingPathComponent("DesignSpec 3.pdf")
        XCTAssertFalse(FileManager.default.fileExists(atPath: copied3.path))
    }
}
