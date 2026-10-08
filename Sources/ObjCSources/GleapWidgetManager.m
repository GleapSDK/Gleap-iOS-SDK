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
#import "GleapInternal.h"

// A transition that UIKit never reports back on ends after this long at the latest, so the ones behind it run.
static NSTimeInterval const kGleapTransitionTimeout = 15.0;
// A survey is held back until its page has something to show, at most this long (as in the JavaScript SDK).
static NSTimeInterval const kGleapSurveyRevealFallback = 1.2;

typedef NS_ENUM(NSInteger, GleapWidgetTransitionKind) {
    GleapWidgetTransitionOpen,
    // Shows a survey held back by its open.
    GleapWidgetTransitionReveal,
    GleapWidgetTransitionMinimize,
    GleapWidgetTransitionRestore,
    GleapWidgetTransitionClose,
};

/// One change of the widget on screen: open, minimize (for a capture), restore, close. They run one after the
/// other, each once UIKit has finished the one before: UIKit refuses a presentation or dismissal while another one
/// runs, without calling its completion, which used to leave the widget off screen but "open" (or on screen but
/// "closed").
GLEAP_INTERNAL
@interface GleapWidgetTransition : NSObject
@property (nonatomic, assign) GleapWidgetTransitionKind kind;
@property (nonatomic, copy, nullable) NSString *format;
@property (nonatomic, assign) BOOL animated;
@property (nonatomic, copy, nullable) void (^minimizeCompletion)(BOOL minimized, UIWindowScene * _Nullable scene);
@property (nonatomic, copy, nullable) void (^restoreCompletion)(BOOL restored);
@property (nonatomic, copy, nullable) void (^closeCompletion)(void);
@property (nonatomic, assign) BOOL ended;
@end

@implementation GleapWidgetTransition

- (void)finishMinimized:(BOOL)minimized scene:(UIWindowScene *)scene {
    void (^completion)(BOOL, UIWindowScene *) = self.minimizeCompletion;
    self.minimizeCompletion = nil;
    @try {
        if (completion != nil) {
            completion(minimized, minimized ? scene : nil);
        }
    } @catch (NSException *exception) {
        NSLog(@"[GLEAP_SDK] Minimizing the widget failed: %@", exception.reason);
    }
}

- (void)finishRestored:(BOOL)restored {
    void (^completion)(BOOL) = self.restoreCompletion;
    self.restoreCompletion = nil;
    @try {
        if (completion != nil) {
            completion(restored);
        }
    } @catch (NSException *exception) {
        NSLog(@"[GLEAP_SDK] Restoring the widget failed: %@", exception.reason);
    }
}

- (void)finishClosed {
    void (^completion)(void) = self.closeCompletion;
    self.closeCompletion = nil;
    @try {
        if (completion != nil) {
            completion();
        }
    } @catch (NSException *exception) {
        NSLog(@"[GLEAP_SDK] Closing the widget failed: %@", exception.reason);
    }
}

// Whoever waits for a transition that ended without doing its work hears about it.
- (void)finishUnsuccessfully {
    switch (self.kind) {
        case GleapWidgetTransitionMinimize:
            [self finishMinimized: NO scene: nil];
            break;
        case GleapWidgetTransitionRestore:
            [self finishRestored: NO];
            break;
        case GleapWidgetTransitionClose:
            [self finishClosed];
            break;
        case GleapWidgetTransitionOpen:
        case GleapWidgetTransitionReveal:
            break;
    }
}

@end

@interface GleapWidgetManager ()
@property (nonatomic, assign, readwrite) BOOL widgetMinimized;
// The presented controller (the navigation controller around the widget) while it is minimized.
@property (nonatomic, strong, nullable) UIViewController *minimizedController;
@property (nonatomic, weak, nullable) UIWindowScene *minimizedScene;
// Main queue.
@property (nonatomic, strong) NSMutableArray<GleapWidgetTransition *> *pendingTransitions;
@property (nonatomic, strong, nullable) GleapWidgetTransition *currentTransition;
// An open survey not presented yet: shown once its page has something to show (or after
// kGleapSurveyRevealFallback), so one that closes before (nothing to ask) is never seen.
@property (nonatomic, strong, nullable) UINavigationController *heldController;
// The widget was presented (and the app heard widgetOpened): only then does it hear widgetClosed.
@property (nonatomic, assign) BOOL widgetShown;
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
        self.pendingTransitions = [[NSMutableArray alloc] init];
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

#pragma mark - Open / close

- (void)showWidget {
    [self showWidgetFor: @"widget"];
}

- (void)showWidgetFor:(NSString *)type {
    if (self.widgetOpened) {
        return;
    }
    self.widgetOpened = YES;

    GleapWidgetTransition *transition = [[GleapWidgetTransition alloc] init];
    transition.kind = GleapWidgetTransitionOpen;
    transition.format = type;
    [self enqueueTransition: transition];
}

- (void)closeWidgetWithAnimation:(Boolean)animated andCompletion:(void (^)(void))completion {
    @synchronized (self) {
        [self.messageQueue removeAllObjects];
    }
    [[GleapAgentToolHelper sharedInstance] clearExecutionState];
    // A capture in progress ends with the widget, and its request goes back to the server.
    [[GleapCaptureManager sharedInstance] widgetWillClose];

    GleapWidgetTransition *transition = [[GleapWidgetTransition alloc] init];
    transition.kind = GleapWidgetTransitionClose;
    transition.animated = animated;
    transition.closeCompletion = completion;
    [self enqueueTransition: transition];
}

- (void)didCloseWidgetWithCompletion:(void (^)(void))completion {
    BOOL shown = self.widgetShown;
    self.widgetShown = NO;
    self.widgetOpened = NO;
    self.gleapWidget = nil;
    self.heldController = nil;
    if (completion != nil) {
        completion();
    }

    [GleapUIOverlayHelper updateUI];

    if (shown && Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(widgetClosed)]) {
        [Gleap.sharedInstance.delegate widgetClosed];
    }
}

#pragma mark - Minimize for captures

- (void)minimizeWidgetWithCompletion:(void (^)(BOOL minimized, UIWindowScene * _Nullable scene))completion {
    GleapWidgetTransition *transition = [[GleapWidgetTransition alloc] init];
    transition.kind = GleapWidgetTransitionMinimize;
    transition.minimizeCompletion = completion;
    [self enqueueTransition: transition];
}

- (void)restoreWidgetWithCompletion:(void (^)(BOOL restored))completion {
    GleapWidgetTransition *transition = [[GleapWidgetTransition alloc] init];
    transition.kind = GleapWidgetTransitionRestore;
    transition.restoreCompletion = completion;
    [self enqueueTransition: transition];
}

- (void)restoreWidgetIfNoCaptureRuns {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            if (self.widgetMinimized && ![[GleapCaptureManager sharedInstance] hasActiveCapture]) {
                [self restoreWidgetWithCompletion: nil];
            }
        } @catch (NSException *exception) {}
    });
}

- (void)forgetMinimizedWidget {
    self.widgetMinimized = NO;
    self.minimizedController = nil;
    self.minimizedScene = nil;
}

// A minimized widget that cannot come back (nothing to show it on, or nothing left of it) closes for good.
- (void)closeMinimizedWidgetForGood {
    [self forgetMinimizedWidget];
    @synchronized (self) {
        [self.messageQueue removeAllObjects];
    }
    [[GleapAgentToolHelper sharedInstance] clearExecutionState];
    if (self.widgetOpened || self.gleapWidget != nil) {
        [self didCloseWidgetWithCompletion: nil];
    }
}

#pragma mark - Transitions (main queue)

- (void)enqueueTransition:(GleapWidgetTransition *)transition {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            [self dropTransitionsMadePointlessBy: transition];
            [self.pendingTransitions addObject: transition];
            [self runNextTransition];
        } @catch (NSException *exception) {
            NSLog(@"[GLEAP_SDK] A widget transition failed: %@", exception.reason);
            [transition finishUnsuccessfully];
        }
    });
}

// Waiting transitions that the new one undoes are dropped: a close makes a minimize or restore pointless, a
// minimize a restore, and a restore a minimize (the capture it was for has ended).
- (void)dropTransitionsMadePointlessBy:(GleapWidgetTransition *)transition {
    NSMutableArray<GleapWidgetTransition *> *dropped = [NSMutableArray array];
    for (GleapWidgetTransition *pending in self.pendingTransitions) {
        BOOL pointless = NO;
        switch (transition.kind) {
            case GleapWidgetTransitionClose:
                pointless = pending.kind == GleapWidgetTransitionMinimize || pending.kind == GleapWidgetTransitionRestore;
                break;
            case GleapWidgetTransitionMinimize:
                pointless = pending.kind == GleapWidgetTransitionRestore;
                break;
            case GleapWidgetTransitionRestore:
                pointless = pending.kind == GleapWidgetTransitionMinimize;
                break;
            case GleapWidgetTransitionOpen:
            case GleapWidgetTransitionReveal:
                break;
        }
        if (pointless) {
            [dropped addObject: pending];
        }
    }
    [self.pendingTransitions removeObjectsInArray: dropped];
    for (GleapWidgetTransition *pending in dropped) {
        pending.ended = YES;
        [pending finishUnsuccessfully];
    }
}

- (void)runNextTransition {
    if (self.currentTransition != nil || self.pendingTransitions.count == 0) {
        return;
    }
    GleapWidgetTransition *transition = self.pendingTransitions.firstObject;
    [self.pendingTransitions removeObjectAtIndex: 0];
    self.currentTransition = transition;

    __weak typeof(self) weakSelf = self;
    dispatch_block_t end = ^{
        if (transition.ended) {
            return;
        }
        transition.ended = YES;
        if (weakSelf.currentTransition == transition) {
            weakSelf.currentTransition = nil;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf runNextTransition];
        });
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kGleapTransitionTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!transition.ended) {
            NSLog(@"[GLEAP_SDK] A widget transition did not finish in time.");
            [transition finishUnsuccessfully];
            end();
        }
    });

    @try {
        switch (transition.kind) {
            case GleapWidgetTransitionOpen:
                [self runOpenTransition: transition end: end];
                break;
            case GleapWidgetTransitionReveal:
                [self runRevealTransition: transition end: end];
                break;
            case GleapWidgetTransitionMinimize:
                [self runMinimizeTransition: transition end: end];
                break;
            case GleapWidgetTransitionRestore:
                [self runRestoreTransition: transition attempt: 0 end: end];
                break;
            case GleapWidgetTransitionClose:
                [self runCloseTransition: transition waits: 0 retried: NO end: end];
                break;
        }
    } @catch (NSException *exception) {
        NSLog(@"[GLEAP_SDK] A widget transition failed: %@", exception.reason);
        [transition finishUnsuccessfully];
        end();
    }
}

// UIKit skips the completion of a presentation or dismissal it refuses. `check` runs once `controller` had time
// for its transition (more while it is still animating); the completion handlers make it run only once.
- (void)afterTransitionOf:(UIViewController *)controller attempt:(NSUInteger)attempt run:(dispatch_block_t)check {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            if ((controller.isBeingPresented || controller.isBeingDismissed) && attempt < 2) {
                [self afterTransitionOf: controller attempt: attempt + 1 run: check];
                return;
            }
            check();
        } @catch (NSException *exception) {}
    });
}

// The controller itself or one it presents is still on its way in or out.
- (BOOL)isMidTransition:(UIViewController *)controller {
    for (UIViewController *current = controller; current != nil; current = current.presentedViewController) {
        if (current.isBeingPresented || current.isBeingDismissed) {
            return YES;
        }
    }
    return NO;
}

- (void)runOpenTransition:(GleapWidgetTransition *)transition end:(dispatch_block_t)end {
    if (!self.widgetOpened || self.gleapWidget != nil) {
        end();
        return;
    }
    NSString *type = transition.format ?: @"widget";

    // Pre widget open hook with error handling.
    [GleapScreenshotManager takeScreenshotWithCompletion:^(UIImage *screenshot, NSError *error) {
        if (error) {
            NSLog(@"Gleap: Screenshot failed before opening widget: %@", error.localizedDescription);
            // Continue opening widget even if screenshot fails
        }
    }];
    [[GleapMetaDataHelper sharedInstance] updateLastScreenName];

    GleapFrameManagerViewController *widget = [[GleapFrameManagerViewController alloc] initWithFormat: type];
    self.gleapWidget = widget;
    self.gleapWidget.delegate = self;

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

    if (widget.isSurvey) {
        // Its page loads and gets the survey off screen; nothing (no dim, no loading view, no sheet)
        // shows until the survey has something to show.
        self.heldController = navController;
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kGleapSurveyRevealFallback * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf revealSurvey: widget];
        });
        end();
        return;
    }

    [self presentWidget: widget in: navController end: end];
}

- (void)surveyContentShown {
    [self revealSurvey: self.gleapWidget];
}

- (void)revealSurvey:(GleapFrameManagerViewController *)widget {
    if (widget == nil || self.gleapWidget != widget || self.heldController == nil) {
        return;
    }
    GleapWidgetTransition *transition = [[GleapWidgetTransition alloc] init];
    transition.kind = GleapWidgetTransitionReveal;
    [self enqueueTransition: transition];
}

- (void)runRevealTransition:(GleapWidgetTransition *)transition end:(dispatch_block_t)end {
    UINavigationController *navController = self.heldController;
    self.heldController = nil;
    GleapFrameManagerViewController *widget = self.gleapWidget;
    if (navController == nil || !self.widgetOpened || widget == nil || navController.viewControllers.firstObject != widget) {
        end();
        return;
    }
    // Animated now also for a card: it fades in (and its page slides the card up).
    [self presentWidget: widget in: navController end: end];
}

- (void)presentWidget:(GleapFrameManagerViewController *)widget in:(UINavigationController *)navController end:(dispatch_block_t)end {
    // Clear all notifications.
    [GleapUIOverlayHelper clear];
    [GleapUIOverlayHelper updateUI];

    // Show on top of all viewcontrollers.
    UIViewController *topMostViewController = [GleapUIHelper getTopMostViewController];
    if (topMostViewController == nil) {
        // Nothing to present on (no key window yet): the widget stays closed, so a later open
        // can succeed, and the messages queued for this one are dropped as on close.
        NSLog(@"[GLEAP_SDK] The widget could not be opened: there is no view controller to present it on.");
        [self widgetDidNotOpen: widget];
        end();
        return;
    }

    __block BOOL finished = NO;
    dispatch_block_t landed = ^{
        if (finished) {
            return;
        }
        finished = YES;
        if (navController.presentingViewController == nil) {
            // UIKit did not present it (another presentation was running): closed, so a later open can succeed.
            NSLog(@"[GLEAP_SDK] The widget could not be opened: its presentation was refused.");
            [self widgetDidNotOpen: widget];
        } else if (self.gleapWidget == widget) {
            self.widgetShown = YES;
            if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(widgetOpened)]) {
                [Gleap.sharedInstance.delegate widgetOpened];
            }
        }
        end();
    };
    [topMostViewController presentViewController: navController animated: YES completion: landed];
    [self afterTransitionOf: navController attempt: 0 run: landed];
}

- (void)widgetDidNotOpen:(GleapFrameManagerViewController *)widget {
    if (self.gleapWidget != widget) {
        return;
    }
    self.gleapWidget = nil;
    self.widgetOpened = NO;
    self.heldController = nil;
    @synchronized (self) {
        [self.messageQueue removeAllObjects];
    }
    [GleapUIOverlayHelper updateUI];
}

- (void)runMinimizeTransition:(GleapWidgetTransition *)transition end:(dispatch_block_t)end {
    if (!self.widgetOpened || self.gleapWidget == nil) {
        [transition finishMinimized: NO scene: nil];
        end();
        return;
    }
    if (self.widgetMinimized) {
        [transition finishMinimized: YES scene: self.minimizedScene];
        end();
        return;
    }
    UIViewController *presented = self.gleapWidget.navigationController ?: self.gleapWidget;
    if (presented.presentingViewController == nil || [self isMidTransition: presented]) {
        [transition finishMinimized: NO scene: nil];
        end();
        return;
    }
    UIWindowScene *scene = presented.view.window.windowScene;
    // Kept here while off screen, so the web view and its page survive the dismissal.
    self.minimizedController = presented;
    self.minimizedScene = scene;
    self.widgetMinimized = YES;

    __block BOOL finished = NO;
    dispatch_block_t landed = ^{
        if (finished) {
            return;
        }
        finished = YES;
        if (presented.presentingViewController != nil && !presented.isBeingDismissed) {
            // UIKit did not dismiss it: still on screen, so nothing can be captured.
            if (self.minimizedController == presented) {
                [self forgetMinimizedWidget];
            }
            [transition finishMinimized: NO scene: nil];
        } else {
            [transition finishMinimized: YES scene: scene];
        }
        end();
    };
    [presented.presentingViewController dismissViewControllerAnimated: YES completion: landed];
    [self afterTransitionOf: presented attempt: 0 run: landed];
}

- (void)runRestoreTransition:(GleapWidgetTransition *)transition attempt:(NSUInteger)attempt end:(dispatch_block_t)end {
    if (!self.widgetMinimized) {
        [transition finishRestored: self.widgetOpened && self.gleapWidget != nil];
        end();
        return;
    }
    UIViewController *controller = self.minimizedController;
    if (controller == nil || self.gleapWidget == nil || !self.widgetOpened) {
        [self closeMinimizedWidgetForGood];
        [transition finishRestored: NO];
        end();
        return;
    }
    if (controller.presentingViewController != nil && !controller.isBeingDismissed) {
        // Still (or again) on screen.
        [self forgetMinimizedWidget];
        [transition finishRestored: YES];
        end();
        return;
    }

    UIViewController *top = [GleapUIHelper getTopMostViewController];
    if (top == nil || top == controller || controller.isBeingDismissed || [self isMidTransition: top]) {
        // Another presentation is on its way in or out: try again in a moment.
        [self retryRestoreTransition: transition attempt: attempt end: end];
        return;
    }

    __block BOOL finished = NO;
    dispatch_block_t landed = ^{
        if (finished) {
            return;
        }
        finished = YES;
        if (controller.presentingViewController != nil) {
            [self forgetMinimizedWidget];
            [transition finishRestored: YES];
            end();
            return;
        }
        [self retryRestoreTransition: transition attempt: attempt end: end];
    };
    @try {
        [top presentViewController: controller animated: YES completion: landed];
    } @catch (NSException *exception) {
        NSLog(@"[GLEAP_SDK] Showing the widget again failed: %@", exception.reason);
    }
    [self afterTransitionOf: controller attempt: 0 run: landed];
}

- (void)retryRestoreTransition:(GleapWidgetTransition *)transition attempt:(NSUInteger)attempt end:(dispatch_block_t)end {
    if (attempt < 2) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (transition.ended) {
                return;
            }
            @try {
                [self runRestoreTransition: transition attempt: attempt + 1 end: end];
            } @catch (NSException *exception) {
                [transition finishRestored: NO];
                end();
            }
        });
        return;
    }
    // Nothing to show it on: the widget closes for good.
    NSLog(@"[GLEAP_SDK] The widget could not be shown again after a capture.");
    [self closeMinimizedWidgetForGood];
    [transition finishRestored: NO];
    end();
}

- (void)runCloseTransition:(GleapWidgetTransition *)transition waits:(NSUInteger)waits retried:(BOOL)retried end:(dispatch_block_t)end {
    if (self.gleapWidget == nil) {
        [self forgetMinimizedWidget];
        [transition finishClosed];
        end();
        return;
    }
    
    UIViewController *presented = self.minimizedController ?: (self.gleapWidget.navigationController ?: self.gleapWidget);
    [self forgetMinimizedWidget];
    if (presented.presentingViewController == nil) {
        // Off screen (minimized for a capture): there is nothing to dismiss.
        [self didCloseWidgetWithCompletion:^{
            [transition finishClosed];
        }];
        end();
        return;
    }
    if ([self isMidTransition: presented] && waits < 8) {
        // Something is on its way in or out (the widget itself, an alert over it): UIKit would refuse the dismissal.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (transition.ended) {
                return;
            }
            @try {
                [self runCloseTransition: transition waits: waits + 1 retried: retried end: end];
            } @catch (NSException *exception) {
                [transition finishClosed];
                end();
            }
        });
        return;
    }
    
    __block BOOL finished = NO;
    dispatch_block_t landed = ^{
        if (finished) {
            return;
        }
        finished = YES;
        if (presented.presentingViewController != nil && !presented.isBeingDismissed) {
            if (!retried) {
                // UIKit refused the dismissal: once more.
                [self runCloseTransition: transition waits: 8 retried: YES end: end];
                return;
            }
            // Still on screen: it stays open (and can be closed again), rather than "closed" but visible.
            NSLog(@"[GLEAP_SDK] The widget could not be closed.");
            [transition finishClosed];
            end();
            return;
        }
        [self didCloseWidgetWithCompletion:^{
            [transition finishClosed];
        }];
        end();
    };
    // Through its presenter: whatever the widget shows on top of itself (an alert, a web page) goes with it.
    [presented.presentingViewController dismissViewControllerAnimated: transition.animated completion: landed];
    [self afterTransitionOf: presented attempt: 0 run: landed];
}

#pragma mark - Widget page

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

@end
