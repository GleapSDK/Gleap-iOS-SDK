//
//  GleapFrameRecorder.m
//  Gleap
//

#import "GleapFrameRecorder.h"
#import "GleapCaptureRenderer.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>
#import <stdatomic.h>

static CGFloat const kGleapVideoMaxLongEdge = 1280.0;
static NSInteger const kGleapVideoBitRate = 1000000;
static double const kGleapTargetFramesPerSecond = 4.0;
static double const kGleapMinFramesPerSecond = 2.0;
static double const kGleapMaxFramesPerSecond = 8.0;
// Frames drawn but not yet handed to the encoder; more means the encoder is behind and frames are dropped.
static int const kGleapMaxFramesInFlight = 3;
static NSString * const kGleapFrameRecorderErrorDomain = @"io.gleap.capture.recorder";

typedef NS_ENUM(NSInteger, GleapFrameRecorderState) {
    GleapFrameRecorderStateIdle,
    GleapFrameRecorderStateRecording,
    GleapFrameRecorderStatePaused,
    GleapFrameRecorderStateStopping,
    GleapFrameRecorderStateStopped,
    GleapFrameRecorderStateCancelled,
};

@implementation GleapRecordingResult
@end

@interface GleapFrameRecorder () {
    atomic_int _framesInFlight;
    CVPixelBufferPoolRef _pixelBufferPool;
    CGColorSpaceRef _colorSpace;
}

@property (nonatomic, weak) UIWindowScene *scene;
@property (nonatomic, strong) NSURL *outputDirectory;
@property (nonatomic, assign) NSTimeInterval maxDuration;
@property (nonatomic, copy) NSArray<UIView *> * (^maskedViewsProvider)(void);

// Main queue.
@property (nonatomic, assign) GleapFrameRecorderState state;
@property (nonatomic, assign) CGSize outputSize;
@property (nonatomic, strong, nullable) NSTimer *frameTimer;
@property (nonatomic, assign, readwrite) double currentFramesPerSecond;
@property (nonatomic, assign) double averageDrawTime;
@property (nonatomic, assign) CFTimeInterval lastFrameStart;
@property (nonatomic, assign) CFTimeInterval startMediaTime;
@property (nonatomic, assign) CFTimeInterval pausedAt;
@property (nonatomic, assign) CFTimeInterval pausedTotal;
@property (nonatomic, assign) NSTimeInterval lastPresentationTime;
@property (nonatomic, assign) NSTimeInterval segmentStartTime;
@property (nonatomic, assign) NSUInteger nextSegmentIndex;
@property (nonatomic, assign) NSTimeInterval finalDuration;
@property (nonatomic, strong, nullable) NSDate *startedAt;
@property (nonatomic, strong, nullable) NSDate *endedAt;
@property (nonatomic, assign) BOOL failureReported;
@property (nonatomic, assign) BOOL maxDurationReported;
@property (nonatomic, assign) BOOL observing;
@property (nonatomic, strong) dispatch_group_t segmentGroup;

// Encode queue.
@property (nonatomic, strong) dispatch_queue_t encodeQueue;
@property (nonatomic, strong, nullable) AVAssetWriter *queueWriter;
@property (nonatomic, strong, nullable) AVAssetWriterInput *queueInput;
@property (nonatomic, strong, nullable) AVAssetWriterInputPixelBufferAdaptor *queueAdaptor;
@property (nonatomic, strong, nullable) NSURL *queueSegmentURL;
@property (nonatomic, assign) NSUInteger queueSegmentIndex;
@property (nonatomic, assign) NSUInteger queueSegmentFrames;
@property (nonatomic, assign) int64_t queueSegmentLastValue;
@property (nonatomic, assign) NSUInteger queueTotalFrames;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *queueFinishedSegments;

@end

@implementation GleapFrameRecorder

@synthesize delegate = _delegate;

- (instancetype)initWithScene:(UIWindowScene *)scene
              outputDirectory:(NSURL *)outputDirectory
                  maxDuration:(NSTimeInterval)maxDuration
          maskedViewsProvider:(NSArray<UIView *> * (^)(void))maskedViewsProvider {
    self = [super init];
    if (self) {
        _scene = scene;
        _outputDirectory = outputDirectory;
        _maxDuration = MAX(1.0, maxDuration);
        _maskedViewsProvider = [maskedViewsProvider copy];
        _state = GleapFrameRecorderStateIdle;
        _currentFramesPerSecond = kGleapTargetFramesPerSecond;
        _lastPresentationTime = -1;
        _segmentGroup = dispatch_group_create();
        _encodeQueue = dispatch_queue_create("io.gleap.capture.encoder", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0));
        _queueFinishedSegments = [NSMutableArray array];
        _queueSegmentLastValue = -1;
        atomic_init(&_framesInFlight, 0);
    }
    return self;
}

- (void)dealloc {
    [_frameTimer invalidate];
    if (_observing) {
        [[NSNotificationCenter defaultCenter] removeObserver: self];
    }
    if (_pixelBufferPool != NULL) {
        CVPixelBufferPoolRelease(_pixelBufferPool);
    }
    if (_colorSpace != NULL) {
        CGColorSpaceRelease(_colorSpace);
    }
}

- (NSString *)method {
    return @"frames";
}

+ (double)framesPerSecondForDrawTime:(NSTimeInterval)drawSeconds {
    if (drawSeconds <= 0) {
        return kGleapTargetFramesPerSecond;
    }
    // Drawing may take at most 30 % of the frame interval ...
    double withinBudget = 0.3 / drawSeconds;
    if (withinBudget < kGleapTargetFramesPerSecond) {
        return MAX(kGleapMinFramesPerSecond, withinBudget);
    }
    // ... and above the 4 fps target at most 10 %: cheap frames buy a smoother video, not a busier app.
    return MIN(kGleapMaxFramesPerSecond, MAX(kGleapTargetFramesPerSecond, 0.1 / drawSeconds));
}

#pragma mark - Errors

+ (NSError *)errorWithCode:(NSInteger)code description:(NSString *)description {
    return [NSError errorWithDomain: kGleapFrameRecorderErrorDomain code: code userInfo: @{ NSLocalizedDescriptionKey: description }];
}

#pragma mark - Start

- (BOOL)startWithError:(NSError **)error {
    if (self.state != GleapFrameRecorderStateIdle) {
        if (error) { *error = [GleapFrameRecorder errorWithCode: 1 description: @"The recorder was already used."]; }
        return NO;
    }
    UIWindowScene *scene = self.scene;
    CGRect canvas = scene != nil ? [GleapCaptureRenderer canvasBoundsForScene: scene] : CGRectZero;
    if (scene == nil || CGRectIsEmpty(canvas)) {
        if (error) { *error = [GleapFrameRecorder errorWithCode: 2 description: @"No window scene to record."]; }
        return NO;
    }
    CGFloat screenScale = scene.screen.scale > 0 ? scene.screen.scale : UIScreen.mainScreen.scale;
    self.outputSize = [GleapCaptureRenderer videoSizeForCanvasSize: canvas.size screenScale: screenScale maxLongEdge: kGleapVideoMaxLongEdge];

    NSError *directoryError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtURL: self.outputDirectory withIntermediateDirectories: YES attributes: nil error: &directoryError]) {
        if (error) { *error = directoryError; }
        return NO;
    }

    NSDictionary *pixelBufferAttributes = [self pixelBufferAttributes];
    NSDictionary *poolAttributes = @{ (id)kCVPixelBufferPoolMinimumBufferCountKey: @(kGleapMaxFramesInFlight) };
    CVPixelBufferPoolRef pool = NULL;
    CVReturn poolResult = CVPixelBufferPoolCreate(kCFAllocatorDefault, (__bridge CFDictionaryRef)poolAttributes, (__bridge CFDictionaryRef)pixelBufferAttributes, &pool);
    if (poolResult != kCVReturnSuccess || pool == NULL) {
        if (error) { *error = [GleapFrameRecorder errorWithCode: 3 description: @"Could not allocate video frames."]; }
        return NO;
    }
    _pixelBufferPool = pool;
    _colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);

    self.state = GleapFrameRecorderStateRecording;
    self.startMediaTime = CACurrentMediaTime();
    self.startedAt = [NSDate date];
    self.pausedTotal = 0;
    self.segmentStartTime = 0;
    [self beginSegment];
    [self startObserving];

    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
        [self pause];
        return YES;
    }
    [self captureFrame];
    [self scheduleNextFrame];
    return YES;
}

- (NSDictionary *)pixelBufferAttributes {
    return @{
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (id)kCVPixelBufferWidthKey: @((NSInteger)self.outputSize.width),
        (id)kCVPixelBufferHeightKey: @((NSInteger)self.outputSize.height),
        (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
        (id)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES,
        (id)kCVPixelBufferCGImageCompatibilityKey: @YES,
    };
}

- (void)startObserving {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver: self selector: @selector(applicationWillResignActive:) name: UIApplicationWillResignActiveNotification object: nil];
    [center addObserver: self selector: @selector(applicationDidBecomeActive:) name: UIApplicationDidBecomeActiveNotification object: nil];
    [center addObserver: self selector: @selector(applicationDidReceiveMemoryWarning:) name: UIApplicationDidReceiveMemoryWarningNotification object: nil];
    if (self.scene != nil) {
        [center addObserver: self selector: @selector(sceneDidDisconnect:) name: UISceneDidDisconnectNotification object: self.scene];
    }
    self.observing = YES;
}

- (void)stopObserving {
    if (self.observing) {
        [[NSNotificationCenter defaultCenter] removeObserver: self];
        self.observing = NO;
    }
}

#pragma mark - Time

- (NSTimeInterval)currentPresentationTime {
    CFTimeInterval now = self.state == GleapFrameRecorderStatePaused ? self.pausedAt : CACurrentMediaTime();
    return MAX(0, now - self.startMediaTime - self.pausedTotal);
}

- (NSTimeInterval)recordedDuration {
    switch (self.state) {
        case GleapFrameRecorderStateIdle:
            return 0;
        case GleapFrameRecorderStateRecording:
        case GleapFrameRecorderStatePaused:
            return MIN([self currentPresentationTime], self.maxDuration);
        default:
            return self.finalDuration;
    }
}

#pragma mark - Frames

- (void)scheduleNextFrame {
    [self.frameTimer invalidate];
    self.frameTimer = nil;
    if (self.state != GleapFrameRecorderStateRecording || self.maxDurationReported) {
        return;
    }
    NSTimeInterval interval = 1.0 / MAX(self.currentFramesPerSecond, kGleapMinFramesPerSecond);
    NSTimeInterval delay = MAX(0.01, (self.lastFrameStart + interval) - CACurrentMediaTime());
    __weak typeof(self) weakSelf = self;
    NSTimer *timer = [NSTimer timerWithTimeInterval: delay repeats: NO block:^(NSTimer * _Nonnull firedTimer) {
        [weakSelf frameTimerFired];
    }];
    timer.tolerance = MIN(0.02, delay * 0.1);
    // Common modes: frames keep coming while the user scrolls.
    [[NSRunLoop mainRunLoop] addTimer: timer forMode: NSRunLoopCommonModes];
    self.frameTimer = timer;
}

- (void)frameTimerFired {
    @try {
        self.frameTimer = nil;
        @try {
            [self captureFrame];
        } @catch (NSException *exception) {
            NSLog(@"[GLEAP_SDK] Screen recording frame failed: %@", exception.reason);
        }
        [self scheduleNextFrame];
    } @catch (NSException *exception) {
        // Without a next frame the recording still ends: by Stop, the maximum length or the elapsed timer.
        NSLog(@"[GLEAP_SDK] Screen recording timer failed: %@", exception.reason);
    }
}

- (void)captureFrame {
    if (self.state != GleapFrameRecorderStateRecording) {
        return;
    }
    self.lastFrameStart = CACurrentMediaTime();
    NSTimeInterval presentationTime = [self currentPresentationTime];
    if (presentationTime >= self.maxDuration) {
        [self reportMaxDuration];
        return;
    }
    UIWindowScene *scene = self.scene;
    if (scene == nil || scene.activationState != UISceneActivationStateForegroundActive || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
        return;
    }
    if (atomic_load(&_framesInFlight) >= kGleapMaxFramesInFlight || _pixelBufferPool == NULL) {
        return;
    }

    CVPixelBufferRef pixelBuffer = NULL;
    NSDictionary *auxAttributes = @{ (id)kCVPixelBufferPoolAllocationThresholdKey: @(kGleapMaxFramesInFlight * 2) };
    CVReturn result = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, _pixelBufferPool, (__bridge CFDictionaryRef)auxAttributes, &pixelBuffer);
    if (result != kCVReturnSuccess || pixelBuffer == NULL) {
        return;
    }

    CFTimeInterval drawStart = CACurrentMediaTime();
    BOOL drawn = NO;
    @try {
        drawn = [self drawScene: scene intoPixelBuffer: pixelBuffer];
    } @catch (NSException *exception) {
        drawn = NO;
    }
    [self recordDrawTime: CACurrentMediaTime() - drawStart];
    if (!drawn) {
        CVPixelBufferRelease(pixelBuffer);
        return;
    }

    if (presentationTime <= self.lastPresentationTime) {
        presentationTime = self.lastPresentationTime + 0.001;
    }
    self.lastPresentationTime = presentationTime;
    NSTimeInterval segmentTime = MAX(0, presentationTime - self.segmentStartTime);

    atomic_fetch_add(&_framesInFlight, 1);
    dispatch_async(self.encodeQueue, ^{
        @try {
            [self queueAppendPixelBuffer: pixelBuffer atTime: segmentTime];
        } @catch (NSException *exception) {
            NSLog(@"[GLEAP_SDK] Screen recording could not encode a frame: %@", exception.reason);
        }
        CVPixelBufferRelease(pixelBuffer);
        atomic_fetch_sub(&self->_framesInFlight, 1);
    });
}

- (void)recordDrawTime:(CFTimeInterval)seconds {
    self.averageDrawTime = self.averageDrawTime <= 0 ? seconds : (self.averageDrawTime * 0.7 + seconds * 0.3);
    self.currentFramesPerSecond = [GleapFrameRecorder framesPerSecondForDrawTime: self.averageDrawTime];
}

- (BOOL)drawScene:(UIWindowScene *)scene intoPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    CGRect canvas = [GleapCaptureRenderer canvasBoundsForScene: scene];
    NSArray<UIWindow *> *windows = [GleapCaptureRenderer capturableWindowsInScene: scene];
    if (CGRectIsEmpty(canvas) || windows.count == 0) {
        return NO;
    }
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    if (CVPixelBufferLockBaseAddress(pixelBuffer, 0) != kCVReturnSuccess) {
        return NO;
    }
    CGContextRef context = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pixelBuffer), width, height, 8, CVPixelBufferGetBytesPerRow(pixelBuffer), _colorSpace, (CGBitmapInfo)kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    if (context == NULL) {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
        return NO;
    }
    @try {
        CGContextSetFillColorWithColor(context, [UIColor blackColor].CGColor);
        CGContextFillRect(context, CGRectMake(0, 0, width, height));

        // The canvas keeps its aspect ratio inside the fixed video size (rotation / resizing letterboxes).
        CGRect box = [GleapCaptureRenderer letterboxRectForContentSize: canvas.size inOutputSize: CGSizeMake(width, height)];
        // UIKit draws top down: flip, then map the canvas (points) onto the box (pixels).
        CGContextTranslateCTM(context, 0, height);
        CGContextScaleCTM(context, 1.0, -1.0);
        CGContextTranslateCTM(context, box.origin.x, box.origin.y);
        CGContextScaleCTM(context, box.size.width / canvas.size.width, box.size.height / canvas.size.height);
        CGContextClipToRect(context, CGRectMake(0, 0, canvas.size.width, canvas.size.height));

        NSArray<UIView *> *maskedViews = self.maskedViewsProvider != nil ? self.maskedViewsProvider() : @[];
        UIGraphicsPushContext(context);
        @try {
            [GleapCaptureRenderer drawWindows: windows inScene: scene canvas: canvas maskedViews: maskedViews ?: @[] context: context];
        } @finally {
            UIGraphicsPopContext();
        }
    } @finally {
        CGContextRelease(context);
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    }
    return YES;
}

#pragma mark - Segments (encode queue unless noted)

// Main queue: a new file for the frames from now on.
- (void)beginSegment {
    NSUInteger index = self.nextSegmentIndex;
    self.nextSegmentIndex += 1;
    NSURL *url = [self.outputDirectory URLByAppendingPathComponent: [NSString stringWithFormat: @"segment-%lu.mp4", (unsigned long)index]];
    CGSize size = self.outputSize;
    dispatch_async(self.encodeQueue, ^{
        NSError *error = nil;
        BOOL started = NO;
        @try {
            started = [self queueStartWriterAtURL: url index: index size: size error: &error];
        } @catch (NSException *exception) {
            error = [GleapFrameRecorder errorWithCode: 4 description: exception.reason ?: @"The video writer could not start."];
        }
        if (!started) {
            [self reportFailure: error];
        }
    });
}

- (NSDictionary *)videoSettingsForSize:(CGSize)size complete:(BOOL)complete {
    NSMutableDictionary *compression = [@{
        AVVideoAverageBitRateKey: @(kGleapVideoBitRate),
        AVVideoMaxKeyFrameIntervalDurationKey: @(2.0),
        AVVideoMaxKeyFrameIntervalKey: @((NSInteger)(kGleapMaxFramesPerSecond * 2)),
    } mutableCopy];
    NSMutableDictionary *settings = [@{
        AVVideoCodecKey: AVVideoCodecTypeH264,
        AVVideoWidthKey: @((NSInteger)size.width),
        AVVideoHeightKey: @((NSInteger)size.height),
    } mutableCopy];
    if (complete) {
        compression[AVVideoAllowFrameReorderingKey] = @NO;
        compression[AVVideoExpectedSourceFrameRateKey] = @((NSInteger)kGleapTargetFramesPerSecond);
        compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel;
        settings[AVVideoColorPropertiesKey] = @{
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        };
    }
    settings[AVVideoCompressionPropertiesKey] = compression;
    return settings;
}

- (BOOL)queueStartWriterAtURL:(NSURL *)url index:(NSUInteger)index size:(CGSize)size error:(NSError **)error {
    [[NSFileManager defaultManager] removeItemAtURL: url error: nil];
    AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL: url fileType: AVFileTypeMPEG4 error: error];
    if (writer == nil) {
        return NO;
    }
    writer.shouldOptimizeForNetworkUse = YES;

    NSDictionary *settings = [self videoSettingsForSize: size complete: YES];
    if (![writer canApplyOutputSettings: settings forMediaType: AVMediaTypeVideo]) {
        settings = [self videoSettingsForSize: size complete: NO];
        if (![writer canApplyOutputSettings: settings forMediaType: AVMediaTypeVideo]) {
            if (error) { *error = [GleapFrameRecorder errorWithCode: 5 description: @"H.264 encoding is not available."]; }
            return NO;
        }
    }
    AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType: AVMediaTypeVideo outputSettings: settings];
    input.expectsMediaDataInRealTime = YES;
    // The adaptor is the Objective-C pixel buffer API (the input receiver that replaces it in the iOS 27 SDK is
    // Swift only); the buffers come from the recorder's own pool, which outlives the per-segment writers.
    AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput: input sourcePixelBufferAttributes: @{
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (id)kCVPixelBufferWidthKey: @((NSInteger)size.width),
        (id)kCVPixelBufferHeightKey: @((NSInteger)size.height),
    }];
    if (![writer canAddInput: input]) {
        if (error) { *error = [GleapFrameRecorder errorWithCode: 6 description: @"The video writer does not accept the input."]; }
        return NO;
    }
    [writer addInput: input];
    if (![writer startWriting]) {
        if (error) { *error = writer.error ?: [GleapFrameRecorder errorWithCode: 7 description: @"The video writer could not start."]; }
        [[NSFileManager defaultManager] removeItemAtURL: url error: nil];
        return NO;
    }
    [writer startSessionAtSourceTime: kCMTimeZero];

    self.queueWriter = writer;
    self.queueInput = input;
    self.queueAdaptor = adaptor;
    self.queueSegmentURL = url;
    self.queueSegmentIndex = index;
    self.queueSegmentFrames = 0;
    self.queueSegmentLastValue = -1;
    return YES;
}

- (void)queueAppendPixelBuffer:(CVPixelBufferRef)pixelBuffer atTime:(NSTimeInterval)segmentTime {
    AVAssetWriter *writer = self.queueWriter;
    if (writer == nil || writer.status != AVAssetWriterStatusWriting) {
        return;
    }
    if (!self.queueInput.isReadyForMoreMediaData) {
        // The encoder is behind: drop the frame rather than wait.
        return;
    }
    int64_t value = llround(segmentTime * 1000.0);
    if (value <= self.queueSegmentLastValue) {
        value = self.queueSegmentLastValue + 1;
    }
    if ([self.queueAdaptor appendPixelBuffer: pixelBuffer withPresentationTime: CMTimeMake(value, 1000)]) {
        self.queueSegmentFrames += 1;
        self.queueTotalFrames += 1;
        self.queueSegmentLastValue = value;
    } else if (writer.status == AVAssetWriterStatusFailed) {
        [self reportFailure: writer.error];
    }
}

// Main queue: finishes the current segment file at `segmentEnd` (seconds into the segment), in the background task
// the writer needs to complete. dispatch_group_notify on segmentGroup waits for it.
- (void)finishCurrentSegmentAt:(NSTimeInterval)segmentEnd {
    dispatch_group_enter(self.segmentGroup);
    __block UIBackgroundTaskIdentifier backgroundTask = UIBackgroundTaskInvalid;
    backgroundTask = [UIApplication.sharedApplication beginBackgroundTaskWithName: @"io.gleap.capture.recording" expirationHandler:^{
        if (backgroundTask != UIBackgroundTaskInvalid) {
            [UIApplication.sharedApplication endBackgroundTask: backgroundTask];
            backgroundTask = UIBackgroundTaskInvalid;
        }
    }];
    dispatch_async(self.encodeQueue, ^{
        [self queueFinishSegmentAt: segmentEnd completion:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (backgroundTask != UIBackgroundTaskInvalid) {
                    [UIApplication.sharedApplication endBackgroundTask: backgroundTask];
                    backgroundTask = UIBackgroundTaskInvalid;
                }
            });
            dispatch_group_leave(self.segmentGroup);
        }];
    });
}

- (void)queueFinishSegmentAt:(NSTimeInterval)segmentEnd completion:(void (^)(void))completion {
    AVAssetWriter *writer = self.queueWriter;
    AVAssetWriterInput *input = self.queueInput;
    NSURL *url = self.queueSegmentURL;
    NSUInteger index = self.queueSegmentIndex;
    NSUInteger frames = self.queueSegmentFrames;
    int64_t lastValue = self.queueSegmentLastValue;
    self.queueWriter = nil;
    self.queueInput = nil;
    self.queueAdaptor = nil;
    self.queueSegmentURL = nil;
    self.queueSegmentFrames = 0;
    self.queueSegmentLastValue = -1;

    if (writer == nil) {
        completion();
        return;
    }
    if (frames == 0 || writer.status != AVAssetWriterStatusWriting) {
        @try {
            if (writer.status == AVAssetWriterStatusWriting) {
                [writer cancelWriting];
            }
        } @catch (NSException *exception) {}
        if (url != nil) {
            [[NSFileManager defaultManager] removeItemAtURL: url error: nil];
        }
        completion();
        return;
    }

    // The last frame stays on screen until the moment the segment ended.
    int64_t endValue = MAX(llround(segmentEnd * 1000.0), lastValue + 1);
    @try {
        [input markAsFinished];
        [writer endSessionAtSourceTime: CMTimeMake(endValue, 1000)];
        [writer finishWritingWithCompletionHandler:^{
            dispatch_async(self.encodeQueue, ^{
                @try {
                    if (writer.status == AVAssetWriterStatusCompleted && url != nil) {
                        [self.queueFinishedSegments addObject: @{
                            @"url": url,
                            @"index": @(index),
                            @"duration": @((double)endValue / 1000.0),
                        }];
                    } else {
                        NSLog(@"[GLEAP_SDK] A screen recording part could not be written: %@", writer.error.localizedDescription);
                        if (url != nil) {
                            [[NSFileManager defaultManager] removeItemAtURL: url error: nil];
                        }
                    }
                } @catch (NSException *exception) {
                    NSLog(@"[GLEAP_SDK] A screen recording part could not be kept: %@", exception.reason);
                }
                completion();
            });
        }];
    } @catch (NSException *exception) {
        if (url != nil) {
            [[NSFileManager defaultManager] removeItemAtURL: url error: nil];
        }
        completion();
    }
}

- (void)queueAssembleWithCompletion:(void (^)(GleapRecordingResult * _Nullable result, NSError * _Nullable error))completion {
    NSArray<NSDictionary *> *segments = [self.queueFinishedSegments sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *first, NSDictionary *second) {
        return [first[@"index"] compare: second[@"index"]];
    }];
    if (segments.count == 0) {
        completion(nil, [GleapFrameRecorder errorWithCode: 8 description: @"Nothing was recorded."]);
        return;
    }
    NSURL *finalURL = [self.outputDirectory URLByAppendingPathComponent: @"screen-recording.mp4"];
    [[NSFileManager defaultManager] removeItemAtURL: finalURL error: nil];

    void (^finish)(NSURL *, NSTimeInterval) = ^(NSURL *url, NSTimeInterval duration) {
        GleapRecordingResult *result = [[GleapRecordingResult alloc] init];
        result.fileURL = url;
        result.width = (NSInteger)self.outputSize.width;
        result.height = (NSInteger)self.outputSize.height;
        result.duration = duration;
        result.frameCount = self.queueTotalFrames;
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath: url.path error: nil];
        result.fileSize = [attributes fileSize];
        // Start and end are set on the main queue before the completion runs.
        completion(result, nil);
    };

    if (segments.count == 1) {
        NSURL *segmentURL = segments.firstObject[@"url"];
        NSTimeInterval duration = [segments.firstObject[@"duration"] doubleValue];
        NSError *moveError = nil;
        if ([[NSFileManager defaultManager] moveItemAtURL: segmentURL toURL: finalURL error: &moveError]) {
            finish(finalURL, duration);
        } else {
            finish(segmentURL, duration);
        }
        return;
    }

    [self queueJoinSegments: segments toURL: finalURL completion:^(BOOL joined, NSTimeInterval duration) {
        dispatch_async(self.encodeQueue, ^{
            @try {
                [self queueFinishJoin: joined duration: duration segments: segments finalURL: finalURL finish: finish];
            } @catch (NSException *exception) {
                completion(nil, [GleapFrameRecorder errorWithCode: 11 description: exception.reason ?: @"The recording could not be assembled."]);
            }
        });
    }];
}

// Encode queue: the joined file, or the longest part when joining failed.
- (void)queueFinishJoin:(BOOL)joined duration:(NSTimeInterval)duration segments:(NSArray<NSDictionary *> *)segments finalURL:(NSURL *)finalURL finish:(void (^)(NSURL *, NSTimeInterval))finish {
    if (joined) {
        for (NSDictionary *segment in segments) {
            [[NSFileManager defaultManager] removeItemAtURL: segment[@"url"] error: nil];
        }
        finish(finalURL, duration);
        return;
    }
    // Joining failed: keep the longest part rather than nothing.
    NSDictionary *longest = segments.firstObject;
    for (NSDictionary *segment in segments) {
        if ([segment[@"duration"] doubleValue] > [longest[@"duration"] doubleValue]) {
            longest = segment;
        }
    }
    finish(longest[@"url"], [longest[@"duration"] doubleValue]);
}

// Encode queue. Joins the parts (all H.264 in the same size) without re-encoding.
- (void)queueJoinSegments:(NSArray<NSDictionary *> *)segments toURL:(NSURL *)url completion:(void (^)(BOOL joined, NSTimeInterval duration))completion {
    @try {
        AVMutableComposition *composition = [AVMutableComposition composition];
        AVMutableCompositionTrack *track = [composition addMutableTrackWithMediaType: AVMediaTypeVideo preferredTrackID: kCMPersistentTrackID_Invalid];
        CMTime cursor = kCMTimeZero;
        for (NSDictionary *segment in segments) {
            AVURLAsset *asset = [AVURLAsset URLAssetWithURL: segment[@"url"] options: @{ AVURLAssetPreferPreciseDurationAndTimingKey: @YES }];
            __block AVAssetTrack *sourceTrack = nil;
            dispatch_semaphore_t loaded = dispatch_semaphore_create(0);
            [asset loadTracksWithMediaType: AVMediaTypeVideo completionHandler:^(NSArray<AVAssetTrack *> * _Nullable tracks, NSError * _Nullable error) {
                sourceTrack = tracks.firstObject;
                dispatch_semaphore_signal(loaded);
            }];
            if (dispatch_semaphore_wait(loaded, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC))) != 0 || sourceTrack == nil) {
                continue;
            }
            CMTimeRange range = sourceTrack.timeRange;
            if (!CMTIMERANGE_IS_VALID(range) || CMTIME_COMPARE_INLINE(range.duration, <=, kCMTimeZero)) {
                continue;
            }
            NSError *insertError = nil;
            if ([track insertTimeRange: range ofTrack: sourceTrack atTime: cursor error: &insertError]) {
                cursor = CMTimeAdd(cursor, range.duration);
            }
        }
        if (CMTimeGetSeconds(cursor) <= 0) {
            completion(NO, 0);
            return;
        }
        AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset: composition presetName: AVAssetExportPresetPassthrough];
        if (exportSession == nil) {
            completion(NO, 0);
            return;
        }
        exportSession.outputURL = url;
        exportSession.outputFileType = AVFileTypeMPEG4;
        exportSession.shouldOptimizeForNetworkUse = YES;
        NSTimeInterval duration = CMTimeGetSeconds(cursor);
        [exportSession exportAsynchronouslyWithCompletionHandler:^{
            BOOL joined = NO;
            @try {
                joined = exportSession.status == AVAssetExportSessionStatusCompleted;
                if (!joined) {
                    NSLog(@"[GLEAP_SDK] Could not join the screen recording parts: %@", exportSession.error.localizedDescription);
                    [[NSFileManager defaultManager] removeItemAtURL: url error: nil];
                }
            } @catch (NSException *exception) {
                joined = NO;
            }
            completion(joined, duration);
        }];
    } @catch (NSException *exception) {
        completion(NO, 0);
    }
}

#pragma mark - Pause / resume

- (void)pause {
    if (self.state != GleapFrameRecorderStateRecording) {
        return;
    }
    self.pausedAt = CACurrentMediaTime();
    self.state = GleapFrameRecorderStatePaused;
    [self.frameTimer invalidate];
    self.frameTimer = nil;
    // Encoders are not available in the background: the part recorded so far is written out now.
    [self finishCurrentSegmentAt: MAX(0, [self currentPresentationTime] - self.segmentStartTime)];
}

- (void)resume {
    if (self.state != GleapFrameRecorderStatePaused) {
        return;
    }
    self.pausedTotal += MAX(0, CACurrentMediaTime() - self.pausedAt);
    self.state = GleapFrameRecorderStateRecording;
    // The next part continues where the last one ended, without the time in between.
    self.segmentStartTime = [self currentPresentationTime];
    self.lastPresentationTime = MAX(self.lastPresentationTime, self.segmentStartTime - 0.001);
    [self beginSegment];
    [self captureFrame];
    [self scheduleNextFrame];
}

- (void)applicationWillResignActive:(NSNotification *)notification {
    @try {
        [self pause];
    } @catch (NSException *exception) {}
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    @try {
        [self resume];
    } @catch (NSException *exception) {}
}

- (void)applicationDidReceiveMemoryWarning:(NSNotification *)notification {
    @try {
        if (self.state != GleapFrameRecorderStateRecording && self.state != GleapFrameRecorderStatePaused) {
            return;
        }
        id<GleapScreenRecorderDelegate> delegate = self.delegate;
        if ([delegate respondsToSelector: @selector(screenRecorderDidReceiveMemoryWarning:)]) {
            [delegate screenRecorderDidReceiveMemoryWarning: self];
        }
    } @catch (NSException *exception) {
        NSLog(@"[GLEAP_SDK] Screen recording memory warning handling failed: %@", exception.reason);
    }
}

- (void)sceneDidDisconnect:(NSNotification *)notification {
    @try {
        // Nothing left to record: end it like reaching the maximum length.
        [self reportMaxDuration];
    } @catch (NSException *exception) {}
}

#pragma mark - Reporting

- (void)reportMaxDuration {
    if (self.maxDurationReported || (self.state != GleapFrameRecorderStateRecording && self.state != GleapFrameRecorderStatePaused)) {
        return;
    }
    self.maxDurationReported = YES;
    [self.frameTimer invalidate];
    self.frameTimer = nil;
    id<GleapScreenRecorderDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector: @selector(screenRecorderDidReachMaxDuration:)]) {
        [delegate screenRecorderDidReachMaxDuration: self];
    }
}

// Any queue.
- (void)reportFailure:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.failureReported || (self.state != GleapFrameRecorderStateRecording && self.state != GleapFrameRecorderStatePaused)) {
            return;
        }
        self.failureReported = YES;
        id<GleapScreenRecorderDelegate> delegate = self.delegate;
        if ([delegate respondsToSelector: @selector(screenRecorder:didFailWithError:)]) {
            [delegate screenRecorder: self didFailWithError: error ?: [GleapFrameRecorder errorWithCode: 9 description: @"The screen recording failed."]];
        }
    });
}

#pragma mark - Stop / cancel

- (void)stopWithCompletion:(void (^)(GleapRecordingResult * _Nullable, NSError * _Nullable))completion {
    if (self.state != GleapFrameRecorderStateRecording && self.state != GleapFrameRecorderStatePaused) {
        if (completion) {
            completion(nil, [GleapFrameRecorder errorWithCode: 10 description: @"The recorder is not recording."]);
        }
        return;
    }
    BOOL wasRecording = self.state == GleapFrameRecorderStateRecording;
    NSTimeInterval end = MIN([self currentPresentationTime], self.maxDuration);
    self.finalDuration = end;
    self.endedAt = [NSDate date];
    self.state = GleapFrameRecorderStateStopping;
    [self.frameTimer invalidate];
    self.frameTimer = nil;
    [self stopObserving];
    if (wasRecording) {
        [self finishCurrentSegmentAt: MAX(0, end - self.segmentStartTime)];
    }

    NSDate *startedAt = self.startedAt;
    NSDate *endedAt = self.endedAt;
    dispatch_group_notify(self.segmentGroup, self.encodeQueue, ^{
        void (^deliver)(GleapRecordingResult *, NSError *) = ^(GleapRecordingResult * _Nullable result, NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.state == GleapFrameRecorderStateCancelled) {
                    if (result != nil) {
                        [[NSFileManager defaultManager] removeItemAtURL: result.fileURL error: nil];
                    }
                    return;
                }
                self.state = GleapFrameRecorderStateStopped;
                result.startedAt = startedAt;
                result.endedAt = endedAt;
                @try {
                    if (completion) {
                        completion(result, result == nil ? error : nil);
                    }
                } @catch (NSException *exception) {
                    NSLog(@"[GLEAP_SDK] Finishing the screen recording failed: %@", exception.reason);
                }
            });
        };
        @try {
            [self queueAssembleWithCompletion: deliver];
        } @catch (NSException *exception) {
            deliver(nil, [GleapFrameRecorder errorWithCode: 11 description: exception.reason ?: @"The recording could not be assembled."]);
        }
    });
}

- (void)cancel {
    if (self.state == GleapFrameRecorderStateCancelled || self.state == GleapFrameRecorderStateStopped) {
        return;
    }
    self.state = GleapFrameRecorderStateCancelled;
    [self.frameTimer invalidate];
    self.frameTimer = nil;
    [self stopObserving];
    dispatch_async(self.encodeQueue, ^{
        AVAssetWriter *writer = self.queueWriter;
        NSURL *url = self.queueSegmentURL;
        self.queueWriter = nil;
        self.queueInput = nil;
        self.queueAdaptor = nil;
        self.queueSegmentURL = nil;
        @try {
            if (writer.status == AVAssetWriterStatusWriting) {
                [writer cancelWriting];
            }
        } @catch (NSException *exception) {}
        if (url != nil) {
            [[NSFileManager defaultManager] removeItemAtURL: url error: nil];
        }
        for (NSDictionary *segment in self.queueFinishedSegments) {
            [[NSFileManager defaultManager] removeItemAtURL: segment[@"url"] error: nil];
        }
        [self.queueFinishedSegments removeAllObjects];
    });
}

@end
