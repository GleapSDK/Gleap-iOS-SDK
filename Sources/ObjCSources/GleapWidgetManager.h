//
//  GleapWidgetManager.h
//  
//
//  Created by Lukas Boehler on 28.05.22.
//
//  Internal to the Gleap SDK. This header is only public because every header in
//  Sources/ObjCSources is; it is not part of the supported API and may change without
//  notice. Use the Gleap class (GleapCore.h) instead.
//

#import <Foundation/Foundation.h>
#import "GleapFrameManagerViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface GleapWidgetManager : NSObject <GleapFrameManagerDelegate>

+ (instancetype)sharedInstance;

- (BOOL)isOpened;
/// Open and connected to its page (also while minimized).
- (BOOL)isConnected;
/// Open and on screen: not minimized for a capture. What the app shows while minimized belongs to the app's own
/// story (console output, page views, replays), unlike the SDK's own output while the widget is up.
- (BOOL)isWidgetVisible;
/// Opening, closing, minimizing and restoring run one after the other on the main queue, each once UIKit has finished
/// the one before (UIKit refuses a presentation or dismissal while another one runs).
- (void)closeWidgetWithAnimation:(Boolean)animated andCompletion:(void (^)(void))completion;
/// Takes the open widget off the screen for a capture: it is dismissed, but its controller, web view and page stay
/// alive and connected, the widget counts as open, and widgetClosed is not called. The completion (main queue) gets
/// the window scene the widget was shown in.
- (void)minimizeWidgetWithCompletion:(void (^)(BOOL minimized, UIWindowScene * _Nullable scene))completion;
/// Shows a minimized widget again, as it was (widgetOpened is not called). When it cannot be shown any more (no
/// window to present it on) it is closed for good. The completion runs on the main queue.
- (void)restoreWidgetWithCompletion:(nullable void (^)(BOOL restored))completion;
/// Shows a minimized widget again when no capture runs any more (any thread).
- (void)restoreWidgetIfNoCaptureRuns;
- (void)showWidget;
- (void)showWidgetFor:(NSString *)type;
- (void)sendMessageWithData:(NSDictionary *)data;
- (void)sendSessionUpdate;
- (void)sendConfigUpdate;

@property (nonatomic, assign) bool widgetOpened;
/// YES while the open widget is minimized for a capture.
@property (nonatomic, assign, readonly) BOOL widgetMinimized;
@property (nonatomic, retain, nullable) GleapFrameManagerViewController *gleapWidget;
@property (nonatomic, retain, nullable) NSMutableArray *messageQueue;

@end

NS_ASSUME_NONNULL_END
