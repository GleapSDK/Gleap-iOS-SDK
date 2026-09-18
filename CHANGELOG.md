## 18.0.0

* **Breaking:** minimum deployment target is now iOS 15.0 (Xcode 27 no longer builds for anything lower).
Added data regions: `Gleap.setRegion("us")` (call before `initialize`) points the SDK at the US data region by setting the api url, the websocket api url and the realtime host at once. The default region stays `eu`, existing integrations are unaffected.
Added `setRealtimeHost`, `setBannerUrl` and `setModalUrl` to customize the remaining hosts. Manual setters called after `setRegion` override that single host.
The realtime host is now passed to the widget with the session update (`realtimeHost`), matching the JavaScript SDK.
The static widget hosts (frame, banner & modal url) are global and are not changed by `setRegion`.
