import XCTest
@testable import MrCalenderCore

final class CommitAndNotificationTests: XCTestCase {
    func testFailedTimetableOperationDoesNotPublishAndShowsOnlyFailureBanner() throws {
        let original = AppSnapshot()
        var candidate = original
        try candidate.addTimetable(name: "新课表", events: [])
        var published = original
        var banners: [String] = []
        var writeCount = 0

        let succeeded = SnapshotOperationCoordinator.commit(
            candidate,
            successMessage: "导入成功",
            failureMessage: { "导入失败：\($0.localizedDescription)" },
            write: { _ in
                writeCount += 1
                throw CocoaError(.fileWriteOutOfSpace)
            },
            publish: { published = $0 },
            showBanner: { banners.append($0) }
        )

        XCTAssertFalse(succeeded)
        XCTAssertEqual(writeCount, 1)
        XCTAssertEqual(published, original)
        XCTAssertEqual(banners.count, 1)
        XCTAssertTrue(banners[0].hasPrefix("导入失败："))
        XCTAssertFalse(banners.contains("导入成功"))
    }

    func testSuccessfulTimetableOperationWritesOnceThenPublishesAndShowsSuccess() throws {
        var candidate = AppSnapshot()
        try candidate.addTimetable(name: "新课表", events: [])
        var steps: [String] = []

        let succeeded = SnapshotOperationCoordinator.commit(
            candidate,
            successMessage: "导入成功",
            failureMessage: { "导入失败：\($0.localizedDescription)" },
            write: { data in
                XCTAssertEqual(try SnapshotStore.decode(data), candidate)
                steps.append("write")
            },
            publish: { published in
                XCTAssertEqual(published, candidate)
                steps.append("publish")
            },
            showBanner: {
                XCTAssertEqual($0, "导入成功")
                steps.append("banner")
            }
        )

        XCTAssertTrue(succeeded)
        XCTAssertEqual(steps, ["write", "publish", "banner"])
    }

    func testFailedDeleteTimetableOperationKeepsTimetableAndShowsOnlyFailureBanner() throws {
        var original = AppSnapshot()
        let timetable = try original.addTimetable(name: "现有课表", events: [])
        var candidate = original
        candidate.removeTimetable(id: timetable.id)
        var published = original
        var banners: [String] = []

        let succeeded = SnapshotOperationCoordinator.commit(
            candidate,
            successMessage: "删除成功",
            failureMessage: { "删除失败：\($0.localizedDescription)" },
            write: { _ in throw CocoaError(.fileWriteOutOfSpace) },
            publish: { published = $0 },
            showBanner: { banners.append($0) }
        )

        XCTAssertFalse(succeeded)
        XCTAssertEqual(published, original)
        XCTAssertEqual(published.timetables.map(\.id), [timetable.id])
        XCTAssertEqual(banners.count, 1)
        XCTAssertTrue(banners[0].hasPrefix("删除失败："))
        XCTAssertFalse(banners.contains("删除成功"))
    }

    func testFailedImportCommitDoesNotPublishOrChangeStoredSnapshot() throws {
        let original = AppSnapshot()
        var candidate = original
        try candidate.addTimetable(name: "新课表", events: [])
        try assertFailedCommit(candidate, preserves: original)
    }

    func testFailedDeleteCommitDoesNotPublishOrChangeStoredSnapshot() throws {
        var original = AppSnapshot()
        let timetable = try original.addTimetable(name: "现有课表", events: [])
        var candidate = original
        candidate.removeTimetable(id: timetable.id)
        try assertFailedCommit(candidate, preserves: original)
    }

    private func assertFailedCommit(_ candidate: AppSnapshot, preserves original: AppSnapshot) throws {
        var published = original
        let storedData = try SnapshotStore.encode(original)
        var writeCount = 0
        var publishCount = 0
        XCTAssertThrowsError(try SnapshotStore.commit(candidate, write: { _ in
            writeCount += 1
            throw CocoaError(.fileWriteOutOfSpace)
        }, publish: {
            publishCount += 1
            published = $0
        }))
        XCTAssertEqual(published, original)
        XCTAssertEqual(try SnapshotStore.decode(storedData), original)
        XCTAssertEqual(writeCount, 1)
        XCTAssertEqual(publishCount, 0)
    }

    func testSuccessfulCommitWritesOnceBeforePublishingOnce() throws {
        var candidate = AppSnapshot()
        try candidate.addTimetable(name: "新课表", events: [])
        var steps: [String] = []
        var storedData: Data?
        try SnapshotStore.commit(candidate, write: {
            steps.append("write")
            storedData = $0
        }, publish: {
            steps.append("publish")
            XCTAssertEqual($0, candidate)
            XCTAssertEqual(storedData.flatMap { try? SnapshotStore.decode($0) }, candidate)
        })
        XCTAssertEqual(steps, ["write", "publish"])
    }

    @MainActor
    func testNotificationReplacementSerializesAndCoalescesToLatestIncludingEmptyQueue() async {
        let firstStarted = expectation(description: "First apply is suspended")
        let latestCompleted = expectation(description: "Latest empty queue applied")
        var releaseFirst: CheckedContinuation<Void, Never>?
        var started: [[PlannedReminder]] = []
        var applied: [[PlannedReminder]] = []
        var activeCalls = 0
        var maximumActiveCalls = 0
        let enabled = [PlannedReminder(id: "course", kind: .event, title: "课程", detail: "", date: Date())]
        let intermediate = [PlannedReminder(id: "intermediate", kind: .event, title: "课程", detail: "", date: Date())]
        let scheduler = LatestNotificationScheduler { reminders in
            activeCalls += 1
            maximumActiveCalls = max(maximumActiveCalls, activeCalls)
            started.append(reminders)
            if reminders == enabled {
                await withCheckedContinuation { continuation in
                    releaseFirst = continuation
                    firstStarted.fulfill()
                }
            }
            applied.append(reminders)
            activeCalls -= 1
            if reminders.isEmpty { latestCompleted.fulfill() }
        }

        scheduler.submit(enabled)
        await fulfillment(of: [firstStarted], timeout: 2)
        scheduler.submit(intermediate)
        scheduler.submit([])
        // Give independently launched tasks a chance to expose overlap while the first is held.
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(started, [enabled])
        releaseFirst?.resume()
        await fulfillment(of: [latestCompleted], timeout: 2)
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(maximumActiveCalls, 1)
        XCTAssertEqual(started, [enabled, []])
        XCTAssertEqual(applied, [enabled, []])
        XCTAssertEqual(activeCalls, 0)
    }

    func testPendingNotificationsAreClearedBeforeAuthorizationCheckWhenDenied() async {
        var steps: [String] = []

        await PendingNotificationReplacement.replace(
            ["course"],
            removeAllPending: { steps.append("clear") },
            isAuthorized: {
                XCTAssertEqual(steps, ["clear"])
                steps.append("authorization")
                return false
            },
            add: { _ in steps.append("add") }
        )

        XCTAssertEqual(steps, ["clear", "authorization"])
    }

    func testAuthorizedPendingNotificationReplacementClearsThenAddsInOrder() async {
        var steps: [String] = []

        await PendingNotificationReplacement.replace(
            ["first", "second"],
            removeAllPending: { steps.append("clear") },
            isAuthorized: {
                steps.append("authorization")
                return true
            },
            add: { steps.append("add:\($0)") }
        )

        XCTAssertEqual(steps, ["clear", "authorization", "add:first", "add:second"])
    }
}
