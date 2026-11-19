---
paths:
  - "Sources/**"
  - "Package.swift"
  - "Gleap.podspec"
---

# Code that runs inside the app

The SDK runs in other companies' apps, on devices we never see, for years after a release. A crash, a hang or a leak is the app's crash, hang or leak, and the app's App Store review.

## Never take the app down

- No exception, `NSAssert` or force unwrap of a value from the server, the Messenger or `NSUserDefaults`: check `isKindOfClass:` and nil, and fall back to doing nothing. Old versions of the Messenger and the server answer too.
- Nothing slow on the main thread: no synchronous network or file work there. `initialize` runs during the app's launch, so what it does directly stays small.
- Every timer, observer and socket the SDK starts has an owner that stops it when it is no longer needed (a logout, the Messenger closing) and holds `self` weakly.

## Changes to system classes

The SDK swizzles `viewDidAppear:` and `viewDidDisappear:` (`UIViewController+GleapViewControllerHelper`), replaces `NSURLSession` and `NSURLSessionTask` methods (`GleapHttpTrafficRecorder`) and overrides touch and motion handling in `UIWindow` categories. Every app's own code runs through them.

- No new swizzling or category override of a system method without asking.
- A replaced method always calls the original, with the same arguments, on the same thread, also when the SDK is not initialized or the feature is off, and adds no work beyond a flag check while it is off.

## The Messenger and the other web views

- Messages between the SDK and the Messenger (`name` plus `data`) are a protocol between two things that deploy separately. Add a message or a field; never rename or remove one, or change its meaning. A new feature the Messenger may use is announced in `session-update`'s capabilities, so the Messenger knows which SDKs have it.
- The session (grant, user) goes only to a page of the Messenger's origin, and only its messages are evaluated (`GleapWebViewSupport`). Other main-frame navigations open in Safari. Do not widen this.
- Changing a message: stop and ask, and name the Messenger change it needs.

## Privacy

- `Sources/PrivacyInfo.xcprivacy` ships to every app, and App Store Connect refuses an app whose SDKs use an API from Apple's [required-reason list](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) without declaring it. Declared today: user defaults (`CA92.1`) and system boot time (`35F9.1`). A new use of user defaults, boot time (`systemUptime`, `mach_absolute_time`), disk space, file timestamps or active keyboards, or new data the SDK collects: stop and ask, the manifest changes with it.
- Collect only what the app turned on (network logs, console logs, screenshots, replays) and what the docs list. Network logs pass `GleapNetworkLogSanitizer` before they leave the device.
- Nothing about the user in logs; ids and counts only.

## State that survives an update

- `NSUserDefaults` keys (`gleapId`, `gleapHash`, `gleapGrant`, `gleapGrantId`, `gleapGrantExp`, `gleapCaptureDeviceId`) and the files under `Caches/gleap-files` are read by the next SDK version. Never rename a key or change what it holds; add a new key and read the old one too.
- `clearIdentity` removes everything that belongs to the user: keys, tokens in memory, downloaded files.

## Both package managers

`Package.swift` (SPM) and `Gleap.podspec` (CocoaPods) ship the same SDK. A linked framework or library, a resource or a new source type goes into both, and both are a stop-and-ask change. CI's `pod lib lint` builds the pod; SPM builds in the tests.
