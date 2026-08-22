import XCTest
@preconcurrency import OpenCombineShim
@testable import AlloDataChannel

private final class Box: @unchecked Sendable { @Published var value = 0 }

/// `waitFor` must time out, honour cancellation, and return immediately when already
/// satisfied - a continuation inside a task group can hang the whole process instead.
final class WaitForTests: XCTestCase
{
    func testTimeoutThrowsInsteadOfHanging() async throws
    {
        let box = Box()
        let started = Date()
        do {
            try await box.$value.waitFor(value: 1, timeout: 0.2)
            XCTFail("must time out")
        } catch PublisherError.timedOut {}
        XCTAssertLessThan(Date().timeIntervalSince(started), 2, "timed out, but only after the group hung")
    }

    func testAlreadyMatchingValueResolvesImmediately() async throws
    {
        let box = Box()
        box.value = 7
        try await box.$value.waitFor(value: 7, timeout: 0.2)
    }

    func testValuePublishedFromAnotherThreadResolves() async throws
    {
        let box = Box()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { box.value = 3 }
        try await box.$value.waitFor(value: 3, timeout: 2)
    }

    func testCancellationReleasesTheWaiter() async throws
    {
        let box = Box()
        let task = Task { try await box.$value.waitFor(value: 1, timeout: 10) }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        let started = Date()
        _ = await task.result
        XCTAssertLessThan(Date().timeIntervalSince(started), 2, "cancel must release the suspended waiter")
    }
}
