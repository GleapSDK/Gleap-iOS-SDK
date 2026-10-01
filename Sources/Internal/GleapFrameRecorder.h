//
//  GleapFrameRecorder.h
//  Gleap
//
//  Screen recordings of the host app. GleapScreenRecorder is what the capture flow talks to; the one
//  backend today, GleapFrameRecorder, draws the app's windows itself (no ReplayKit, no system prompt)
//  and encodes them to H.264 MP4. A ReplayKit / ScreenCaptureKit backend would adopt the same protocol.
//

#import <UIKit/UIKit.h>
#import "GleapInternal.h"

NS_ASSUME_NONNULL_BEGIN

/// A finished recording.
GLEAP_INTERNAL
@interface GleapRecordingResult : NSObject
@property (nonatomic, strong) NSURL *fileURL;
@property (nonatomic, assign) NSInteger width;
@property (nonatomic, assign) NSInteger height;
/// Length of the video (time in the background is not part of it).
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, strong) NSDate *startedAt;
@property (nonatomic, strong) NSDate *endedAt;
@property (nonatomic, assign) unsigned long long fileSize;
@property (nonatomic, assign) NSUInteger frameCount;
@end

@protocol GleapScreenRecorder;

/// Called on the main queue.
@protocol GleapScreenRecorderDelegate <NSObject>
- (void)screenRecorderDidReachMaxDuration:(id<GleapScreenRecorder>)recorder;
- (void)screenRecorderDidReceiveMemoryWarning:(id<GleapScreenRecorder>)recorder;
- (void)screenRecorder:(id<GleapScreenRecorder>)recorder didFailWithError:(NSError *)error;
@end

/// A screen recording backend. All methods are called on the main queue.
@protocol GleapScreenRecorder <NSObject>
@property (nonatomic, weak, nullable) id<GleapScreenRecorderDelegate> delegate;
/// The capture method reported to the server (`frames` for in-app frame capture).
@property (nonatomic, readonly) NSString *method;
/// Recorded time so far (stops while the app is inactive).
@property (nonatomic, readonly) NSTimeInterval recordedDuration;
- (BOOL)startWithError:(NSError * _Nullable * _Nullable)error;
/// Ends the recording and keeps what was recorded. The completion runs on the main queue.
- (void)stopWithCompletion:(void (^)(GleapRecordingResult * _Nullable result, NSError * _Nullable error))completion;
/// Ends the recording and discards it.
- (void)cancel;
@end

/// Records the app's windows (see GleapCaptureRenderer) at 2–8 frames per second, 4 by default, adapting to how
/// long a frame takes to draw: the main thread spends at most about 30 % of the frame interval on it (at most 10 %
/// above 4 fps). Frames are drawn at video size straight into pixel buffers; encoding runs on a serial queue.
/// H.264 MP4, long edge ≤ 1280 px, even dimensions fixed at the start (later size / orientation changes are
/// letterboxed), about 1 Mbit/s, a key frame at least every 2 s, no audio. While the app is inactive no frames are
/// taken and the time does not count; the writer is finished on resign active (encoders are not allowed in the
/// background) and the parts are joined when the recording stops.
GLEAP_INTERNAL
@interface GleapFrameRecorder : NSObject <GleapScreenRecorder>

- (instancetype)initWithScene:(UIWindowScene *)scene
              outputDirectory:(NSURL *)outputDirectory
                  maxDuration:(NSTimeInterval)maxDuration
          maskedViewsProvider:(NSArray<UIView *> * (^)(void))maskedViewsProvider NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Frames per second chosen for the next frame (2–8).
@property (nonatomic, readonly) double currentFramesPerSecond;

/// The frame rate for an average main-thread draw time of `drawSeconds` (see the class comment).
+ (double)framesPerSecondForDrawTime:(NSTimeInterval)drawSeconds;

@end

NS_ASSUME_NONNULL_END
