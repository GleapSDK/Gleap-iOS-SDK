//
//  GleapCaptureOverlay.h
//  Gleap
//
//  The capture UI on top of the app while the widget is minimized, in a window of its own: a small dark bar
//  the customer can drag anywhere (Capture or Start recording, then the recording timer with Stop; the
//  instruction shows briefly as a caption above it) and a dark full-screen preview of the recording
//  (Send / Retake / close). Every text comes from capture-start.labels with an English fallback. Main thread
//  only.
//

#import <UIKit/UIKit.h>
#import "GleapInternal.h"

NS_ASSUME_NONNULL_BEGIN

/// The host UI texts of a capture request (capture-start.labels), with English defaults.
GLEAP_INTERNAL
@interface GleapCaptureLabels : NSObject
- (instancetype)initWithLabels:(nullable id)labels;
/// The label for `key` (e.g. `barCapture`); the English default when the request has none.
- (NSString *)text:(NSString *)key;
+ (NSDictionary<NSString *, NSString *> *)defaultLabels;
@end

typedef NS_ENUM(NSInteger, GleapCaptureBarMode) {
    GleapCaptureBarModeScreenshot,
    GleapCaptureBarModeRecordReady,
    GleapCaptureBarModeRecording,
    /// The bar as it is, with a spinner in its main button (Capture, Start or Stop), which waits meanwhile.
    GleapCaptureBarModeBusy,
};

/// Taps on the capture UI (main queue).
@protocol GleapCaptureOverlayDelegate <NSObject>
- (void)captureOverlayDidTapCapture;
- (void)captureOverlayDidTapStart;
- (void)captureOverlayDidTapStop;
- (void)captureOverlayDidTapCancel;
- (void)captureOverlayDidTapSend;
- (void)captureOverlayDidTapRetake;
- (void)captureOverlayDidTapPreviewCancel;
/// The preview disappeared without one of its buttons (the system removed it): treated like Cancel.
- (void)captureOverlayPreviewWasDismissed;
@end

GLEAP_INTERNAL
@interface GleapCaptureOverlay : NSObject

/// Shows nothing yet; the window appears with the first showBarMode:. `accentColor` is the widget's color (the main
/// buttons); without one they are white.
- (nullable instancetype)initWithScene:(UIWindowScene *)scene
                                labels:(GleapCaptureLabels *)labels
                           accentColor:(nullable UIColor *)accentColor
                              delegate:(id<GleapCaptureOverlayDelegate>)delegate;

- (void)showBarMode:(GleapCaptureBarMode)mode;
- (void)setBarHidden:(BOOL)hidden animated:(BOOL)animated completion:(nullable void (^)(void))completion;
- (void)updateElapsed:(NSTimeInterval)elapsed maxDuration:(NSTimeInterval)maxDuration;

/// The recording (`videoSize` in pixels, for its frame on screen) to send, retake or drop.
- (void)presentPreviewWithFileURL:(NSURL *)fileURL videoSize:(CGSize)videoSize;
/// Shows the upload progress (0…1) on Send and disables the preview except its close button (which cancels).
- (void)setPreviewUploadProgress:(double)progress;
/// Ends the uploading look; shows `message` (nil clears it) and enables the buttons again.
- (void)setPreviewErrorMessage:(nullable NSString *)message;
- (void)dismissPreviewWithCompletion:(nullable void (^)(void))completion;

/// Removes the window (and a presented preview). The completion runs on the main queue.
- (void)tearDownWithCompletion:(nullable void (^)(void))completion;

/// "mm:ss".
+ (NSString *)formattedTime:(NSTimeInterval)seconds;

@end

NS_ASSUME_NONNULL_END
