# Gleap iOS SDK

The `Gleap` library apps embed for the Messenger (chat, help center, news, checklists), banners, modals, surveys, bug reports with screenshots, screen recordings and network and console logs, and the capture of what the Messenger asks for. Objective-C only (`Sources/`, about 22,800 lines); the tests are Swift (XCTest); no dependencies. iOS 15 and later.

- `Sources/ObjCSources`: **every header here is public** (`publicHeadersPath` in `Package.swift`, `public_header_files` in the podspec); `Gleap.h` is the umbrella header, `GleapCore.h` the `Gleap` class apps call. Never add a subfolder: SPM rejects a public header directory with folders next to `Gleap.h`.
- `Sources/Internal`: code apps cannot see. Classes are marked `GLEAP_INTERNAL` (hidden symbols, `GleapInternal.h`).
- `Sources/PrivacyInfo.xcprivacy`: the SDK's privacy manifest, shipped in the `Gleap` resource bundle.
- `Tests/GleapTests`: the XCTest target of `Package.swift`; `Support/` has the network stub (`GleapStubURLProtocol`) and the base class for tests that talk to the API (`GleapNetworkTestCase`).
- `Example/`: a demo app that uses the package from this folder. Not built by CI.

The SDK shows the Messenger and other web views (the Messenger-App repo) and talks to them through `WKScriptMessageHandler` messages (`session-update`, `open-url`, `capture-start`, ...). The Messenger deploys on its own, so every SDK version still in apps talks to today's Messenger. Terms, as in the Server: a conversation is a ticket, the end user is a session, the project's key is the Project ID (formerly API key or SDK key).

How it ships: a tag `X.Y.Z` runs `.github/workflows/release.yml`, which checks that it equals `s.version` in `Gleap.podspec` and that `CHANGELOG.md` has a `## X.Y.Z` section, runs the tests, pushes the pod to CocoaPods trunk and creates the GitHub release. Swift Package Manager reads the tag directly. Apps and the Flutter and React Native SDKs pin a version, so old versions stay out there for years.

## Commands

```bash
make hooks                                    # once per clone: git push runs scripts/lint-new.sh (.githooks/pre-push)
make test-classes CLASSES="GleapGrantTests"   # only these XCTest classes, on a simulator: about 1.5 min cold
make lint-new                                 # what this branch adds compared with origin/main (below): about 30 s
make api-check                                # the public API compared with origin/main (part of lint-new)
make analyze                                  # every compiler and analyzer warning, old code included: for reading only
make test                                     # the whole suite, as CI runs it (.github/scripts/test.sh)
sh scripts/clang-format.sh -i <new file>      # the pinned clang-format, for files this branch adds
LANG=en_US.UTF-8 pod lib lint Gleap.podspec --allow-warnings   # the pod builds (CI runs it)
```

Needs Xcode (`xcodebuild`, `xcrun`), `jq` and `python3`; `scripts/clang-format.sh` installs the pinned clang-format into `build/tools` on first use. Nothing else to install.

`make lint-new` judges only what the branch adds (committed, uncommitted and untracked): compiler and static analyzer warnings on the lines it adds or changes in `Sources/` (with nullability and implicit-self warnings the shipped build does not turn on), clang-format on the `.h` and `.m` files it adds (old files keep their own style and are never reformatted), files over 700 lines that grew, and a removed or changed public API. A warning on a line you change counts as yours: fix it with the change. Exit 1 means problems, 3 that a check could not run.

**Simulators are shared.** Several sessions share this machine, the simulators and their `NSUserDefaults`, which the tests write. Run only the test classes your change reaches (`make test-classes`), never the whole suite while another one may run; CI runs it on every PR.

CI (`.github/workflows/ci.yml`) runs the whole suite on a simulator with a coverage summary, and `pod lib lint`, on every PR and push to `main`. `.github/workflows/quality.yml` runs `scripts/lint-new.sh` on PRs with the base branch's copy of `scripts/` and `.clang-format`, on a fixed image and Xcode (`macos-26`, Xcode 26.6).

Done means `make lint-new` and the test classes that reach your change pass, and CI is green. Say which commands you ran and what they printed. The stop hook runs `scripts/lint-new.sh` and the test classes it can match (a changed test file, `<Name>Tests` for a changed `<Name>.m`); name the others yourself.

New worktree: `make hooks` once per clone is all it needs. `build/` (results, tools, analyzer output) is ignored.

`git push` runs `scripts/lint-new.sh` on your branch (`.githooks/pre-push`). Agents fix what it reports and push again; they never use `--no-verify`.

## Code

New files and the code you change follow `.claude/rules/code-conventions.md`, code that runs in the app follows `.claude/rules/host-app.md`, and tests follow `.claude/rules/testing.md`. Read them before your first edit: old code here is no precedent.

## Public API

Everything an app or a wrapper SDK can call or rely on is public: every class, method, property, constant, enum and protocol in `Sources/ObjCSources/*.h`, how it behaves, its defaults and the thread its callbacks arrive on, and the `GleapDelegate` callbacks. The Flutter SDK and the React Native SDK call `Gleap`, `GleapUserProperty`, `GleapDelegate` and the enums.

- **Never remove, rename or change any of it in a minor or patch version.** `make api-check` fails on a removed or changed declaration. Add instead: a new method, an optional parameter through a new method, a new delegate method marked `@optional`.
- **Deprecate, don't delete:** keep the behaviour, mark it `__attribute__((deprecated("Use ... instead")))` and say so in `CHANGELOG.md`. Removal needs a major version, a product decision: stop and ask.
- **A change to the API updates `CHANGELOG.md` (`## Unreleased`) and, for a new call, `README.md` in the same PR.** Doc comments on public headers say what a call does, from the app's side.
- **New behaviour is opted into:** from a dashboard setting or a new call, never because the SDK was updated. A missing setting keeps today's behaviour.
- A public header added to `Sources/ObjCSources` is public for good: new classes go to `Sources/Internal` unless apps must call them.

## Security

- **Code runs inside other companies' apps.** Never log, send or keep the app's data beyond what the SDK documents: no request or response bodies outside the network log the app turned on (`GleapNetworkLogSanitizer` applies), no keychain access, no reading other apps' data.
- **Tokens and identity.** The user JWT (`setUserJwt`) and the auth tokens (`setAuthTokens`) stay in memory; the grant, `gleapId` and `gleapHash` are the only identity in `NSUserDefaults`. Never log any of them; log ids and counts.
- **Web content.** The session (grant, user) goes only to a page of the Messenger's origin, and only its messages are evaluated (`GleapWebViewSupport`); other main-frame navigations open in Safari. Protected files are fetched only from the files host of the configured region, with the file session as the only credential. Do not widen either.
- **Privacy manifest.** A new use of an API in Apple's required-reason list (user defaults, system boot time, disk space, file timestamps, active keyboards) needs its category and reason in `Sources/PrivacyInfo.xcprivacy`, and new collected data its entry: stop and ask. The manifest ships to every app.

## Traps

- `Package.swift` and `Gleap.podspec` both describe the shipped SDK and must agree: a framework or library the SDK links goes into `linkerSettings` and `s.frameworks`/`s.libraries`; a resource into `resources` and `s.resource_bundles`. Every file under `Sources/` with `.h`, `.m` or `.c` ships through CocoaPods (`Sources/**/*.{h,m,c}`); SPM builds everything under `Sources/`.
- `.github/scripts/test.sh` is also the test step of `release.yml`: changing it changes releases.
- Swift tests cannot import `Sources/Internal`. Tests reach internal classes through the Objective-C runtime (`NSClassFromString`, `perform`, `value(forKey:)`, as `GleapUserJwtTests` does): a renamed selector fails only when the test runs.
- `.github/scripts/test.sh` and `make test-classes` use the last iPhone simulator in `simctl list`: two runs at once share it and its `NSUserDefaults`.
- `NSUserDefaults` keys (`gleapId`, `gleapHash`, `gleapGrant`, `gleapGrantId`, `gleapGrantExp`, `gleapCaptureDeviceId`) hold a returning user's session: renaming one logs every user out on update.
- The SDK changes system classes inside the app: `UIViewController+GleapViewControllerHelper` swizzles `viewDidAppear:` and `viewDidDisappear:`, `GleapHttpTrafficRecorder` replaces `NSURLSession` and `NSURLSessionTask` methods to log network traffic, and the `UIWindow` categories override touch and motion handling. A mistake there breaks the app, not only the SDK.
- `GleapCore.m`, `GleapSessionHelper.m`, `GleapCaptureOverlay.m` and `GleapCaptureManager.m` are far over every size limit; new logic goes into new files in `Sources/Internal`.
- Xcode or `swift package` may create `.swiftpm/` in the repository root; do not commit it.
- `CHANGELOG.md` must have a `## X.Y.Z` section before a release tag, or `release.yml` fails.

## Tests

New behaviour and bug fixes start with a test that fails; refactors leave tests unchanged. Full rules: `.claude/rules/testing.md`.

- XCTest in `Tests/GleapTests`, Swift, `@testable import Gleap`. Network through `GleapStubURLProtocol` and `GleapNetworkTestCase`, never the real API.
- No sleep decides a result: wait for an expectation or poll with a deadline.
- Never edit, skip or delete an existing test to make a change pass. If one looks wrong, stop and report `BLOCKED` with the reason.

## Customer requests

A ticket is one customer's view, a bug report too. Before changing anything for it:

- **A feature or a change:** decide whether it is right for the product. Would most customers want it, or does it belong behind a setting every customer can use?
- **A bug report:** first check whether the code does something other than intended, from its tests, comments, docs and history. If it works as designed and the customer expected something else, it is not a bug: change nothing, and say so in your report. Changing intended behaviour is a product decision: stop and ask.
- **Never special-case one customer in code:** no project, organisation or user ids, app bundle ids, names or domains in conditions. If the only fix that works is specific to one customer, stop and ask.

## Stop and ask

Keep going while a step needs no input. Stop and ask before: releasing (a version in `Gleap.podspec`, a tag, a CocoaPods push, a GitHub release), changing `Package.swift`, `Gleap.podspec`, `Sources/PrivacyInfo.xcprivacy` or the minimum iOS version, adding a dependency or a linked framework, removing or changing anything public (above), changing a message the SDK and the Messenger exchange, adding swizzling or another change to a system class, or changing `.github/workflows/release.yml` or `.github/scripts/test.sh`.

## Production

Merging to `main` ships nothing: apps get the SDK when a human pushes a version tag and they update. A tag cannot be taken back once CocoaPods and SPM resolved it: a broken release is fixed by a new version. Only a human releases.
