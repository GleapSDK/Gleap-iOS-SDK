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
