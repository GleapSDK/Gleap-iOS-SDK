//
//  Gleap.m
//  GleapCore
//
//  Created by Lukas on 13.01.19.
//  Copyright © 2021 Gleap. All rights reserved.
//

#import "GleapCore.h"
#import "GleapFrameManagerViewController.h"
#import "GleapReplayHelper.h"
#import "GleapHttpTrafficRecorder.h"
#import "GleapSessionHelper.h"
#import "GleapUserProperty.h"
#import "GleapLogHelper.h"
#import "GleapConfigHelper.h"
#import "GleapMetaDataHelper.h"
#import "GleapScreenCaptureHelper.h"
#import "GleapConsoleLogHelper.h"
#import "GleapActivationMethodHelper.h"
#import "GleapScreenshotListener.h"
#import "GleapUIHelper.h"
#import "GleapCustomDataHelper.h"
#import "GleapAttachmentHelper.h"

@interface Gleap ()

@property (strong, nonatomic) UIImage *screenshot;
@property (retain, nonatomic) NSMutableDictionary *customActions;

@end

@implementation Gleap

/*
 Returns a shared instance (singleton).
 */
+ (instancetype)sharedInstance
{
    static Gleap *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[Gleap alloc] init];
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

/*
 Init helper.
 */
- (void)initHelper {
    self.token = @"";
    self.startFlow = @"";
    self.apiUrl = @"https://api.gleap.io";
    self.widgetUrl = @"https://widget.gleap.io";
    self.replayInterval = 5;
    self.initialized = NO;
    self.applicationType = NATIVE;
    self.screenshot = nil;
    self.language = [[NSLocale preferredLanguages] firstObject];
    
    [[GleapMetaDataHelper sharedInstance] startSession];
}

+ (void)setActivationMethods: (NSArray *)activationMethods {
    [[GleapActivationMethodHelper sharedInstance] setActivationMethods: activationMethods];
}

+ (void)setAutoActivationMethodsDisabled {
    [[GleapActivationMethodHelper sharedInstance] setAutoActivationMethodsDisabled];
}

+ (void)afterBugReportCleanup {
    if ([Gleap sharedInstance].replaysEnabled) {
        [[GleapReplayHelper sharedInstance] startWithInterval: [Gleap sharedInstance].replayInterval];
    }
    
    Gleap.sharedInstance.currentlyOpened = NO;
    Gleap.sharedInstance.startFlow = @"";
    Gleap.sharedInstance.action = nil;
}

+ (void)setLanguage: (NSString *)language {
    [Gleap sharedInstance].language = language;
}

+ (void)disableConsoleLog {
    GleapConsoleLogHelper.sharedInstance.consoleLogDisabled = YES;
}

+ (void)enableDebugConsoleLog {
    GleapConsoleLogHelper.sharedInstance.debugConsoleLogDisabled = NO;
}

+ (void)enableReplays: (BOOL)enable {
    [Gleap sharedInstance].replaysEnabled = enable;
    
    if ([Gleap sharedInstance].replaysEnabled) {
        // Starts the replay helper.
        [[GleapReplayHelper sharedInstance] startWithInterval: [Gleap sharedInstance].replayInterval];
    } else {
        [[GleapReplayHelper sharedInstance] stop];
    }
}

+ (void)startNetworkRecording {
    [[GleapHttpTrafficRecorder sharedRecorder] startRecording];
}

+ (void)startNetworkRecordingForSessionConfiguration:(NSURLSessionConfiguration *)configuration {
    [[GleapHttpTrafficRecorder sharedRecorder] startRecordingForSessionConfiguration: configuration];
}

+ (void)stopNetworkRecording {
    [[GleapHttpTrafficRecorder sharedRecorder] stopRecording];
}

+ (void)logEvent: (NSString *)name {
    [[GleapLogHelper sharedInstance] logEvent: name];
}

+ (void)logEvent: (NSString *)name withData: (NSDictionary *)data {
    [[GleapLogHelper sharedInstance] logEvent: name withData: data];
}

- (BOOL)isActivationMethodActive: (GleapActivationMethod)activationMethod {
    [[GleapActivationMethodHelper sharedInstance] isActivationMethodActive: activationMethod];
}

- (void)setSDKToken:(NSString *)token {
    self.token = token;
    
    [[GleapConsoleLogHelper sharedInstance] start];
}

/**
 Sets the API token.
 */
+ (void)setApiToken: (NSString *)token {
    Gleap* instance = [Gleap sharedInstance];
    [instance setSDKToken: token];
}

/*
 Autoconfigure with token
 */
+ (void)initializeWithToken: (NSString *)token {
    if ([Gleap sharedInstance].initialized) {
        NSLog(@"[GLEAP_SDK] Gleap has already been initialized.");
    }
    
    [Gleap sharedInstance].initialized = YES;
    [Gleap setApiToken: token];
    
    [[GleapScreenshotListener sharedInstance] start];
    [[GleapSessionHelper sharedInstance] startSessionWith:^(bool success) {
        [Gleap logEvent: @"sessionStarted"];
        [[GleapLogHelper sharedInstance] start];
        [[GleapConfigHelper sharedInstance] run];
    }];
}

/**
 * Updates a session's user data.
 * @author Gleap
 *
 * @param data The updated user data.
 */
+ (void)identifyUserWith:(NSString *)userId andData:(nullable GleapUserProperty *)data {
    [GleapSessionHelper.sharedInstance identifySessionWith: userId andData: data];
}

/**
 * Clears a user session.
 * @author Gleap
 */
+ (void)clearIdentity {
    [GleapSessionHelper.sharedInstance clearSession];
}

+ (void)setApiUrl: (NSString *)apiUrl {
    Gleap.sharedInstance.apiUrl = apiUrl;
}

+ (void)setWidgetUrl: (NSString *)widgetUrl {
    Gleap.sharedInstance.widgetUrl = widgetUrl;
}

+ (void)open {
    [self startFeedbackFlow];
}

/*
 Starts the bug reporting flow, when a SDK key has been assigned.
 */
+ (void)startFeedbackFlow {
    UIImage * screenshot = [GleapScreenCaptureHelper captureScreen];
    [self startFeedbackFlowWithScreenshot: screenshot andUI: true];
}

+ (void)startFeedbackFlow:(NSString *)feedbackFlow; {
    Gleap.sharedInstance.startFlow = feedbackFlow;
    [self startFeedbackFlow];
}

/*
 Sends a silent bug report with type
 */
+ (void)sendSilentCrashReportWith:(NSString *)description andSeverity:(GleapBugSeverity)severity {
    NSMutableDictionary *dataToAppend = [[NSMutableDictionary alloc] init];
    
    NSString *bugReportPriority = @"LOW";
    if (severity == MEDIUM) {
        bugReportPriority = @"MEDIUM";
    }
    if (severity == HIGH) {
        bugReportPriority = @"HIGH";
    }
    
    [dataToAppend setValue: @{
        @"description": description
    } forKey: @"formData"];
    [dataToAppend setValue: @(YES) forKey: @"isSilent"];
    [dataToAppend setValue: bugReportPriority forKey: @"priority"];
    [dataToAppend setValue: @"CRASH" forKey: @"type"];
    
    // [Gleap attachData: dataToAppend];
    
    UIImage * screenshot = [GleapScreenCaptureHelper captureScreen];
    [self startFeedbackFlowWithScreenshot: screenshot andUI: false];
}

+ (void)startFeedbackFlowWithScreenshot:(UIImage *)screenshot andUI:(BOOL)ui {
    if (GleapSessionHelper.sharedInstance.currentSession == nil) {
        NSLog(@"[GLEAP_SDK] Gleap session not ready.");
        return;
    }
    
    if (Gleap.sharedInstance.currentlyOpened) {
        NSLog(@"[GLEAP_SDK] Gleap is already opened.");
        return;
    }
    
    if (Gleap.sharedInstance.token.length == 0) {
        NSLog(@"[GLEAP_SDK] Please provide a valid Gleap project TOKEN!");
        return;
    }
    
    Gleap.sharedInstance.currentlyOpened = YES;
    
    if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(feedbackWillBeSent)]) {
        [Gleap.sharedInstance.delegate feedbackWillBeSent];
    }
    
    // Update last screen name
    [GleapMetaDataHelper.sharedInstance updateLastScreenName];
    
    // Stop replays
    [[GleapReplayHelper sharedInstance] stop];
    [Gleap attachScreenshot: screenshot];
    
    if (ui) {
        GleapFrameManagerViewController *gleapWidget = [[GleapFrameManagerViewController alloc] init];
        [gleapWidget setScreenshot: screenshot];
        
        UINavigationController * navController = [[UINavigationController alloc] initWithRootViewController: gleapWidget];
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
            
        }];
    } else {
        // No UI flow
        /*[Gleap.sharedInstance sendReport:^(bool success) {
            if (success) {
                if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(feedbackSent:)]) {
                    [Gleap.sharedInstance.delegate feedbackSent: [Gleap.sharedInstance getFormData]];
                }
            } else {
                if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(feedbackSendingFailed)]) {
                    [Gleap.sharedInstance.delegate feedbackSendingFailed];
                }
            }
            [Gleap afterBugReportCleanup];
        }];*/
    }
}

/*
 Invoked when a shake gesture is beeing performed.
 */
+ (void)shakeInvocation {
    if ([[GleapActivationMethodHelper sharedInstance] isActivationMethodActive: SHAKE]) {
        [Gleap startFeedbackFlow];
    }
}

/*
 Attaches custom data, which can be viewed in the Gleap dashboard. New data will be merged with existing custom data.
 */
+ (void)attachCustomData: (NSDictionary *)customData {
    [GleapCustomDataHelper attachCustomData: customData];
}

/*
 Clears all custom data.
 */
+ (void)clearCustomData {
    [GleapCustomDataHelper clearCustomData];
}

/**
 * Attach one key value pair to existing custom data.
 */
+ (void)setCustomData: (NSString *)value forKey: (NSString *)key {
    [GleapCustomDataHelper setCustomData: value forKey: key];
}

/**
 * Removes one key from existing custom data.
 */
+ (void)removeCustomDataForKey: (NSString *)key {
    [GleapCustomDataHelper removeCustomDataForKey: key];
}

/**
 * Attaches a file to the bug report
 */
+ (bool)addAttachmentWithPath: (NSString *)filePath {
    return [GleapAttachmentHelper addAttachmentWithPath: filePath];
}

+ (bool)addAttachmentWithData:(NSData *)data andName:(NSString *)name {
    return [GleapAttachmentHelper addAttachmentWithData: data andName: name];
}

/**
 * Removes all attachments
 */
+ (void)removeAllAttachments {
    [GleapAttachmentHelper removeAllAttachments];
}

/*
 Attaches a screenshot.
 */
+ (void)attachScreenshot: (UIImage *)screenshot {
    [Gleap sharedInstance].screenshot = screenshot;
}

/*
 Returns the attacked screenshot.
 */
+ (UIImage *)getAttachedScreenshot {
    return [Gleap sharedInstance].screenshot;
}

/**
 Sets the application type.
 */
+ (void)setApplicationType: (GleapApplicationType)applicationType {
    Gleap.sharedInstance.applicationType = applicationType;
}

- (void)performAction:(GleapAction *)action {
    if (self.action != nil) {
        NSLog(@"[GLEAP_SDK] Already performing action.");
        return;
    }
    
    self.action = action;
    [Gleap startFeedbackFlow: action.actionType];
}

@end
