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
#import "GleapCaptureManager.h"

@interface GleapWidgetManager ()
@property (nonatomic, assign, readwrite) BOOL widgetMinimized;
// The presented controller (the navigation controller around the widget) while it is minimized.
@property (nonatomic, strong, nullable) UIViewController *minimizedController;
@property (nonatomic, weak, nullable) UIWindowScene *minimizedScene;
@end

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

- (BOOL)isWidgetVisible {
    return self.widgetOpened && !self.widgetMinimized;
}

- (void)sendMessageWithData:(NSDictionary *)data {
    if ([self isConnected]) {
        [self.gleapWidget sendMessageWithData: data];
    } else {
        // Commands can come from any thread (the wrappers call off the main thread).
        @synchronized (self) {
            [self.messageQueue addObject: data];
        }
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
    @synchronized (self) {
        [self.messageQueue removeAllObjects];
    }
    [[GleapAgentToolHelper sharedInstance] clearExecutionState];
    // A capture in progress ends with the widget, and its request goes back to the server.
    [[GleapCaptureManager sharedInstance] widgetWillClose];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.gleapWidget == nil) {
            if (completion != nil) {
                completion();
            }
            return;
        }
        
        if (self.widgetMinimized) {
            // Minimized for a capture: there is nothing on screen to dismiss.
            [self forgetMinimizedWidget];
            [self didCloseWidgetWithCompletion: completion];
            return;
        }
        
        [self.gleapWidget dismissViewControllerAnimated: animated completion:^{
            [self didCloseWidgetWithCompletion: completion];
        }];
    });
}

- (void)didCloseWidgetWithCompletion:(void (^)(void))completion {
    self.widgetOpened = NO;
    self.gleapWidget = nil;
    if (completion != nil) {
        completion();
    }
    
    [GleapUIOverlayHelper updateUI];
    
    if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(widgetClosed)]) {
        [Gleap.sharedInstance.delegate widgetClosed];
    }
}

#pragma mark - Minimize for captures

- (void)forgetMinimizedWidget {
    self.widgetMinimized = NO;
    self.minimizedController = nil;
    self.minimizedScene = nil;
}

- (void)minimizeWidgetWithCompletion:(void (^)(BOOL minimized, UIWindowScene * _Nullable scene))completion {
    dispatch_block_t work = ^{
        if (!self.widgetOpened || self.gleapWidget == nil) {
            completion(NO, nil);
            return;
        }
        if (self.widgetMinimized) {
            completion(YES, self.minimizedScene);
            return;
        }
        UIViewController *presented = self.gleapWidget.navigationController ?: self.gleapWidget;
        if (presented.presentingViewController == nil || presented.isBeingDismissed) {
            completion(NO, nil);
            return;
        }
        UIWindowScene *scene = presented.view.window.windowScene;
        // Kept here while off screen, so the web view and its page survive the dismissal.
        self.minimizedController = presented;
        self.minimizedScene = scene;
        self.widgetMinimized = YES;
        __block BOOL finished = NO;
        void (^finish)(void) = ^{
            if (finished) {
                return;
            }
            finished = YES;
            completion(YES, scene);
        };
        [presented dismissViewControllerAnimated: YES completion: finish];
        // UIKit skips the completion when the dismissal cannot run; the capture must not wait forever.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), finish);
    };
    if ([NSThread isMainThread]) {
        work();
    } else {
        dispatch_async(dispatch_get_main_queue(), work);
    }
}

- (void)restoreWidgetWithCompletion:(void (^)(BOOL restored))completion {
    dispatch_block_t work = ^{
        if (!self.widgetMinimized) {
            if (completion != nil) {
                completion(self.widgetOpened && self.gleapWidget != nil);
            }
            return;
        }
        [self presentMinimizedWidgetAttempt: 0 completion: completion];
    };
    if ([NSThread isMainThread]) {
        work();
    } else {
        dispatch_async(dispatch_get_main_queue(), work);
    }
}

- (void)presentMinimizedWidgetAttempt:(NSUInteger)attempt completion:(void (^)(BOOL restored))completion {
    UIViewController *controller = self.minimizedController;
    if (!self.widgetMinimized || controller == nil || self.gleapWidget == nil) {
        if (completion != nil) {
            completion(NO);
        }
        return;
    }
    if (controller.presentingViewController != nil) {
        // Already back on screen.
        [self forgetMinimizedWidget];
        if (completion != nil) {
            completion(YES);
        }
        return;
    }
    
    UIViewController *top = [GleapUIHelper getTopMostViewController];
    __block BOOL finished = NO;
    void (^retryOrGiveUp)(void) = ^{
        if (attempt < 2) {
            [self presentMinimizedWidgetAttempt: attempt + 1 completion: completion];
            return;
        }
        // Nothing to show it on: the widget closes for good.
        NSLog(@"[GLEAP_SDK] The widget could not be shown again after a capture.");
        [self forgetMinimizedWidget];
        @synchronized (self) {
            [self.messageQueue removeAllObjects];
        }
        [[GleapAgentToolHelper sharedInstance] clearExecutionState];
        [self didCloseWidgetWithCompletion: nil];
        if (completion != nil) {
            completion(NO);
        }
    };
    
    if (top == nil || top == controller || top.isBeingDismissed || top.isBeingPresented) {
        // Another presentation is on its way in or out: try again in a moment.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), retryOrGiveUp);
        return;
    }
    
    @try {
        [top presentViewController: controller animated: YES completion:^{
            if (finished) {
                return;
            }
            finished = YES;
            [self forgetMinimizedWidget];
            if (completion != nil) {
                completion(YES);
            }
        }];
    } @catch (NSException *exception) {
        NSLog(@"[GLEAP_SDK] Showing the widget again failed: %@", exception.reason);
    }
    
    // A presentation UIKit refused never calls its completion.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (finished) {
            return;
        }
        finished = YES;
        if (controller.presentingViewController != nil) {
            [self forgetMinimizedWidget];
            if (completion != nil) {
                completion(YES);
            }
            return;
        }
        retryOrGiveUp();
    });
}

- (void)connected {
    if (![self isConnected]) {
        return;
    }
    
    NSArray *queuedMessages;
    @synchronized (self) {
        queuedMessages = [self.messageQueue copy];
        [self.messageQueue removeAllObjects];
    }
    for (NSDictionary *message in queuedMessages) {
        [self.gleapWidget sendMessageWithData: message];
    }
}

- (void)failedToConnect {
    @synchronized (self) {
        [self.messageQueue removeAllObjects];
    }
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
        [navController setModalInPresentation: YES];
        
        if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad)
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
        } else {
            // Nothing to present on (no key window yet): the widget stays closed, so a later open
            // can succeed, and the messages queued for this one are dropped as on close.
            NSLog(@"[GLEAP_SDK] The widget could not be opened: there is no view controller to present it on.");
            self.gleapWidget = nil;
            self.widgetOpened = NO;
            @synchronized (self) {
                [self.messageQueue removeAllObjects];
            }
            [GleapUIOverlayHelper updateUI];
        }
    });
}

@end
