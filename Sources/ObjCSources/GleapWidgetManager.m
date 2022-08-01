//
//  GleapWidgetManager.m
//  
//
//  Created by Lukas Boehler on 28.05.22.
//

#import "GleapWidgetManager.h"
#import "GleapUIHelper.h"
#import "GleapReplayHelper.h"
#import "GleapMetaDataHelper.h"
#import "GleapScreenshotManager.h"
#import "GleapCore.h"

@implementation GleapWidgetManager

/*
 Returns a shared instance (singleton).
 */
+ (instancetype)sharedInstance
{
    static GleapWidgetManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GleapWidgetManager alloc] init];
    });
    return sharedInstance;
}

- (id)init {
    self = [super init];
    if (self) {
        self.messageQueue = [[NSMutableArray alloc] init];
    }
    return self;
}

- (BOOL)isOpened {
    return self.gleapWidget != nil;
}

- (BOOL)isConnected {
    return self.gleapWidget != nil && self.gleapWidget.connected;
}

- (void)sendMessageWithData:(NSDictionary *)data {
    if ([self isConnected]) {
        [self.gleapWidget sendMessageWithData: data];
    } else {
        [self.messageQueue addObject: data];
    }
}

- (void)sendSessionUpdate {
    if ([self isConnected]) {
        [self.gleapWidget sendSessionUpdate];
    }
}

- (void)sendConfigUpdate {
    if ([self isConnected]) {
        [self.gleapWidget sendConfigUpdate];
    }
}

- (void)closeWidget:(void (^)())completion {
    [self.messageQueue removeAllObjects];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.gleapWidget == nil) {
            if (completion != nil) {
                completion();
            }
            return;
        }
        
        [self.gleapWidget dismissViewControllerAnimated: YES completion:^{
            self.gleapWidget = nil;
            if (completion != nil) {
                completion();
            }
            
            if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(widgetClosed)]) {
                [Gleap.sharedInstance.delegate widgetClosed];
            }
        }];
    });
}

- (void)connected {
    if (![self isConnected]) {
        return;
    }
    
    for (int i = 0; i < self.messageQueue.count; i++) {
        [self.gleapWidget sendMessageWithData: [self.messageQueue objectAtIndex: i]];
    }
    [self.messageQueue removeAllObjects];
}

- (void)failedToConnect {
    [self.messageQueue removeAllObjects];
}

- (void)showWidget {
    if (self.gleapWidget != nil) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Pre widget open hook.
        [GleapScreenshotManager takeScreenshot];
        [[GleapMetaDataHelper sharedInstance] updateLastScreenName];
        
        self.gleapWidget = [[GleapFrameManagerViewController alloc] init];
        self.gleapWidget.delegate = self;
        
        UINavigationController * navController = [[UINavigationController alloc] initWithRootViewController: self.gleapWidget];
        navController.navigationBar.barStyle = UIBarStyleBlack;
        [navController.navigationBar setTranslucent: NO];
        [navController.navigationBar setBarTintColor: [UIColor whiteColor]];
        [navController.navigationBar setTitleTextAttributes:
           @{NSForegroundColorAttributeName:[UIColor blackColor]}];
        navController.navigationBar.hidden = YES;
        navController.modalPresentationStyle = UIModalPresentationCustom;
        navController.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        
        // Show on top of all viewcontrollers.
        UIViewController *topMostViewController = [GleapUIHelper getTopMostViewController];
        [topMostViewController presentViewController: navController animated: YES completion:^{
            if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(widgetOpened)]) {
                [Gleap.sharedInstance.delegate widgetOpened];
            }
        }];
    });
}

@end
