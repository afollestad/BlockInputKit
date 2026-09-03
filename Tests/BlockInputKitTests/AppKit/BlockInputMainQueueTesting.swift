import Foundation
import XCTest

/// Waits for main-queue work the code under test deferred to the next main-loop turn.
///
/// The main queue is FIFO, so a block enqueued here runs only once every block
/// enqueued earlier has. Waiting on it keeps deferred-effect assertions
/// independent of how long a loaded machine takes to service the run loop,
/// which a fixed `RunLoop.run(until:)` deadline cannot promise.
/// Only one main-queue hop is awaited, and it settles the queue rather than AppKit's
/// update cycle, so a chained effect, a delayed one, or state computed in `viewDidLayout`
/// needs its own signal.
@MainActor
func waitForNextMainLoopTurn(file: StaticString = #filePath, line: UInt = #line) {
    let turn = XCTestExpectation(description: "next main loop turn")
    DispatchQueue.main.async {
        turn.fulfill()
    }

    XCTAssertEqual(
        XCTWaiter.wait(for: [turn], timeout: 5),
        .completed,
        "Timed out waiting for the next main loop turn.",
        file: file,
        line: line
    )
}
