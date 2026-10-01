//
//  GleapCaptureManager.h
//  Gleap
//
//  Capture requests ("Show me the issue"): screenshots and screen recordings the Messenger asks the app
//  for (capture-start / capture-cancel / capture-done over the widget bridge) and logs the server asks
//  for in the background (capture-request on the SDK websocket, `cr` in the ping answer). Nothing runs,
//  observes or allocates until a request arrives. Main thread unless noted.
//

#import <UIKit/UIKit.h>
#import "GleapInternal.h"
#import "GleapCore.h"

NS_ASSUME_NONNULL_BEGIN

GLEAP_INTERNAL
@interface GleapCaptureManager : NSObject

+ (instancetype)sharedInstance;

/// Deletes what captures of an earlier run left behind (the app ended mid-capture). Once at SDK start, any thread.
+ (void)removeLeftoverFiles;

#pragma mark Settings (any thread)

/// Screenshots and recordings for the widget (default YES). Off: the widget offers file uploads only.
@property (atomic, assign) BOOL captureEnabled;
/// Background log collection for the support team (default YES). Off: logs requests are answered `unsupported`
/// and logs are not attached to captures.
@property (atomic, assign) BOOL remoteLogCollectionEnabled;
/// Lets a wrapper SDK push its buffered logs before logs are collected.
@property (atomic, copy, nullable) GleapLogFlushHandler logFlushHandler;

- (void)maskView:(UIView *)view;
- (void)unmaskView:(UIView *)view;
/// The masked views that still exist. Main thread.
- (NSArray<UIView *> *)maskedViews;

#pragma mark Capabilities (any thread)

/// What this SDK supports: `capture.screenshot`, `capture.recording`, `capture.logs` (websocket `caps`, ping `caps`).
- (NSArray<NSString *> *)sdkCapabilities;
/// The `capture-capabilities` message data for the widget.
- (NSDictionary *)widgetCapabilities;

#pragma mark Widget bridge

/// Handles capture-start, capture-cancel, capture-done and capture-editor. YES when the message was one of them.
- (BOOL)handleWidgetMessage:(NSString *)name data:(nullable id)data;
/// Sends capture-capabilities to a connected widget.
- (void)sendCapabilitiesToWidget;
/// The widget closes for good (not minimized): ends a running capture and gives the request back.
- (void)widgetWillClose;
/// The widget's page was loaded again after its web content process ended: the current request's image and state
/// are sent to it once more.
- (void)widgetPageDidReload;

#pragma mark Background logs (any thread)

/// `capture-request` data from the websocket, or the ping answer's `cr` list. Only `logs` requests are handled.
- (void)handleCaptureRequests:(nullable id)requests;

#pragma mark State

/// YES while a recording runs (the replays pause meanwhile).
- (BOOL)isRecording;
/// YES from capture-start until the capture has ended (main thread).
- (BOOL)hasActiveCapture;

@end

NS_ASSUME_NONNULL_END
