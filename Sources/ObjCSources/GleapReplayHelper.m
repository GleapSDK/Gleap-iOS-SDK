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
    if (self.running) {
        if (self.replayTimer != nil) {
            [self.replayTimer invalidate];
        }
        return;
    }
    self.running = true;
    dispatch_async(dispatch_get_main_queue(), ^{
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
    
    if (self.replaySteps.count >= 60) {
        [self.replaySteps removeObjectAtIndex: 0];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive) {
            UIImage *screenshot = [GleapScreenCaptureHelper captureScreen];
            if (screenshot != nil) {
                NSString *currentViewControllerName = [GleapUIHelper getTopMostViewControllerName];
                
                [self.replaySteps addObject: @{
                    @"screenname": currentViewControllerName,
                    @"image": screenshot,
                    @"interactions": [GleapTouchHelper getAndClearTouchEvents],
                    @"date": [GleapUIHelper getJSStringForNSDate: [[NSDate alloc] init]]
                }];
            }
        }
    });
}

@end
