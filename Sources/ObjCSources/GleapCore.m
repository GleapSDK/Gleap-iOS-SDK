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
#import "GleapTranslationHelper.h"
#import "GleapWidgetManager.h"
#import "GleapFeedback.h"

@interface Gleap ()

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
    self.apiUrl = @"https://api.gleap.io";
    self.widgetUrl = @"https://widget.gleap.io";
    self.initialized = NO;
    self.applicationType = NATIVE;
    
    [[GleapMetaDataHelper sharedInstance] startSession];
}

+ (void)setActivationMethods: (NSArray *)activationMethods {
    [[GleapActivationMethodHelper sharedInstance] setActivationMethods: activationMethods];
}

+ (void)setAutoActivationMethodsDisabled {
    [GleapActivationMethodHelper setAutoActivationMethodsDisabled];
}

+ (void)setLanguage: (NSString *)language {
    [GleapTranslationHelper setLanguage: language];
}

+ (void)disableConsoleLog {
    GleapConsoleLogHelper.sharedInstance.consoleLogDisabled = YES;
}

+ (void)enableDebugConsoleLog {
    GleapConsoleLogHelper.sharedInstance.debugConsoleLogDisabled = NO;
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
    [GleapActivationMethodHelper isActivationMethodActive: activationMethod];
}

/**
 Sets the API token.
 */
+ (void)setApiToken: (NSString *)token {
    Gleap* instance = [Gleap sharedInstance];
    instance.token = token;
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
    
    [[GleapConsoleLogHelper sharedInstance] start];
    [[GleapScreenshotListener sharedInstance] start];
    [[GleapSessionHelper sharedInstance] startSessionWith:^(bool success) {
        [Gleap logEvent: @"sessionStarted"];
        [[GleapConfigHelper sharedInstance] run];
        
        // TODO: After config?
        [[GleapLogHelper sharedInstance] start];
    }];
}

/**
 * Updates a session's user data.
 * @author Gleap
 *
 * @param userId The user ID of the the user (can be an email as well)
 * @param data The updated user data.
 */
+ (void)identifyUserWith:(NSString *)userId andData:(nullable GleapUserProperty *)data {
    [GleapSessionHelper.sharedInstance identifySessionWith: userId andData: data andUserHash: nil];
}

/**
 * Updates a session's identity.
 * @author Gleap
 *
 * @param userId The user ID of the the user (can be an email as well)
 * @param data The updated user data.
 * @param userHash The calculated user hash to verify ownership.
 */
+ (void)identifyUserWith:(NSString *)userId andData:(nullable GleapUserProperty *)data andUserHash:(NSString *)userHash {
    [GleapSessionHelper.sharedInstance identifySessionWith: userId andData: data andUserHash: userHash];
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

+ (BOOL)isOpened {
    return [[GleapWidgetManager sharedInstance] isOpened];
}

+ (void)open {
    [[Gleap sharedInstance] startFeedbackFlow: nil withOptions: nil];
}

/**
    Starts the specified feedback flow.
 */
+ (void)startFeedbackFlow:(NSString * _Nullable)feedbackFlow showBackButton:(BOOL)showBackButton {
    [[Gleap sharedInstance] startFeedbackFlow: feedbackFlow withOptions: @{
        @"hideBackButton": @(!showBackButton)
    }];
}

/**
 Starts the bug reporting flow, when a SDK key has been assigned.
 */
- (void)startFeedbackFlow:(NSString * _Nullable)feedbackFlow withOptions:(NSDictionary * _Nullable)options {
    if (GleapSessionHelper.sharedInstance.currentSession == nil) {
        NSLog(@"[GLEAP_SDK] Gleap session not ready.");
        return;
    }
    
    if (Gleap.sharedInstance.token == nil || Gleap.sharedInstance.token.length == 0) {
        NSLog(@"[GLEAP_SDK] Please provide a valid Gleap project TOKEN!");
        return;
    }
    
    [[GleapWidgetManager sharedInstance] showWidget];
    
    // Start a feedback flow.
    if (feedbackFlow != nil) {
        NSMutableDictionary *startFeedbackFlowData = [[NSMutableDictionary alloc] initWithDictionary: @{
            @"flow": feedbackFlow
        }];
        if (options != nil) {
            [startFeedbackFlowData addEntriesFromDictionary: options];
        }
        
        [[GleapWidgetManager sharedInstance] sendMessageWithData: @{
            @"name": @"start-feedbackflow",
            @"data": startFeedbackFlowData,
        }];
    }
}

/*
 Sends a silent bug report with type
 */
+ (void)sendSilentCrashReportWith:(NSString *)description andSeverity:(GleapBugSeverity)severity andDataExclusion:(NSDictionary * _Nullable)excludeData andCompletion: (void (^)(bool success))completion {
    
    NSString *bugReportPriority = @"LOW";
    if (severity == MEDIUM) {
        bugReportPriority = @"MEDIUM";
    }
    if (severity == HIGH) {
        bugReportPriority = @"HIGH";
    }
    
    GleapFeedback *feedback = [[GleapFeedback alloc] init];
    [feedback appendData: @{
        @"formData": @{
            @"description": description
        },
        @"isSilent": @(YES),
        @"type": @"CRASH",
        @"priority": bugReportPriority,
    }];
    
    // Attach current screenshot.
    feedback.screenshot = [GleapScreenCaptureHelper captureScreen];
    
    // Attach exclude data.
    if (excludeData != nil) {
        feedback.excludeData = excludeData;
    } else {
        feedback.excludeData = @{
            @"screenshot": @(YES),
            @"replays": @(YES),
            @"attachments": @(YES)
        };
    }
    
    // Send crash report.
    [feedback send:^(bool success) {
        completion(success);
    }];
}

/*
 Invoked when a shake gesture is beeing performed.
 */
+ (void)shakeInvocation {
    if ([GleapActivationMethodHelper isActivationMethodActive: SHAKE]) {
        [Gleap open];
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

/**
 Sets the application type.
 */
+ (void)setApplicationType: (GleapApplicationType)applicationType {
    Gleap.sharedInstance.applicationType = applicationType;
}

- (void)performAction:(GleapAction *)action {
    [self startFeedbackFlow: action.actionType withOptions: @{
        @"actionOutboundId": action.outbound,
        @"hideBackButton": @YES
    }];
}

@end
