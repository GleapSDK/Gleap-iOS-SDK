---
paths:
  - "Sources/**/*.{h,m}"
---

# Code conventions

For new files and the code you change; do not rewrite other code to match. Copy the examples below, not your neighbours: `GleapCore.m`, `GleapSessionHelper.m` and the capture files are far over every limit. `make lint-new` checks the mechanical part on what your branch adds; the rest is on you and the review.

Sources: [Programming with Objective-C](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/ProgrammingWithObjectiveC/), [Coding Guidelines for Cocoa](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CodingGuidelines/CodingGuidelines.html) (naming), [Designating nullability](https://developer.apple.com/documentation/swift/designating-nullability-in-objective-c-apis), [Improving Objective-C API declarations for Swift](https://developer.apple.com/documentation/swift/improving-objective-c-api-declarations-for-swift).

- **Size:** aim for files under 400 lines and never write a new one over 700 (`make lint-new`); methods under 80 lines. A file over 700 lines must not grow: new logic goes into a new class in `Sources/Internal` that the big file calls.
- **Where:** a new class goes to `Sources/Internal`, imports `GleapInternal.h` and has `GLEAP_INTERNAL` before its `@interface`. `Sources/ObjCSources` only for what apps must call (Public API in `AGENTS.md`). One class per `.h`/`.m` pair named `Gleap<What>`; a category `<Class>+<Topic>`.
- **Nullability:** every new header between `NS_ASSUME_NONNULL_BEGIN` and `NS_ASSUME_NONNULL_END`, `nullable` wherever nil is possible. Never pass a nullable value where nonnull is required; check it first (`-Wnullable-to-nonnull-conversion` in `make lint-new`). A nil in a dictionary or array literal crashes the app: `GleapObjectOrNull(value)` or a check.
- **Properties:** `nonatomic`; `copy` for strings, collections and blocks; `weak` for delegates. Readonly in the header, readwrite in the class extension; private state in the class extension of the `.m`, never ivars in a header.
- **Blocks:** a block the object keeps (a property, a timer, an observer, a pending completion) captures `__weak typeof(self) weakSelf = self;` and makes it strong inside. No `_ivar` inside a block: it retains `self` without saying so (`CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF` in `make lint-new`).
- **Threads:** UIKit and the web views only on the main thread. A completion or delegate call the app receives runs on the main queue unless its header says otherwise. Shared state: `@synchronized (self)` or one serial queue, next to the fields it guards, as in `GleapGrant`; singletons with `dispatch_once`.
- **Failures:** never `@throw`, `NSAssert` or force a crash in shipped code: an exception takes the app down. A call that can fail completes with an `NSError * _Nullable` or returns nil and logs. Every value from JSON gets an `isKindOfClass:` check before use.
- **Logging:** `NSLog(@"[GLEAP_SDK] ...")` only for what an app developer must act on, never per request or event. Never tokens, user data or bodies (`AGENTS.md`, Security).
- **Constants:** `static NSString * const kGleap...` in the `.m`; a closed set of values is an `NS_ENUM` or `NS_TYPED_ENUM`. Strings that reach the server, the Messenger or `NSUserDefaults`: add values, never rename one.
- **Public headers** (Swift reads them, see `make api-check`): lightweight generics on collections (`NSArray<NSString *> *`), `NS_SWIFT_NAME` when the imported name reads badly, a `///` doc comment that says what the call does for the app and on which thread callbacks arrive.
- **Comments:** a `///` doc comment on every method in a header. Other comments say why, in English, in one or two lines. No ticket or PR numbers, people's names, dates or decision histories: those belong in the PR.
- **Dependencies:** none. No pod, package or linked framework without asking first; a framework goes into `Package.swift` and the podspec together.
- **Formatting:** files you add follow `.clang-format` (the edit hook formats them, `make lint-new` checks them). In old files, match the lines around your change.

## One job, one system

| Job | Use | Not in new code |
|---|---|---|
| Requests to the Gleap API | `GleapAPIClient` (identity headers, grant, completion on the main queue) | an own `NSURLSession` or request setup |
| Identity and session | `GleapSessionHelper`, `GleapGrant`, `GleapUserJwt` | reading `gleapId` or `gleapHash` from `NSUserDefaults` elsewhere |
| Web views (Messenger, banner, modal) | `GleapWebViewSupport` (configuration, bridge, same-origin check) | a `WKWebView` configured by hand |
| Messages to a page | `sendMessage:toFunction:inWebView:onlyOnPage:` | `evaluateJavaScript:` with JavaScript built from strings |
| Retry and backoff | a schedule in its own class, as `GleapPingBackoff` | delays and retry counters spread over a caller |
| Tests | XCTest | Swift Testing, OCMock, Quick/Nimble |

## Examples to copy

- A small internal class whose decisions are testable from outside, documented in its header: `Sources/Internal/GleapPingBackoff.h/.m`, tested in `GleapEventPingTests`.
- Requests: `Sources/Internal/GleapAPIClient.h/.m`.
- State guarded by a lock and persisted in `NSUserDefaults`: `Sources/Internal/GleapGrant.h/.m`.
