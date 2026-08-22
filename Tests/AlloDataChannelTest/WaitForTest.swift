import XCTest
@preconcurrency import OpenCombineShim
@testable import AlloDataChannel

private final class Box: @unchecked Sendable { @Published var value = 0 }

/// `waitFor` used to turn a timeout into a process-wide hang: the task group cancelled a
/// child suspended in a continuation that ignored cancellation. These pin the three
/// behaviours a replacement must keep.
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
