//
//  GleapCaptureManager.m
//  Gleap
//

#import "GleapCaptureManager.h"
#import "GleapCaptureAPI.h"
#import "GleapCaptureOverlay.h"
#import "GleapCaptureRenderer.h"
#import "GleapConfigHelper.h"
#import "GleapFrameRecorder.h"
#import "GleapLogsBundle.h"
#import "GleapMetaDataHelper.h"
#import "GleapSessionHelper.h"
#import "GleapUIHelper.h"
#import "GleapWidgetManager.h"

static NSTimeInterval const kGleapDefaultRecordingSeconds = 60;
static NSTimeInterval const kGleapMinRecordingSeconds = 5;
static NSTimeInterval const kGleapMaxRecordingSeconds = 180;
static CGFloat const kGleapScreenshotMaxLongEdge = 2560;
static CGFloat const kGleapScreenshotJPEGQuality = 0.85;
static NSUInteger const kGleapMaxLogsBytes = 20 * 1024 * 1024;
static NSTimeInterval const kGleapLogFlushTimeout = 0.5;
static NSUInteger const kGleapMaxRememberedRequests = 200;
// A logs request that keeps failing for network reasons (offline, 408, 429, 5xx) is tried this often in all...
static NSUInteger const kGleapMaxLogsAttempts = 3;
// ...waiting this long before the second and the third try (about ten minutes in all). Then it is reported `failed`.
static NSTimeInterval const kGleapLogsRetryDelays[] = { 120, 480 };
static NSString * const kGleapRecordingFileName = @"screen-recording.mp4";
// Recordings and upload bodies live in tmp/GleapCapture/<capture>/ while a capture runs.
static NSString * const kGleapCaptureDirectoryName = @"GleapCapture";
static NSString * const kGleapLeftoverPrefix = @"GleapCapture-leftover-";

// The step of a logs request an answer belongs to.
typedef NS_ENUM(NSInteger, GleapLogsStep) {
    GleapLogsStepUnsupported,
    GleapLogsStepClaim,
    GleapLogsStepUpload,
};

typedef NS_ENUM(NSInteger, GleapCaptureSessionState) {
    GleapCaptureSessionStateMinimizing,
    GleapCaptureSessionStateBar,
    GleapCaptureSessionStateCapturing,
    GleapCaptureSessionStateRecording,
    GleapCaptureSessionStateFinishing,
    GleapCaptureSessionStatePreview,
    GleapCaptureSessionStateUploading,
    GleapCaptureSessionStateEnded,
};

#pragma mark - Session

/// One interactive capture (screenshot or recording) from capture-start until the widget is back.
GLEAP_INTERNAL
@interface GleapCaptureSession : NSObject
@property (nonatomic, copy) NSString *requestId;
@property (nonatomic, copy) NSString *kind;
@property (nonatomic, assign) BOOL attachLogs;
@property (nonatomic, copy) NSDictionary *include;
@property (nonatomic, assign) NSTimeInterval maxDuration;
@property (nonatomic, strong) GleapCaptureLabels *labels;
@property (nonatomic, assign) GleapCaptureSessionState state;
@property (nonatomic, strong) NSDate *startedAt;
@property (nonatomic, weak, nullable) UIWindowScene *scene;
@property (nonatomic, strong, nullable) GleapCaptureOverlay *overlay;
@property (nonatomic, strong, nullable) id<GleapScreenRecorder> recorder;
@property (nonatomic, strong, nullable) GleapRecordingResult *recording;
@property (nonatomic, copy, nullable) NSString *uploadedFileUrl;
@property (nonatomic, strong, nullable) id<GleapCaptureCancellable> upload;
@property (nonatomic, strong, nullable) NSTimer *elapsedTimer;
@property (nonatomic, strong) NSURL *workDirectory;
@property (nonatomic, assign) double lastSentProgress;
@property (nonatomic, assign) CFTimeInterval lastProgressSentAt;
@end

@implementation GleapCaptureSession
@end

#pragma mark - Manager

@interface GleapCaptureManager () <GleapCaptureOverlayDelegate, GleapScreenRecorderDelegate> {
    BOOL _captureEnabled;
    BOOL _remoteLogCollectionEnabled;
    GleapLogFlushHandler _logFlushHandler;
}
@property (nonatomic, strong) NSHashTable<UIView *> *maskedViewTable;
@property (nonatomic, strong, nullable) GleapCaptureSession *session;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *finishedLogRequests;
@property (nonatomic, strong) NSMutableSet<NSString *> *runningLogRequests;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *logRequestAttempts;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *logRequestRetryAt;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *attachedLogRequests;
// The last capture-image (until the widget is done with its request) and the last capture-state for the widget. They
// go to the widget again when its page had to be loaded again (its web content process ended).
@property (nonatomic, copy, nullable) NSDictionary *pendingImageMessage;
@property (nonatomic, copy, nullable) NSDictionary *lastStateMessage;
@end

@implementation GleapCaptureManager

+ (instancetype)sharedInstance {
    static GleapCaptureManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GleapCaptureManager alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _captureEnabled = YES;
        _remoteLogCollectionEnabled = YES;
        _maskedViewTable = [NSHashTable weakObjectsHashTable];
        _finishedLogRequests = [NSMutableOrderedSet orderedSet];
        _runningLogRequests = [NSMutableSet set];
        _logRequestAttempts = [NSMutableDictionary dictionary];
        _logRequestRetryAt = [NSMutableDictionary dictionary];
        _attachedLogRequests = [NSMutableOrderedSet orderedSet];
    }
    return self;
}

#pragma mark - Settings

- (BOOL)captureEnabled {
    @synchronized (self) {
        return _captureEnabled;
    }
}

- (void)setCaptureEnabled:(BOOL)captureEnabled {
    @synchronized (self) {
        _captureEnabled = captureEnabled;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            GleapCaptureSession *session = self.session;
            if (!captureEnabled && session != nil) {
                [self finishSession: session widgetState: @"cancelled" error: @"capture-disabled" eventType: @"released" restore: YES];
            }
            [self sendCapabilitiesToWidget];
        } @catch (NSException *exception) {}
    });
}

- (BOOL)remoteLogCollectionEnabled {
    @synchronized (self) {
        return _remoteLogCollectionEnabled;
    }
}

- (void)setRemoteLogCollectionEnabled:(BOOL)remoteLogCollectionEnabled {
    @synchronized (self) {
        _remoteLogCollectionEnabled = remoteLogCollectionEnabled;
    }
}

- (GleapLogFlushHandler)logFlushHandler {
    @synchronized (self) {
        return _logFlushHandler;
    }
}

- (void)setLogFlushHandler:(GleapLogFlushHandler)logFlushHandler {
    @synchronized (self) {
        _logFlushHandler = [logFlushHandler copy];
    }
}

- (void)maskView:(UIView *)view {
    if (![view isKindOfClass: [UIView class]]) {
        return;
    }
    [self onMainQueue:^{
        [self.maskedViewTable addObject: view];
    }];
}

- (void)unmaskView:(UIView *)view {
    if (![view isKindOfClass: [UIView class]]) {
        return;
    }
    [self onMainQueue:^{
        [self.maskedViewTable removeObject: view];
    }];
}

- (NSArray<UIView *> *)maskedViews {
    return self.maskedViewTable.allObjects ?: @[];
}

- (void)onMainQueue:(dispatch_block_t)block {
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

#pragma mark - Capabilities

- (NSArray<NSString *> *)sdkCapabilities {
    NSMutableArray<NSString *> *capabilities = [NSMutableArray array];
    if (self.captureEnabled) {
        [capabilities addObject: @"capture.screenshot"];
        [capabilities addObject: @"capture.recording"];
    }
    if (self.remoteLogCollectionEnabled) {
        [capabilities addObject: @"capture.logs"];
    }
    return capabilities;
}

- (NSDictionary *)widgetCapabilities {
    BOOL enabled = self.captureEnabled;
    return @{
        @"version": @1,
        @"platform": @"ios",
        @"sdkType": [GleapCaptureAPI sdkType],
        @"sdkVersion": SDK_VERSION,
        @"screenshot": @(enabled),
        @"recording": @(enabled),
        @"recordingMethod": @"frames",
        @"annotate": @YES,
        @"maxRecordingSec": @((NSInteger)kGleapMaxRecordingSeconds),
        @"microphone": @NO,
    };
}

- (void)sendCapabilitiesToWidget {
    [self sendToWidget: @"capture-capabilities" data: [self widgetCapabilities]];
}

#pragma mark - Widget messages

- (BOOL)widgetConnected {
    GleapWidgetManager *widgetManager = [GleapWidgetManager sharedInstance];
    return widgetManager.widgetOpened && widgetManager.gleapWidget != nil && widgetManager.gleapWidget.connected;
}

// Only to the widget that is open right now: queued messages would reach the next widget session.
- (void)sendToWidget:(NSString *)name data:(NSDictionary *)data {
    if (![self widgetConnected]) {
        return;
    }
    [[GleapWidgetManager sharedInstance].gleapWidget sendMessageWithData: @{ @"name": name, @"data": data ?: @{} }];
}

- (void)sendState:(NSString *)state requestId:(NSString *)requestId extra:(NSDictionary *)extra {
    NSMutableDictionary *data = [NSMutableDictionary dictionaryWithDictionary: @{ @"requestId": requestId, @"state": state }];
    if (extra != nil) {
        [data addEntriesFromDictionary: extra];
    }
    self.lastStateMessage = data;
    [self sendToWidget: @"capture-state" data: data];
}

// The widget's page was loaded again (its web content process had ended): what it was told about the current
// request goes to it once more. A freshly loaded Messenger fetches the request and opens the editor for an image.
- (void)widgetPageDidReload {
    @try {
        NSDictionary *image = self.pendingImageMessage;
        NSDictionary *state = self.lastStateMessage;
        if (image != nil) {
            [self sendToWidget: @"capture-image" data: image];
        }
        if (state != nil && (image == nil || [state[@"requestId"] isEqual: image[@"requestId"]])) {
            [self sendToWidget: @"capture-state" data: state];
        }
    } @catch (NSException *exception) {
        NSLog(@"[GLEAP_SDK] Could not update the reloaded widget: %@", exception.reason);
    }
}

- (BOOL)handleWidgetMessage:(NSString *)name data:(id)data {
    if (![name isKindOfClass: [NSString class]] || ![name hasPrefix: @"capture-"]) {
        return NO;
    }
    @try {
        [self widgetMessageEndsPendingMessages: name data: data];
        if ([name isEqualToString: @"capture-start"]) {
            [self handleCaptureStart: data];
        } else if ([name isEqualToString: @"capture-cancel"]) {
            [self handleCaptureEnd: data widgetState: @"cancelled"];
        } else if ([name isEqualToString: @"capture-done"]) {
            [self handleCaptureEnd: data widgetState: nil];
        } else if ([name isEqualToString: @"capture-editor"]) {
            // Web hosts show the frame full-viewport for the editor; the native widget already is.
        } else {
            return NO;
        }
    } @catch (NSException *exception) {
        NSLog(@"[GLEAP_SDK] Capture request failed: %@", exception.reason);
        GleapCaptureSession *session = self.session;
        if (session != nil) {
            [self finishSession: session widgetState: @"failed" error: @"exception" eventType: @"failed" restore: YES];
        }
    }
    return YES;
}

// What waits for a reload of the widget's page is dropped once the widget is done with its request (done, cancel)
// or starts a capture (again).
- (void)widgetMessageEndsPendingMessages:(NSString *)name data:(id)data {
    BOOL starts = [name isEqualToString: @"capture-start"];
    if (!starts && ![name isEqualToString: @"capture-done"] && ![name isEqualToString: @"capture-cancel"]) {
        return;
    }
    id requestId = [data isKindOfClass: [NSDictionary class]] ? data[@"requestId"] : nil;
    if (starts || [self.pendingImageMessage[@"requestId"] isEqual: requestId]) {
        self.pendingImageMessage = nil;
    }
    if (!starts && [self.lastStateMessage[@"requestId"] isEqual: requestId]) {
        self.lastStateMessage = nil;
    }
}

- (void)handleCaptureStart:(id)data {
    NSDictionary *message = [data isKindOfClass: [NSDictionary class]] ? data : nil;
    NSString *requestId = message[@"requestId"];
    if (![GleapCaptureAPI isValidRequestId: requestId]) {
        return;
    }
    NSString *kind = [message[@"kind"] isKindOfClass: [NSString class]] ? message[@"kind"] : nil;
    if (![kind isEqualToString: @"screenshot"] && ![kind isEqualToString: @"recording"]) {
        [self sendState: @"unsupported" requestId: requestId extra: @{ @"error": @"unsupported-kind" }];
        [GleapCaptureAPI postEventType: @"unsupported" reason: @"unsupported-kind" requestId: requestId completion: nil];
        return;
    }
    if (!self.captureEnabled) {
        [self sendState: @"unsupported" requestId: requestId extra: @{ @"error": @"capture-disabled" }];
        [GleapCaptureAPI postEventType: @"unsupported" reason: @"capture-disabled" requestId: requestId completion: nil];
        return;
    }
    NSDictionary *options = [message[@"options"] isKindOfClass: [NSDictionary class]] ? message[@"options"] : @{};

    GleapCaptureSession *current = self.session;
    if (current != nil) {
        if ([current.requestId isEqualToString: requestId] && current.state == GleapCaptureSessionStateBar) {
            // The same request again (e.g. switching between screenshot and recording): only the bar changes.
            [self configureSession: current kind: kind options: options labels: message[@"labels"]];
            [current.overlay showBarMode: [self readyModeForSession: current]];
            [self sendState: @"bar" requestId: current.requestId extra: nil];
            return;
        }
        // A new request replaces the running one, which goes back to the server.
        [self finishSession: current widgetState: nil error: @"replaced" eventType: @"released" restore: NO];
    }

    GleapCaptureSession *session = [[GleapCaptureSession alloc] init];
    session.requestId = requestId;
    [self configureSession: session kind: kind options: options labels: message[@"labels"]];
    session.startedAt = [NSDate date];
    session.state = GleapCaptureSessionStateMinimizing;
    session.workDirectory = [[self captureDirectory] URLByAppendingPathComponent: [NSUUID UUID].UUIDString isDirectory: YES];
    self.session = session;

    __weak typeof(self) weakSelf = self;
    [[GleapWidgetManager sharedInstance] minimizeWidgetWithCompletion:^(BOOL minimized, UIWindowScene * _Nullable scene) {
        [weakSelf widgetDidMinimize: minimized scene: scene session: session];
    }];
}

- (void)configureSession:(GleapCaptureSession *)session kind:(NSString *)kind options:(NSDictionary *)options labels:(id)labels {
    session.kind = kind;
    id attachLogs = options[@"attachLogs"];
    session.attachLogs = [attachLogs isKindOfClass: [NSNumber class]] ? [attachLogs boolValue] : YES;
    id maxDuration = options[@"maxDurationSec"];
    double seconds = [maxDuration isKindOfClass: [NSNumber class]] ? [maxDuration doubleValue] : kGleapDefaultRecordingSeconds;
    if (!isfinite(seconds)) {
        seconds = kGleapDefaultRecordingSeconds;
    }
    session.maxDuration = MIN(kGleapMaxRecordingSeconds, MAX(kGleapMinRecordingSeconds, seconds));
    session.include = [GleapLogsBundle normalizedInclude: options[@"include"]];
    session.labels = [[GleapCaptureLabels alloc] initWithLabels: labels];
}

- (GleapCaptureBarMode)readyModeForSession:(GleapCaptureSession *)session {
    return [session.kind isEqualToString: @"recording"] ? GleapCaptureBarModeRecordReady : GleapCaptureBarModeScreenshot;
}

- (void)widgetDidMinimize:(BOOL)minimized scene:(UIWindowScene *)scene session:(GleapCaptureSession *)session {
    @try {
        if (self.session != session || session.state != GleapCaptureSessionStateMinimizing) {
            // The capture ended while the widget was on its way down: it comes back, unless another capture runs.
            if (minimized && self.session == nil) {
                [self restoreWidgetThen: nil];
            }
            return;
        }
        if (!minimized) {
            [self finishSession: session widgetState: @"failed" error: @"minimize-failed" eventType: @"failed" restore: YES];
            return;
        }
        UIWindowScene *captureScene = scene ?: [GleapCaptureRenderer foregroundWindowScene];
        GleapCaptureOverlay *overlay = captureScene != nil ? [[GleapCaptureOverlay alloc] initWithScene: captureScene labels: session.labels accentColor: [self accentColor] delegate: self] : nil;
        if (overlay == nil) {
            [self finishSession: session widgetState: @"failed" error: @"no-window-scene" eventType: @"failed" restore: YES];
            return;
        }
        session.scene = captureScene;
        session.overlay = overlay;
        session.state = GleapCaptureSessionStateBar;
        [overlay showBarMode: [self readyModeForSession: session]];
        [self sendState: @"bar" requestId: session.requestId extra: nil];
    } @catch (NSException *exception) {
        [self finishSession: session widgetState: @"failed" error: @"exception" eventType: @"failed" restore: YES];
    }
}

- (void)handleCaptureEnd:(id)data widgetState:(NSString *)widgetState {
    NSDictionary *message = [data isKindOfClass: [NSDictionary class]] ? data : nil;
    NSString *requestId = message[@"requestId"];
    GleapCaptureSession *session = self.session;
    if (session != nil && [requestId isKindOfClass: [NSString class]] && [session.requestId isEqualToString: requestId]) {
        // The widget ended it (withdrawn, answered elsewhere, finished): nothing to give back to the server.
        [self finishSession: session widgetState: widgetState error: nil eventType: nil restore: YES];
        return;
    }
    if (session == nil && [GleapWidgetManager sharedInstance].widgetMinimized) {
        [self restoreWidgetThen: nil];
    }
}

- (void)widgetWillClose {
    [self onMainQueue:^{
        @try {
            self.pendingImageMessage = nil;
            self.lastStateMessage = nil;
            GleapCaptureSession *session = self.session;
            if (session != nil) {
                [self finishSession: session widgetState: nil error: @"widget-closed" eventType: @"released" restore: NO];
            }
        } @catch (NSException *exception) {}
    }];
}

- (BOOL)isRecording {
    GleapCaptureSession *session = self.session;
    return session != nil && (session.state == GleapCaptureSessionStateRecording || session.state == GleapCaptureSessionStateFinishing);
}

- (BOOL)hasActiveCapture {
    return self.session != nil;
}

#pragma mark - Ending a session

// Ends `session`: stops recording and uploading, removes its files and UI, optionally tells the server
// (`eventType`), brings the widget back (`restore`) and tells it the outcome (`widgetState`).
- (void)finishSession:(GleapCaptureSession *)session
          widgetState:(NSString *)widgetState
                error:(NSString *)error
            eventType:(NSString *)eventType
              restore:(BOOL)restore {
    if (session == nil || session.state == GleapCaptureSessionStateEnded) {
        return;
    }
    session.state = GleapCaptureSessionStateEnded;
    if (self.session == session) {
        self.session = nil;
    }
    [session.elapsedTimer invalidate];
    session.elapsedTimer = nil;
    session.recorder.delegate = nil;
    [session.recorder cancel];
    session.recorder = nil;
    [session.upload cancel];
    session.upload = nil;
    [self removeItemAtURL: session.workDirectory];
    if (eventType != nil) {
        [GleapCaptureAPI postEventType: eventType reason: error requestId: session.requestId completion: nil];
    }

    NSString *requestId = session.requestId;
    GleapCaptureOverlay *overlay = session.overlay;
    session.overlay = nil;
    __weak typeof(self) weakSelf = self;
    void (^afterTearDown)(void) = ^{
        void (^notify)(void) = ^{
            if (widgetState != nil) {
                [weakSelf sendState: widgetState requestId: requestId extra: (error != nil && ![widgetState isEqualToString: @"cancelled"]) ? @{ @"error": error } : nil];
            }
        };
        if (restore) {
            [weakSelf restoreWidgetThen:^(BOOL restored) {
                notify();
            }];
        } else {
            notify();
        }
    };
    if (overlay != nil) {
        [overlay tearDownWithCompletion: afterTearDown];
    } else {
        afterTearDown();
    }
}

- (void)restoreWidgetThen:(void (^)(BOOL restored))completion {
    GleapWidgetManager *widgetManager = [GleapWidgetManager sharedInstance];
    // Not while another capture starts: the widget stays down for it.
    if (self.session != nil) {
        if (completion) {
            completion(widgetManager.widgetOpened);
        }
        return;
    }
    // Queued behind a minimize still under way, so a widget on its way down comes back too.
    [widgetManager restoreWidgetWithCompletion:^(BOOL restored) {
        if (completion) {
            completion(restored);
        }
    }];
}

#pragma mark - Overlay actions

- (void)captureOverlayDidTapCapture {
    GleapCaptureSession *session = self.session;
    if (session == nil || session.state != GleapCaptureSessionStateBar || ![session.kind isEqualToString: @"screenshot"]) {
        return;
    }
    session.state = GleapCaptureSessionStateCapturing;
    [self sendState: @"capturing" requestId: session.requestId extra: nil];
    __weak typeof(self) weakSelf = self;
    __weak GleapCaptureSession *weakSession = session;
    [session.overlay setBarHidden: YES animated: YES completion:^{
        // Let the hidden bar reach the screen, then take the shot.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.06 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            GleapCaptureSession *capturingSession = weakSession;
            if (capturingSession != nil) {
                [weakSelf takeScreenshotForSession: capturingSession];
            }
        });
    }];
}

- (void)takeScreenshotForSession:(GleapCaptureSession *)session {
    if (self.session != session || session.state != GleapCaptureSessionStateCapturing) {
        return;
    }
    UIImage *image = nil;
    @try {
        UIWindowScene *scene = session.scene ?: [GleapCaptureRenderer foregroundWindowScene];
        if (scene != nil && UIApplication.sharedApplication.applicationState == UIApplicationStateActive) {
            image = [GleapCaptureRenderer screenshotOfScene: scene maxLongEdge: kGleapScreenshotMaxLongEdge maskedViews: [self maskedViews]];
        }
    } @catch (NSException *exception) {
        image = nil;
    }
    if (image == nil) {
        [self finishSession: session widgetState: @"failed" error: @"capture-failed" eventType: @"failed" restore: YES];
        return;
    }
    NSDate *capturedAt = [NSDate date];
    CGSize pixelSize = CGSizeMake(round(image.size.width * image.scale), round(image.size.height * image.scale));
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *dataUrl = nil;
        @autoreleasepool {
            NSData *jpeg = UIImageJPEGRepresentation(image, kGleapScreenshotJPEGQuality);
            if (jpeg.length > 0) {
                dataUrl = [@"data:image/jpeg;base64," stringByAppendingString: [jpeg base64EncodedStringWithOptions: 0]];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf deliverScreenshot: dataUrl size: pixelSize capturedAt: capturedAt session: session];
        });
    });
}

- (void)deliverScreenshot:(NSString *)dataUrl size:(CGSize)size capturedAt:(NSDate *)capturedAt session:(GleapCaptureSession *)session {
    if (self.session != session || session.state != GleapCaptureSessionStateCapturing) {
        return;
    }
    if (dataUrl == nil) {
        [self finishSession: session widgetState: @"failed" error: @"encoding-failed" eventType: @"failed" restore: YES];
        return;
    }
    // The capture is done; annotating and sending happen in the widget.
    session.state = GleapCaptureSessionStateEnded;
    self.session = nil;
    [self removeItemAtURL: session.workDirectory];
    NSString *requestId = session.requestId;
    BOOL attachLogs = session.attachLogs;
    NSDictionary *include = session.include;
    NSDate *startedAt = session.startedAt;
    GleapCaptureOverlay *overlay = session.overlay;
    session.overlay = nil;
    __weak typeof(self) weakSelf = self;
    [overlay tearDownWithCompletion:^{
        [weakSelf restoreWidgetThen:^(BOOL restored) {
            if (!restored) {
                // Nothing to show the widget on any more: the request goes back to the server.
                [GleapCaptureAPI postEventType: @"released" reason: @"widget-unavailable" requestId: requestId completion: nil];
                return;
            }
            NSDictionary *image = @{
                @"requestId": requestId,
                @"dataUrl": dataUrl,
                @"width": @((NSInteger)size.width),
                @"height": @((NSInteger)size.height),
                @"method": @"frames",
                @"platform": @"ios",
                @"sdkType": [GleapCaptureAPI sdkType],
                @"sdkVersion": SDK_VERSION,
            };
            // Kept until the widget is done with the request, in case its page has to be loaded again.
            weakSelf.pendingImageMessage = image;
            [weakSelf sendToWidget: @"capture-image" data: image];
            [weakSelf sendState: @"preview" requestId: requestId extra: nil];
            if (attachLogs) {
                [weakSelf uploadLogsForCaptureRequest: requestId include: include windowStart: startedAt windowEnd: capturedAt];
            }
        }];
    }];
}

- (void)captureOverlayDidTapStart {
    GleapCaptureSession *session = self.session;
    if (session == nil || session.state != GleapCaptureSessionStateBar || ![session.kind isEqualToString: @"recording"]) {
        return;
    }
    UIWindowScene *scene = session.scene ?: [GleapCaptureRenderer foregroundWindowScene];
    __weak typeof(self) weakSelf = self;
    GleapFrameRecorder *recorder = scene != nil ? [[GleapFrameRecorder alloc] initWithScene: scene outputDirectory: session.workDirectory maxDuration: session.maxDuration maskedViewsProvider:^NSArray<UIView *> * {
        return [weakSelf maskedViews] ?: @[];
    }] : nil;
    recorder.delegate = self;
    NSError *error = nil;
    BOOL started = NO;
    @try {
        started = recorder != nil && [recorder startWithError: &error];
    } @catch (NSException *exception) {
        started = NO;
    }
    if (!started) {
        NSLog(@"[GLEAP_SDK] The screen recording could not start: %@", error.localizedDescription);
        [recorder cancel];
        [self finishSession: session widgetState: @"failed" error: @"recording-failed" eventType: @"failed" restore: YES];
        return;
    }
    session.recorder = recorder;
    session.state = GleapCaptureSessionStateRecording;
    [session.overlay showBarMode: GleapCaptureBarModeRecording];
    [session.overlay updateElapsed: 0 maxDuration: session.maxDuration];
    __weak GleapCaptureSession *weakSession = session;
    session.elapsedTimer = [NSTimer timerWithTimeInterval: 0.5 repeats: YES block:^(NSTimer * _Nonnull timer) {
        [weakSelf recordingTickForSession: weakSession];
    }];
    [[NSRunLoop mainRunLoop] addTimer: session.elapsedTimer forMode: NSRunLoopCommonModes];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, [session.labels text: @"barRecording"]);
    [self sendState: @"recording" requestId: session.requestId extra: @{ @"elapsedSec": @0 }];
}

- (void)recordingTickForSession:(GleapCaptureSession *)session {
    if (session == nil || self.session != session || session.state != GleapCaptureSessionStateRecording) {
        return;
    }
    NSTimeInterval elapsed = session.recorder.recordedDuration;
    [session.overlay updateElapsed: elapsed maxDuration: session.maxDuration];
    if (elapsed >= session.maxDuration) {
        [self stopRecordingForSession: session];
    }
}

- (void)captureOverlayDidTapStop {
    [self stopRecordingForSession: self.session];
}

- (void)stopRecordingForSession:(GleapCaptureSession *)session {
    if (session == nil || self.session != session || session.state != GleapCaptureSessionStateRecording) {
        return;
    }
    session.state = GleapCaptureSessionStateFinishing;
    [session.elapsedTimer invalidate];
    session.elapsedTimer = nil;
    [session.overlay updateElapsed: session.recorder.recordedDuration maxDuration: session.maxDuration];
    [session.overlay showBarMode: GleapCaptureBarModeBusy];
    __weak typeof(self) weakSelf = self;
    [session.recorder stopWithCompletion:^(GleapRecordingResult * _Nullable result, NSError * _Nullable error) {
        [weakSelf recordingDidFinish: result error: error session: session];
    }];
}

- (void)recordingDidFinish:(GleapRecordingResult *)result error:(NSError *)error session:(GleapCaptureSession *)session {
    if (self.session != session || session.state != GleapCaptureSessionStateFinishing) {
        if (result.fileURL != nil) {
            [self removeItemAtURL: result.fileURL];
        }
        return;
    }
    session.recorder.delegate = nil;
    session.recorder = nil;
    if (result == nil || result.fileURL == nil) {
        NSLog(@"[GLEAP_SDK] The screen recording failed: %@", error.localizedDescription);
        [self finishSession: session widgetState: @"failed" error: @"recording-failed" eventType: @"failed" restore: YES];
        return;
    }
    session.recording = result;
    session.uploadedFileUrl = nil;
    session.state = GleapCaptureSessionStatePreview;
    [session.overlay setBarHidden: YES animated: YES completion: nil];
    [session.overlay presentPreviewWithFileURL: result.fileURL];
    [self sendState: @"preview" requestId: session.requestId extra: nil];
}

- (void)captureOverlayDidTapCancel {
    GleapCaptureSession *session = self.session;
    if (session == nil || (session.state != GleapCaptureSessionStateBar && session.state != GleapCaptureSessionStateMinimizing)) {
        return;
    }
    [self finishSession: session widgetState: @"cancelled" error: nil eventType: @"released" restore: YES];
}

- (void)captureOverlayDidTapPreviewCancel {
    GleapCaptureSession *session = self.session;
    if (session == nil || (session.state != GleapCaptureSessionStatePreview && session.state != GleapCaptureSessionStateUploading)) {
        return;
    }
    [self finishSession: session widgetState: @"cancelled" error: nil eventType: @"released" restore: YES];
}

- (void)captureOverlayPreviewWasDismissed {
    GleapCaptureSession *session = self.session;
    if (session == nil || (session.state != GleapCaptureSessionStatePreview && session.state != GleapCaptureSessionStateUploading)) {
        return;
    }
    [self finishSession: session widgetState: @"cancelled" error: @"preview-dismissed" eventType: @"released" restore: YES];
}

- (void)captureOverlayDidTapRetake {
    GleapCaptureSession *session = self.session;
    if (session == nil || session.state != GleapCaptureSessionStatePreview) {
        return;
    }
    if (session.recording.fileURL != nil) {
        [self removeItemAtURL: session.recording.fileURL];
    }
    session.recording = nil;
    session.uploadedFileUrl = nil;
    session.state = GleapCaptureSessionStateBar;
    __weak typeof(self) weakSelf = self;
    [session.overlay dismissPreviewWithCompletion:^{
        if (weakSelf.session != session || session.state != GleapCaptureSessionStateBar) {
            return;
        }
        [session.overlay showBarMode: GleapCaptureBarModeRecordReady];
        [weakSelf sendState: @"bar" requestId: session.requestId extra: nil];
    }];
}

- (void)captureOverlayDidTapSend {
    GleapCaptureSession *session = self.session;
    if (session == nil || session.state != GleapCaptureSessionStatePreview || session.recording == nil) {
        return;
    }
    session.state = GleapCaptureSessionStateUploading;
    session.lastSentProgress = 0;
    session.lastProgressSentAt = CACurrentMediaTime();
    [session.overlay setPreviewUploadProgress: 0];
    [self sendState: @"uploading" requestId: session.requestId extra: @{ @"progress": @0 }];
    if (session.uploadedFileUrl != nil) {
        // Uploaded before, only /complete failed: don't upload the video again.
        [session.overlay setPreviewUploadProgress: 1];
        [self completeRecordingForSession: session fileUrl: session.uploadedFileUrl];
        return;
    }
    __weak typeof(self) weakSelf = self;
    session.upload = [GleapCaptureAPI uploadFileAtURL: session.recording.fileURL fileName: kGleapRecordingFileName contentType: @"video/mp4" progress:^(double fraction) {
        [weakSelf uploadProgress: fraction session: session];
    } completion:^(NSString * _Nullable fileUrl, NSInteger statusCode, NSError * _Nullable error) {
        [weakSelf uploadDidFinish: fileUrl statusCode: statusCode error: error session: session];
    }];
}

- (void)uploadProgress:(double)fraction session:(GleapCaptureSession *)session {
    if (self.session != session || session.state != GleapCaptureSessionStateUploading) {
        return;
    }
    [session.overlay setPreviewUploadProgress: fraction];
    CFTimeInterval now = CACurrentMediaTime();
    if (fraction - session.lastSentProgress >= 0.1 || (fraction > session.lastSentProgress && now - session.lastProgressSentAt >= 1.0)) {
        session.lastSentProgress = fraction;
        session.lastProgressSentAt = now;
        [self sendState: @"uploading" requestId: session.requestId extra: @{ @"progress": @(round(fraction * 100) / 100) }];
    }
}

- (void)uploadDidFinish:(NSString *)fileUrl statusCode:(NSInteger)statusCode error:(NSError *)error session:(GleapCaptureSession *)session {
    if (self.session != session || session.state != GleapCaptureSessionStateUploading) {
        return;
    }
    session.upload = nil;
    if (fileUrl == nil) {
        NSLog(@"[GLEAP_SDK] The screen recording upload failed (%ld): %@", (long)statusCode, error.localizedDescription);
        session.state = GleapCaptureSessionStatePreview;
        [session.overlay setPreviewErrorMessage: [session.labels text: @"failed"]];
        [self sendState: @"preview" requestId: session.requestId extra: @{ @"error": @"upload-failed" }];
        return;
    }
    session.uploadedFileUrl = fileUrl;
    [self completeRecordingForSession: session fileUrl: fileUrl];
}

- (void)completeRecordingForSession:(GleapCaptureSession *)session fileUrl:(NSString *)fileUrl {
    GleapRecordingResult *recording = session.recording;
    NSMutableDictionary *file = [@{
        @"url": fileUrl,
        @"name": kGleapRecordingFileName,
        @"type": @"video/mp4",
        @"width": @(recording.width),
        @"height": @(recording.height),
        @"durationMs": @((long long)llround(recording.duration * 1000.0)),
    } mutableCopy];
    if (recording.fileSize > 0) {
        file[@"size"] = @(recording.fileSize);
    }
    NSMutableDictionary *body = [@{
        @"files": @[file],
        @"method": @"frames",
        @"platform": @"ios",
        @"sdkType": [GleapCaptureAPI sdkType],
        @"sdkVersion": SDK_VERSION,
        @"deviceId": [GleapCaptureAPI deviceId],
    } mutableCopy];
    if (recording.startedAt != nil) {
        body[@"recordingStartedAt"] = [GleapUIHelper getJSStringForNSDate: recording.startedAt];
    }
    if (recording.endedAt != nil) {
        body[@"recordingEndedAt"] = [GleapUIHelper getJSStringForNSDate: recording.endedAt];
    }
    __weak typeof(self) weakSelf = self;
    [GleapCaptureAPI completeRequest: session.requestId body: body completion:^(NSInteger statusCode, NSDictionary * _Nullable response, NSError * _Nullable error) {
        [weakSelf completeDidFinish: statusCode error: error session: session];
    }];
}

- (void)completeDidFinish:(NSInteger)statusCode error:(NSError *)error session:(GleapCaptureSession *)session {
    if (self.session != session || session.state != GleapCaptureSessionStateUploading) {
        return;
    }
    if (statusCode >= 200 && statusCode < 300) {
        NSString *requestId = session.requestId;
        BOOL attachLogs = session.attachLogs;
        NSDictionary *include = session.include;
        NSDate *startedAt = session.recording.startedAt ?: session.startedAt;
        NSDate *endedAt = session.recording.endedAt ?: [NSDate date];
        [self finishSession: session widgetState: @"done" error: nil eventType: nil restore: YES];
        if (attachLogs) {
            [self uploadLogsForCaptureRequest: requestId include: include windowStart: startedAt windowEnd: endedAt];
        }
        return;
    }
    if (statusCode == 400 || statusCode == 403 || statusCode == 404 || statusCode == 409 || statusCode == 410 || statusCode == 422) {
        // Final: answered elsewhere, withdrawn, expired or refused. Only a refused body leaves a claim to release.
        NSString *reason = [NSString stringWithFormat: @"complete-%ld", (long)statusCode];
        BOOL release = statusCode == 400 || statusCode == 422;
        [self finishSession: session widgetState: @"failed" error: reason eventType: release ? @"failed" : nil restore: YES];
        return;
    }
    // Offline or a server error: the recording stays and Send tries again.
    NSLog(@"[GLEAP_SDK] Completing the capture request failed (%ld): %@", (long)statusCode, error.localizedDescription);
    session.state = GleapCaptureSessionStatePreview;
    [session.overlay setPreviewErrorMessage: [session.labels text: @"failed"]];
    [self sendState: @"preview" requestId: session.requestId extra: @{ @"error": @"complete-failed" }];
}

#pragma mark - GleapScreenRecorderDelegate

- (void)screenRecorderDidReachMaxDuration:(id<GleapScreenRecorder>)recorder {
    GleapCaptureSession *session = self.session;
    if (session.recorder == recorder) {
        [self stopRecordingForSession: session];
    }
}

- (void)screenRecorderDidReceiveMemoryWarning:(id<GleapScreenRecorder>)recorder {
    // Keep what was recorded rather than risk the app.
    GleapCaptureSession *session = self.session;
    if (session.recorder == recorder) {
        [self stopRecordingForSession: session];
    }
}

- (void)screenRecorder:(id<GleapScreenRecorder>)recorder didFailWithError:(NSError *)error {
    NSLog(@"[GLEAP_SDK] The screen recording stopped: %@", error.localizedDescription);
    GleapCaptureSession *session = self.session;
    if (session.recorder == recorder) {
        // Whatever was written before the failure is kept; with nothing, the stop reports the failure.
        [self stopRecordingForSession: session];
    }
}

#pragma mark - Background logs

- (void)handleCaptureRequests:(id)requests {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handleCaptureRequests: requests];
        });
        return;
    }
    @try {
        NSArray *list = [requests isKindOfClass: [NSArray class]] ? requests : ([requests isKindOfClass: [NSDictionary class]] ? @[requests] : @[]);
        for (id item in list) {
            if (![item isKindOfClass: [NSDictionary class]]) {
                continue;
            }
            NSString *requestId = item[@"id"];
            // Screenshots and recordings reach the customer through the widget's card, only logs come this way.
            if (![GleapCaptureAPI isValidRequestId: requestId] || ![item[@"kind"] isEqual: @"logs"] || [self isExpired: item[@"expiresAt"]]) {
                continue;
            }
            [self startLogsRequest: requestId options: [item[@"options"] isKindOfClass: [NSDictionary class]] ? item[@"options"] : @{}];
        }
    } @catch (NSException *exception) {
        NSLog(@"[GLEAP_SDK] Could not handle a capture request: %@", exception.reason);
    }
}

- (BOOL)isExpired:(id)expiresAt {
    if (![expiresAt isKindOfClass: [NSString class]]) {
        return NO;
    }
    static NSISO8601DateFormatter *withFractions = nil;
    static NSISO8601DateFormatter *withoutFractions = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        withFractions = [[NSISO8601DateFormatter alloc] init];
        withFractions.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
        withoutFractions = [[NSISO8601DateFormatter alloc] init];
        withoutFractions.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    });
    NSDate *date = [withFractions dateFromString: expiresAt] ?: [withoutFractions dateFromString: expiresAt];
    return date != nil && date.timeIntervalSinceNow < 0;
}

- (BOOL)hasSession {
    GleapSession *session = GleapSessionHelper.sharedInstance.currentSession;
    return session.gleapId.length > 0 && session.gleapHash.length > 0 && [Gleap sharedInstance].token.length > 0;
}

- (BOOL)backgroundLogsDisabledByProject {
    NSDictionary *capture = GleapConfigHelper.sharedInstance.config[@"capture"];
    if (![capture isKindOfClass: [NSDictionary class]]) {
        return NO;
    }
    id backgroundLogs = capture[@"backgroundLogs"];
    return [backgroundLogs isKindOfClass: [NSNumber class]] && ![backgroundLogs boolValue];
}

- (void)startLogsRequest:(NSString *)requestId options:(NSDictionary *)options {
    if ([self.finishedLogRequests containsObject: requestId] || [self.runningLogRequests containsObject: requestId]) {
        return;
    }
    NSDate *retryAt = self.logRequestRetryAt[requestId];
    if (retryAt != nil && retryAt.timeIntervalSinceNow > 0.5) {
        return;
    }
    if (![self hasSession]) {
        return;
    }
    [self.runningLogRequests addObject: requestId];
    __weak typeof(self) weakSelf = self;

    if (!self.remoteLogCollectionEnabled || [self backgroundLogsDisabledByProject]) {
        NSString *reason = self.remoteLogCollectionEnabled ? @"background-logs-disabled" : @"remote-log-collection-disabled";
        [GleapCaptureAPI postEventType: @"unsupported" reason: reason requestId: requestId completion:^(NSInteger statusCode, NSDictionary * _Nullable body, NSError * _Nullable error) {
            [weakSelf logsRequest: requestId step: GleapLogsStepUnsupported didFinishWithStatus: statusCode options: options];
        }];
        return;
    }

    [GleapCaptureAPI claimRequest: requestId completion:^(NSInteger statusCode, NSDictionary * _Nullable body, NSError * _Nullable error) {
        [weakSelf logsRequest: requestId guarded:^{
            if (statusCode < 200 || statusCode >= 300) {
                [weakSelf logsRequest: requestId step: GleapLogsStepClaim didFinishWithStatus: statusCode options: options];
                return;
            }
            [weakSelf flushWrapperLogsThen:^{
                [weakSelf logsRequest: requestId guarded:^{
                    [GleapLogsBundle collectWithInclude: options[@"include"] windowStart: nil windowEnd: nil completion:^(NSDictionary * _Nonnull bundle) {
                        [weakSelf logsRequest: requestId guarded:^{
                            [weakSelf postLogsBundle: bundle requestId: requestId completion:^(NSInteger logsStatus) {
                                [weakSelf logsRequest: requestId step: GleapLogsStepUpload didFinishWithStatus: logsStatus options: options];
                            }];
                        }];
                    }];
                }];
            }];
        }];
    }];
}

// A step of a logs request that throws ends the attempt (it is not left running forever).
- (void)logsRequest:(NSString *)requestId guarded:(dispatch_block_t)block {
    @try {
        block();
    } @catch (NSException *exception) {
        NSLog(@"[GLEAP_SDK] Collecting logs for capture request %@ failed: %@", requestId, exception.reason);
        [self.runningLogRequests removeObject: requestId];
        [self rememberRequest: requestId in: self.finishedLogRequests];
        [GleapCaptureAPI postEventType: @"failed" reason: @"exception" requestId: requestId completion: nil];
    }
}

- (void)logsRequest:(NSString *)requestId step:(GleapLogsStep)step didFinishWithStatus:(NSInteger)statusCode options:(NSDictionary *)options {
    @try {
        [self.runningLogRequests removeObject: requestId];
        BOOL success = statusCode >= 200 && statusCode < 300;
        BOOL transient = statusCode == 0 || statusCode == 408 || statusCode == 429 || statusCode >= 500;
        if (!success && transient) {
            NSUInteger attempts = self.logRequestAttempts[requestId].unsignedIntegerValue + 1;
            if (attempts < kGleapMaxLogsAttempts) {
                // Offline or the server is busy: again a little later (a delivery before then is ignored).
                self.logRequestAttempts[requestId] = @(attempts);
                NSTimeInterval delay = kGleapLogsRetryDelays[MIN(attempts, (NSUInteger)(sizeof(kGleapLogsRetryDelays) / sizeof(kGleapLogsRetryDelays[0]))) - 1];
                self.logRequestRetryAt[requestId] = [NSDate dateWithTimeIntervalSinceNow: delay];
                __weak typeof(self) weakSelf = self;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [weakSelf logsRequest: requestId guarded:^{
                        [weakSelf startLogsRequest: requestId options: options];
                    }];
                });
                return;
            }
        }
        // Final: answered, refused, or out of tries. Never again from this device.
        [self rememberRequest: requestId in: self.finishedLogRequests];
        [self.logRequestAttempts removeObjectForKey: requestId];
        [self.logRequestRetryAt removeObjectForKey: requestId];
        if (success || step == GleapLogsStepUnsupported || statusCode == 409 || statusCode == 410) {
            return;
        }
        if (step == GleapLogsStepClaim && !transient) {
            // Not this device's to answer (gone, or no access).
            return;
        }
        // The server ends the request with this, instead of handing it out again.
        NSString *reason = transient ? [NSString stringWithFormat: @"logs-unreachable-%ld", (long)statusCode] : [NSString stringWithFormat: @"logs-%ld", (long)statusCode];
        [GleapCaptureAPI postEventType: @"failed" reason: reason requestId: requestId completion: nil];
    } @catch (NSException *exception) {
        NSLog(@"[GLEAP_SDK] Could not finish capture request %@: %@", requestId, exception.reason);
    }
}

// Logs for a screenshot / recording request with attachLogs: once per request, best effort.
- (void)uploadLogsForCaptureRequest:(NSString *)requestId include:(NSDictionary *)include windowStart:(NSDate *)windowStart windowEnd:(NSDate *)windowEnd {
    if (!self.remoteLogCollectionEnabled || [self.attachedLogRequests containsObject: requestId] || ![self hasSession]) {
        return;
    }
    [self rememberRequest: requestId in: self.attachedLogRequests];
    __weak typeof(self) weakSelf = self;
    [self flushWrapperLogsThen:^{
        [GleapLogsBundle collectWithInclude: include windowStart: windowStart windowEnd: windowEnd completion:^(NSDictionary * _Nonnull bundle) {
            [weakSelf postLogsBundle: bundle requestId: requestId completion:^(NSInteger statusCode) {
                if (statusCode < 200 || statusCode >= 300) {
                    NSLog(@"[GLEAP_SDK] The logs for capture request %@ were not accepted (%ld).", requestId, (long)statusCode);
                }
            }];
        }];
    }];
}

- (void)postLogsBundle:(NSDictionary *)bundle requestId:(NSString *)requestId completion:(void (^)(NSInteger statusCode))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSData *body = nil;
        @try {
            body = [GleapLogsBundle gzippedJSONForBundle: bundle maxBytes: kGleapMaxLogsBytes];
        } @catch (NSException *exception) {}
        dispatch_async(dispatch_get_main_queue(), ^{
            if (body == nil) {
                // Nothing that fits could be encoded: final, like a 413.
                completion(413);
                return;
            }
            [GleapCaptureAPI postLogs: body requestId: requestId completion:^(NSInteger statusCode, NSDictionary * _Nullable response, NSError * _Nullable error) {
                completion(statusCode);
            }];
        });
    });
}

// Gives a wrapper SDK (React Native, Flutter, Capacitor) up to 500 ms to hand over its buffered logs.
- (void)flushWrapperLogsThen:(void (^)(void))then {
    GleapLogFlushHandler handler = self.logFlushHandler;
    if (handler == nil) {
        then();
        return;
    }
    __block BOOL finished = NO;
    void (^finish)(void) = ^{
        if (finished) {
            return;
        }
        finished = YES;
        then();
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kGleapLogFlushTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), finish);
    void (^done)(void) = ^{
        dispatch_async(dispatch_get_main_queue(), finish);
    };
    @try {
        handler(done);
    } @catch (NSException *exception) {
        finish();
    }
}

- (void)rememberRequest:(NSString *)requestId in:(NSMutableOrderedSet<NSString *> *)set {
    [set addObject: requestId];
    while (set.count > kGleapMaxRememberedRequests) {
        [set removeObjectAtIndex: 0];
    }
}

#pragma mark - Helpers

- (UIColor *)accentColor {
    id color = GleapConfigHelper.sharedInstance.config[@"color"];
    if ([color isKindOfClass: [NSString class]] && [color hasPrefix: @"#"] && [color length] == 7) {
        return [GleapUIHelper colorFromHexString: color];
    }
    return nil;
}

- (NSURL *)captureDirectory {
    return [NSURL fileURLWithPath: [NSTemporaryDirectory() stringByAppendingPathComponent: kGleapCaptureDirectoryName] isDirectory: YES];
}

- (void)removeItemAtURL:(NSURL *)url {
    if (url == nil) {
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [[NSFileManager defaultManager] removeItemAtURL: url error: nil];
    });
}

+ (void)removeLeftoverFiles {
    @try {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *temporary = NSTemporaryDirectory();
        NSString *directory = [temporary stringByAppendingPathComponent: kGleapCaptureDirectoryName];
        if ([fileManager fileExistsAtPath: directory]) {
            // Moved aside at once (a capture right after starts in a new folder), deleted in the background.
            NSString *aside = [temporary stringByAppendingPathComponent: [kGleapLeftoverPrefix stringByAppendingString: [NSUUID UUID].UUIDString]];
            if (![fileManager moveItemAtPath: directory toPath: aside error: nil]) {
                [fileManager removeItemAtPath: directory error: nil];
            }
        }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
            for (NSString *name in [fileManager contentsOfDirectoryAtPath: temporary error: nil]) {
                if ([name hasPrefix: kGleapLeftoverPrefix]) {
                    [fileManager removeItemAtPath: [temporary stringByAppendingPathComponent: name] error: nil];
                }
            }
        });
    } @catch (NSException *exception) {}
}

@end
