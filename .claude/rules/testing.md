---
paths:
  - "Sources/**/*.{h,m}"
  - "Tests/**/*.swift"
---

# Testing

Tests come first and stay fixed while the code is written: an agent that may change a test will change it to get green.

- **New behaviour or a bug fix:** write the test first, from the requirement and not from the code. Use the `test-writer` subagent if you can start one. See it fail for the expected reason and commit it on its own, then write the code without touching it.
- **Refactor without a behaviour change:** tests stay unchanged. Nothing covers the code? Pin today's behaviour with a test first.
- **Never edit, skip or delete an existing test to make a change pass,** and never detect test inputs or hardcode answers. No `XCTSkip`, retries or longer timeouts to make a test pass. If a test looks wrong, stop and report `BLOCKED` with the reason. A test changes only when the required behaviour changed; say so in the PR.

## What needs what

| Code | Test |
|---|---|
| A decision or calculation (a backoff, a parser, a sanitizer, a header or URL a request gets) | a test of the class that decides, with every case in one test method or a loop over cases: `GleapEventPingTests` (backoff), `GleapNetworkLogSanitizerTests` |
| A request to the Gleap API and what the SDK does with the answer (retries, a refused identify, a grant) | a `GleapNetworkTestCase` subclass with `GleapStubURLProtocol` answering: `GleapGrantTests`, `GleapIdentityTests` |
| A message from or to the Messenger | the message the Messenger sends, posted from a page, and what the SDK did; or the message the SDK sends: `GleapProtectedFilesTests` (`open-protected-file`), `GleapEventStreamAndRoutingTests` (`session-update`), `GleapWebContentTrustTests` (which pages may use the bridge) |
| A delegate callback | `GleapDelegateSpy` (`Support/GleapNetworkTestCase.swift`): the payload and that it arrived on the main thread |
| Screens, gestures, the capture overlay | the decision behind it, moved into a class a test can call; say in the PR what only a run of the Example app showed |

Every new path that can drop, repeat or retry work gets a test: an answer that fails once, one that keeps failing, no network, a second call while the first runs, a logout in the middle.

## How tests are written

- XCTest in Swift, one file per class under test in `Tests/GleapTests`, `final class <What>Tests`, `@testable import Gleap`. Test names state the behaviour: `testAnIdentifyRefusedWithTokenExpiredKeepsTheSession`.
- Public API first. An internal class is reached through the Objective-C runtime, as `GleapUserJwtTests` does (`NSClassFromString`, `perform`, `value(forKey:)`); check the selector exists (`XCTUnwrap`) so a rename fails with a clear message.
- The network is always stubbed: `GleapStubURLProtocol` answers, and the test asserts the request it recorded (path, headers, body). Never the real API.
- No sleep decides a result. Wait with an `XCTestExpectation` or poll with a deadline, as `GleapGrantTests` does, and give the deadline room for a slow CI runner.
- Leave nothing behind: `setUp` and `tearDown` reset what the test changed (region, identity, `NSUserDefaults` keys, delegates). The suite shares one process and one simulator.
- Assert behaviour, not that code ran: the request that went out, the value stored, the callback with its payload.
- XCTest only: the shared helpers subclass `XCTestCase`, which Swift Testing cannot reuse. One framework in the target.

## What to run

- While you work: `make test-classes CLASSES="<the classes your change reaches>"`.
- Before you finish: `make lint-new` and those classes. CI runs the whole suite; locally only when no other session runs one (`AGENTS.md`).
- CI shows coverage per target in the job summary. Say in your report what no test reaches.

If no test reaches the code you changed, that is not a pass: say in your report what no test covered.
