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
#import "GleapUIOverlayHelper.h"
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
        self.widgetOpened = NO;
        self.messageQueue = [[NSMutableArray alloc] init];
    }
    return self;
}

- (BOOL)isOpened {
    return self.widgetOpened;
}

- (BOOL)isConnected {
    return self.widgetOpened && self.gleapWidget != nil && self.gleapWidget.connected;
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

- (void)closeWidgetWithAnimation:(Boolean)animated andCompletion:(void (^)(void))completion {
    [self.messageQueue removeAllObjects];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.gleapWidget == nil) {
            if (completion != nil) {
                completion();
            }
            return;
        }
        
        [self.gleapWidget dismissViewControllerAnimated: animated completion:^{
            self.widgetOpened = NO;
            self.gleapWidget = nil;
            self.widgetOpened = NO;
            if (completion != nil) {
                completion();
            }
            
            [GleapUIOverlayHelper updateUI];
            
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
    [self showWidgetFor: @"widget"];
}

- (void)showWidgetFor:(NSString *)type {
    if (self.widgetOpened) {
        return;
    }
    self.widgetOpened = YES;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Pre widget open hook with error handling.
        [GleapScreenshotManager takeScreenshotWithCompletion:^(UIImage *screenshot, NSError *error) {
            if (error) {
                NSLog(@"Gleap: Screenshot failed before opening widget: %@", error.localizedDescription);
                // Continue opening widget even if screenshot fails
            }
        }];
        [[GleapMetaDataHelper sharedInstance] updateLastScreenName];
        
        self.gleapWidget = [[GleapFrameManagerViewController alloc] initWithFormat: type];
        self.gleapWidget.delegate = self;
    
        // Clear all notifications.
        [GleapUIOverlayHelper clear];
        [GleapUIOverlayHelper updateUI];
        
        UINavigationController * navController = [[UINavigationController alloc] initWithRootViewController: self.gleapWidget];
        navController.navigationBar.barStyle = UIBarStyleBlack;
        [navController.navigationBar setTranslucent: NO];
        navController.modalPresentationStyle = UIModalPresentationFormSheet;
        [navController.navigationBar setBarTintColor: [UIColor whiteColor]];
        [navController.navigationBar setTitleTextAttributes:
           @{NSForegroundColorAttributeName:[UIColor blackColor]}];
        navController.navigationBar.hidden = YES;
        if (@available(iOS 13.0, *)) {
            [navController setModalInPresentation: YES];
        }
        
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
        {
            [navController setModalPresentationStyle: UIModalPresentationCustom];
        }
        
        // Bottom card survey.
        if ([type isEqualToString: @"survey"]) {
            [navController setModalPresentationStyle: UIModalPresentationCustom];
            [navController setModalTransitionStyle: UIModalTransitionStyleCrossDissolve];
            self.gleapWidget.view.backgroundColor = [UIColor clearColor];
        }
        
        // Show on top of all viewcontrollers.
        UIViewController *topMostViewController = [GleapUIHelper getTopMostViewController];
        if (topMostViewController != nil) {
            [topMostViewController presentViewController: navController animated: ![type isEqualToString: @"survey"] completion:^{
                if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(widgetOpened)]) {
                    [Gleap.sharedInstance.delegate widgetOpened];
                }
            }];
        }
    });
}

@end
