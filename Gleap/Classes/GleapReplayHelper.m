//
//  GleapReplayHelper.m
//  Gleap
//
//  Created by Lukas Boehler on 15.01.21.
//

#import "GleapReplayHelper.h"
#import "GleapCore.h"
#import "GleapTouchHelper.h"

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
}

- (void)start {
    if (self.running) {
        return;
    }
    self.running = true;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.replayTimer = [NSTimer scheduledTimerWithTimeInterval: 1
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
    if (self.replaySteps.count >= 60) {
        [self.replaySteps removeObjectAtIndex: 0];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIImage *screenshot = [[Gleap sharedInstance] captureScreen];
        NSString *currentViewControllerName = [[Gleap sharedInstance] getTopMostViewControllerName];
        
        [self.replaySteps addObject: @{
            @"screenname": currentViewControllerName,
            @"image": screenshot,
            @"interactions": [GleapTouchHelper getAndClearTouchEvents],
            @"date": [[Gleap sharedInstance] getJSStringForNSDate: [[NSDate alloc] init]]
        }];
    });
}

@end
