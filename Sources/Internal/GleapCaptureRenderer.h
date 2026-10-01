//
//  GleapCaptureRenderer.h
//  Gleap
//
//  Draws what the user sees in one window scene: every visible window in window level order,
//  without Gleap's own windows and the keyboard, with masked views and secure text fields
//  blacked out. Screenshots and the frames of a screen recording both come from here.
//

#import <UIKit/UIKit.h>
#import "GleapInternal.h"

NS_ASSUME_NONNULL_BEGIN

/// Windows of the SDK itself (the capture bar, the recording preview) adopt this and are never captured.
@protocol GleapExcludedFromCapture <NSObject>
@end

GLEAP_INTERNAL
@interface GleapCaptureRenderer : NSObject

/// The scene the user sees: the scene of the key window when it is in the foreground, otherwise the first
/// foreground-active window scene (nil without one).
+ (nullable UIWindowScene *)foregroundWindowScene;

/// The capture canvas of a scene in points (its coordinate space: the app's window, also in split view).
+ (CGRect)canvasBoundsForScene:(UIWindowScene *)scene;

/// The windows that make up a capture of the scene, back to front: visible windows without the SDK's own
/// windows and the keyboard / text effects windows.
+ (NSArray<UIWindow *> *)capturableWindowsInScene:(UIWindowScene *)scene;

/// Draws `windows` (from capturableWindowsInScene:) into `context`, whose user space is the canvas in points
/// with the origin at the top left (a UIKit context). Every window is followed by the black boxes of its masked
/// views and secure / one-time-code / card text fields, so a window above still covers them. Main thread.
+ (void)drawWindows:(NSArray<UIWindow *> *)windows
            inScene:(UIWindowScene *)scene
             canvas:(CGRect)canvas
        maskedViews:(NSArray<UIView *> *)maskedViews
            context:(CGContextRef)context;

/// A screenshot of the scene with a long edge of at most `maxLongEdge` pixels (never above the screen's own
/// resolution), opaque sRGB. Main thread; nil when nothing could be drawn.
+ (nullable UIImage *)screenshotOfScene:(UIWindowScene *)scene
                            maxLongEdge:(CGFloat)maxLongEdge
                            maskedViews:(NSArray<UIView *> *)maskedViews;

#pragma mark - Geometry

/// Pixels per point for a capture of `canvas` whose long edge stays within `maxLongEdge` pixels and which is not
/// sharper than the screen (`screenScale`).
+ (CGFloat)pixelScaleForCanvasSize:(CGSize)canvas screenScale:(CGFloat)screenScale maxLongEdge:(CGFloat)maxLongEdge;

/// The pixel size of a recording of `canvas`: long edge at most `maxLongEdge`, not above the screen's resolution,
/// both sides even (H.264 needs even dimensions) and at least 2.
+ (CGSize)videoSizeForCanvasSize:(CGSize)canvas screenScale:(CGFloat)screenScale maxLongEdge:(CGFloat)maxLongEdge;

/// Where content of `contentSize` goes in a frame of `outputSize`: scaled to fit, centered, whole pixels (the
/// rest of the frame stays black). A zero rect for empty sizes.
+ (CGRect)letterboxRectForContentSize:(CGSize)contentSize inOutputSize:(CGSize)outputSize;

#pragma mark - Windows

+ (BOOL)isExcludedWindow:(UIWindow *)window;
+ (BOOL)isKeyboardWindow:(UIWindow *)window;

@end

NS_ASSUME_NONNULL_END
