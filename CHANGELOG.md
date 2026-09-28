## 18.2.0
Added dark / light mode support for the widget. The widget colors now follow the color scheme set in the dashboard (`colorScheme`: default, auto, light, dark) or at runtime:
`Gleap.setColorScheme("auto")` follows the app's interface style (the system appearance, or the app's own `overrideUserInterfaceStyle`) and switches live when it changes. `"light"` / `"dark"` force a scheme, `"default"` removes the runtime override so the dashboard setting applies again. `setColorScheme` only takes effect when "Adapt to dark / light mode" is enabled in the dashboard; otherwise the widget keeps its normal colors.
Light mode uses the widget colors from the dashboard. Dark mode uses the dark colors set in the dashboard (header colors, UI color and background); a dark color that is not set keeps the normal one. Dark mode also uses the dark logo, header background image and composer glow set in the dashboard. Without dark colors the widget keeps its normal colors, also in dark mode. The backgrounds can be overridden via `Gleap.setColorScheme("auto", lightBackgroundColor: "#ffffff", darkBackgroundColor: "#121212")`. Button colors are unchanged. The widget, its loading screen, notifications and modals follow the scheme, including ones that are already showing.
Can be called before or after `initialize`.

Network logs now cover every NSURLSession request of the app. Until now only requests created with a completion handler were logged, so Swift async/await (`URLSession.data(for:)`, `upload(for:from:)`, `bytes(for:)`) and delegate-based clients such as Alamofire, Moya, Apollo or AFNetworking were missing unless their session configuration was registered with `startNetworkRecording(for:)`, which is no longer needed (it now behaves like `startNetworkRecording()`). Each request is logged with method, URL, request headers and body, status, response headers, duration and, for failures and cancellations, the error. Response bodies are kept for completion handler and delegate-based requests; async/await hands the data to the caller internally, so those requests are logged without the response body. Text bodies are kept up to 150 KB (longer ones are truncated and marked), binary and streaming bodies (images, `text/event-stream`) are replaced by a marker instead of being held in memory. Requests are timed from their start, the log keeps the last 30 requests (was 10) and requests still running when a report is sent show up as pending. The SDK's own requests to Gleap no longer take up the log, and bodies passed to `uploadTask(with:from:)` are included. The Gleap Moya plugin is no longer needed; while it is still installed, requests it attaches that the SDK logged itself are left out, so nothing is listed twice.

Network log filtering (`networkLogPropsToIgnore` from the dashboard and `Gleap.setNetworkLogPropsToIgnore`) now matches header names case-insensitively, removes keys at any depth of JSON bodies (a prop with dots such as `user.password` also removes that path) and removes matching form fields and URL query parameters. In a JSON body that no longer parses because it was cut at the 150 KB limit, the values of those keys are replaced by `[REDACTED]`. The values of the `Authorization`, `Proxy-Authorization`, `Cookie` and `Set-Cookie` headers are always replaced by `[REDACTED]`. Network logs attached by the React Native, Flutter and Capacitor SDKs go through the same filters and are sent even when native recording is off.

Console logs capture the app's stdout and stderr again, now on iOS 15+ and in debug builds too: `print()`, `NSLog` (which the unified log only stores as `<private>`) and anything else written to the standard streams, while the output still reaches the Xcode console. os_log / Logger messages are read from the unified log as before, but now the most recent ones (the reader kept the oldest 300 entries since launch), with errors and faults marked as errors and `<private>` placeholders left out. `Gleap.enableDebugConsoleLog()` is no longer needed. Log dates are UTC with milliseconds, independent of the device's calendar and 12/24-hour setting (a non-Gregorian calendar produced dates the server dropped). Conversations always include the captured console output, even when reading the unified log takes longer than the widget waits. Inside the Capacitor SDK, Capacitor's own copies of the WebView console (`⚡️  [log] - ...`) are left out, since the Capacitor plugin records the WebView console itself. Data attached by the React Native, Flutter and Capacitor SDKs is now read and written under a lock (a report built while a wrapper attached new logs could crash).

Reports only count as sent once the server accepted them. A report the server rejects (for example because it is too large) now calls `feedbackSendingFailed` and shows the error in the widget, where it used to call `feedbackSent` and `outboundSent` for a ticket that was never created. When the server is momentarily overloaded (503), a report and its uploads are sent once more after the delay the server asks for (at most 5 seconds). An attachment upload that was rejected, or whose answer does not list every uploaded file, no longer crashes the app; the report is sent without the attachments.

A failed request no longer costs the user their identity. When a session start, `identify` or `updateContact` met an overloaded server or a server error, or `updateContact` was refused (for example because the request was too large), the SDK could delete the stored guest or user identity, so the user continued as a new guest without their conversations. Only an answer that contains a session replaces the stored identity now. An `identify` the server refuses with an error (for example because of a wrong user hash) still starts a new guest session, as before.

Custom actions from banners now reach the app the same way as those from modals: `customActionCalled(_:withShareToken:)` when the delegate implements it, otherwise `customActionCalled(_:)`. A banner action used to crash apps whose delegate implements `customActionCalled(_:)` (the Flutter plugin) and never reached apps that only implement the two-argument version (React Native, Capacitor).

A closed widget, banner or modal is released again, together with its web view and web content process. Each one used to stay in memory until the app quit, because its web view kept it alive.

The realtime connection no longer reconnects every 5 seconds after the session changed (for example after `identify`), and all connections share one URL session instead of creating a new one per attempt. Realtime messages are now handled on the main queue, like the answers to the event stream.

Replays keep recording after the app returns from the background or the config is loaded again; until now they stopped for good the first time either happened.

Restarting the session (for example on `identify`) no longer adds another page tracking timer each time.

`identifyContact` (and `identifyUserWith`) without user data and `updateContact(nil)` no longer crash; the header always declared the data optional.

Opening the widget before the app has a window to show it on no longer leaves the SDK thinking the widget is open, which blocked every later attempt to open it and kept the feedback button hidden.

Links in modals that are not web links (`tel:`, `sms:`, links into other apps) no longer crash the app; they open in the app that handles them.

The widget, banners and modals only accept messages from their own page: the main frame of the configured frame, banner or modal URL. Content embedded in help articles, news or banners (for example a third-party iframe) can no longer open links, run custom actions or agent tools, or send tickets through the SDK.

Banners only grant camera and microphone access without asking to their own page; any other origin gets the system prompt. They used to grant it to any origin, including embedded third-party content.

Custom data, ticket attributes, tags, attachments, prefilled form data, the session and the commands waiting for the widget are now read and written under a lock, so they can be changed from any thread (as the wrappers do) while a report is built or the widget opens; this could crash with "Collection was mutated while being enumerated".

`configLoaded` and `initialized` now arrive on the main thread, once per `initialize` call. A session recovery (opening the widget after an offline start) no longer reports them a second time; if the config had not loaded before, the recovery reports them instead. Calling `initialize` again with the same API key, as a reloaded JavaScript context does (a React Native reload or over-the-air update, a Capacitor WebView reload), no longer starts another session or loads the config again: once the config has loaded, the delegate set at that point gets `configLoaded` with the loaded config and then `initialized`; before that, the first config load reports to it. With a different key the SDK starts over as before.

`openChecklist`, `startChecklist` and `sendSilentCrashReport` no longer crash when an Objective-C caller passes nil for the checklist id, the description or the completion block.

Touches and motion events (such as a shake) that reach the app's window are now passed on along the responder chain, to the application and its delegate. The SDK's `UIWindow` category used to handle them without passing them on.

A feedback button that is created again (for example after the app switched its key window) no longer gets a layout constraint that ties the button to itself.

The SDK no longer adds a second feedback button when the config arrives while it is still setting up its overlay. The extra button sat underneath the real one without a notification badge, and stayed on screen after `showFeedbackButton(false)` hid the real one.

## 18.1.0
Added control over the env data (device, OS, screen, locale and battery details shown under the Env data tab of a ticket) the SDK collects:
`Gleap.setEnvDataPropsToIgnore(["deviceName", "batteryLevel"])` removes individual env data keys from every ticket and conversation before it is sent. Each call replaces the previous list; an empty array resets it.
`Gleap.setDisableEnvData(true)` stops collecting env data entirely (tickets arrive with an empty Env data tab); `Gleap.setDisableEnvData(false)` turns it back on.
Both can be called before or after `initialize` and apply to the next ticket. The per-form "Exclude data → Env data" switch in the dashboard keeps working as before.

## 18.0.0

* **Breaking:** minimum deployment target is now iOS 15.0 (Xcode 27 no longer builds for anything lower).
Added data regions: `Gleap.setRegion("us")` (call before `initialize`) points the SDK at the US data region by setting the api url, the websocket api url and the realtime host at once. The default region stays `eu`, existing integrations are unaffected.
Added `setRealtimeHost`, `setBannerUrl` and `setModalUrl` to customize the remaining hosts. Manual setters called after `setRegion` override that single host.
The realtime host is now passed to the widget with the session update (`realtimeHost`), matching the JavaScript SDK.
The static widget hosts (frame, banner & modal url) are global and are not changed by `setRegion`.
