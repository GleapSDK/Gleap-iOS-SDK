//
//  GleapScreenshotListener.m
//  
//
//  Created by Lukas Boehler on 27.05.22.
//

#import "GleapScreenshotListener.h"
#import "GleapCore.h"
#import "GleapActivationMethodHelper.h"

@implementation GleapScreenshotListener

/*
 Returns a shared instance (singleton).
 */
+ (instancetype)sharedInstance
{
    static GleapScreenshotListener *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GleapScreenshotListener alloc] init];
    });
    return sharedInstance;
}

- (id)init {
    self = [super init];
    return self;
}

- (void)start {
    @try {
        NSOperationQueue *mainQueue = [NSOperationQueue mainQueue];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationUserDidTakeScreenshotNotification
                                                          object:nil
                                                           queue:mainQueue
                                                      usingBlock:^(NSNotification *note) {
            if ([GleapActivationMethodHelper isActivationMethodActive: SCREENSHOT]) {
                [Gleap open];
            }
        }];
    } @catch(id anException) {}
}

@end
