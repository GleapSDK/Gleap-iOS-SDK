//
//  GleapReplayHelper.m
//  Gleap
//
//  Created by Lukas Boehler on 15.01.21.
//

#import "GleapReplayHelper.h"
#import "GleapCore.h"
#import "GleapTouchHelper.h"
#import "GleapScreenCaptureHelper.h"
#import "GleapUIHelper.h"
#import "GleapWidgetManager.h"
#import "GleapUploadManager.h"

// The replay keeps this many frames (5 minutes at the default 5 s interval).
static NSUInteger const kGleapMaxReplaySteps = 60;

@interface GleapReplayHelper ()
// Encodes the frames off the main thread.
@property (nonatomic, strong) dispatch_queue_t frameQueue;
@end

@implementation GleapReplayHelper

/*
 Returns a shared instance (singleton).
 */
+ (instancetype)sharedInstance
{
    static GleapReplayHelper *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GleapReplayHelper alloc] init];
    });
    return sharedInstance;
}

- (id)init {
    self = [super init];
    if (self) {
        [self initHelper];
    }
    return self;
}

- (void)initHelper {
    self.replaySteps = [[NSMutableArray alloc] init];
    self.running = false;
    self.timerInterval = 5;
    self.frameQueue = dispatch_queue_create("io.gleap.replay.frames", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillResignActive:) name: UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
}

- (void)appWillResignActive:(NSNotification*)notification {
    if (self.replayTimer) {
        [self.replayTimer invalidate];
    }
}

- (void)appWillEnterForeground:(NSNotification*)notification {
    // Reactivate the replays.
    if (self.running) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive) {
                [self start];
            }
        });
    }
}

- (void)start {
    self.running = true;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.running) {
            return;
        }
        // Starting again (after the app was in the background, or when the config is loaded again)
        // replaces the timer; it used to only stop it, which ended the replays for good.
        [self.replayTimer invalidate];
        self.replayTimer = [NSTimer scheduledTimerWithTimeInterval: self.timerInterval
                                             target: self
                                           selector: @selector(addReplayStep)
                                           userInfo: nil
                                            repeats: YES];
    });
}

- (void)stop {
    if (self.replayTimer) {
        [self.replayTimer invalidate];
    }
    self.running = false;
}

- (void)clear {
    self.replaySteps = [[NSMutableArray alloc] init];
}

- (void)addReplayStep {
    if ([[GleapWidgetManager sharedInstance] isOpened]) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive) {
            UIImage *screenshot = [GleapScreenCaptureHelper captureScreen];
            if (screenshot != nil) {
                NSMutableDictionary *step = [@{
                    @"screenname": [GleapUIHelper getTopMostViewControllerName],
                    @"interactions": [GleapTouchHelper getAndClearTouchEvents],
                    @"date": [GleapUIHelper getJSStringForNSDate: [[NSDate alloc] init]]
                } mutableCopy];
                // Frames are kept as they are uploaded (half size, JPEG): 60 full-resolution screenshots
                // held hundreds of megabytes.
                dispatch_async(self.frameQueue, ^{
                    NSData *imageData = nil;
                    @autoreleasepool {
                        imageData = [GleapUploadManager replayFrameDataForImage: screenshot];
                    }
                    if (imageData == nil) {
                        return;
                    }
                    step[@"imageData"] = imageData;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        while (self.replaySteps.count >= kGleapMaxReplaySteps) {
                            [self.replaySteps removeObjectAtIndex: 0];
                        }
                        [self.replaySteps addObject: [step copy]];
                    });
                });
            }
        }
    });
}

@end
