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
#import "GleapEventLogHelper.h"
#import "GleapConfigHelper.h"
#import "GleapMetaDataHelper.h"
#import "GleapScreenCaptureHelper.h"
#import "GleapConsoleLogHelper.h"
#import "GleapActivationMethodHelper.h"
#import "GleapScreenshotListener.h"
#import "GleapUIHelper.h"
#import "GleapNotificationHelper.h"
#import "GleapCustomDataHelper.h"
#import "GleapAttachmentHelper.h"
#import "GleapTranslationHelper.h"
#import "GleapWidgetManager.h"
#import "GleapFeedback.h"
#import "GleapExternalDataHelper.h"
#import "GleapPreFillHelper.h"
#import "GleapTagHelper.h"

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
    self.frameUrl = @"https://messenger.gleap.io/appnew";
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

+ (void)attachExternalData:(NSDictionary *)data {
    if (data != nil) {
        [[GleapExternalDataHelper sharedInstance].data addEntriesFromDictionary: data];
    }
}

+ (void)setDisableInAppNotifications:(Boolean)disableInAppNotifications {
    [GleapEventLogHelper sharedInstance].disableInAppNotifications = disableInAppNotifications;
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
    [[GleapEventLogHelper sharedInstance] logEvent: name];
}

+ (void)logEvent: (NSString *)name withData: (NSDictionary *)data {
    [[GleapEventLogHelper sharedInstance] logEvent: name withData: data];
}

+ (void)trackEvent: (NSString *)name {
    [[GleapEventLogHelper sharedInstance] logEvent: name];
}

+ (void)trackEvent: (NSString *)name withData: (NSDictionary *)data {
    [[GleapEventLogHelper sharedInstance] logEvent: name withData: data];
}

+ (BOOL)isActivationMethodActive: (GleapActivationMethod)activationMethod {
    return [GleapActivationMethodHelper isActivationMethodActive: activationMethod];
}

+ (NSArray *)getActivationMethods {
    return [GleapActivationMethodHelper getActivationMethods];
}

+ (void)preFillForm: (NSDictionary *)data {
    [[GleapPreFillHelper sharedInstance].preFillData addEntriesFromDictionary: data];
}

/*
 Autoconfigure with token
 */
+ (void)initializeWithToken: (NSString *)token {
    if ([Gleap sharedInstance].initialized) {
        NSLog(@"[GLEAP_SDK] Gleap has already been initialized.");
    }
    
    [Gleap sharedInstance].initialized = YES;
    [Gleap sharedInstance].token = token;
    
    [[GleapConsoleLogHelper sharedInstance] start];
    [[GleapScreenshotListener sharedInstance] start];
    [[GleapSessionHelper sharedInstance] startSessionWith:^(bool success) {
        [[GleapConfigHelper sharedInstance] run];
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

+ (NSDictionary *)getIdentity {
    return [GleapSessionHelper.sharedInstance.currentSession toDictionary];
}

+ (void)handlePushNotification:(NSDictionary *)notificationData {
    [GleapSessionHelper handlePushNotification: notificationData];
}

+ (BOOL)isUserIdentified {
    if (GleapSessionHelper.sharedInstance.currentSession != nil && GleapSessionHelper.sharedInstance.currentSession.userId != nil && GleapSessionHelper.sharedInstance.currentSession.userId.length > 0) {
        return YES;
    }
    return NO;
}

+ (void)setApiUrl: (NSString *)apiUrl {
    Gleap.sharedInstance.apiUrl = apiUrl;
}

+ (void)showFeedbackButton:(BOOL)show {
    [GleapNotificationHelper showFeedbackButton: show];
}

+ (void)setFrameUrl: (NSString *)frameUrl {
    Gleap.sharedInstance.frameUrl = frameUrl;
}

+ (BOOL)isOpened {
    return [[GleapWidgetManager sharedInstance] isOpened];
}

+ (Boolean)open {
    return [[Gleap sharedInstance] startFeedbackFlow: nil withOptions: nil];
}

+ (void)openNewsArticle:(NSString *)articleId {
    [self openNewsArticle: articleId andShowBackButton: YES];
}

+ (void)openNewsArticle:(NSString *)articleId andShowBackButton:(Boolean)showBackButton {
    if ([Gleap open]) {
        [[GleapWidgetManager sharedInstance] sendMessageWithData: @{
            @"name": @"open-news-article",
            @"data": @{
              @"id": articleId,
              @"hideBackButton": @(!showBackButton)
            }
        }];
    }
}

+ (void)startBot:(NSString * _Nullable)botId showBackButton:(BOOL)showBackButton {
    if ([Gleap open]) {
        [[GleapWidgetManager sharedInstance] sendMessageWithData: @{
            @"name": @"start-bot",
            @"data": @{
              @"botId": botId,
              @"hideBackButton": @(!showBackButton)
            }
        }];
    }
}

+ (void)openConversation:(NSString *)shareToken {
    if ([Gleap open]) {
        [[GleapWidgetManager sharedInstance] sendMessageWithData: @{
            @"name": @"open-conversation",
            @"data": @{
                @"shareToken": shareToken
            },
        }];
    }
}

+ (void)openNews {
    [self openNews: NO];
}

+ (void)openNews:(Boolean)showBackButton {
    if ([Gleap open]) {
        [[GleapWidgetManager sharedInstance] sendMessageWithData: @{
            @"name": @"open-news",
            @"data": @{
              @"hideBackButton": @(!showBackButton)
            }
        }];
    }
}

+ (void)openFeatureRequests {
    [self openFeatureRequests: NO];
}

+ (void)openFeatureRequests:(Boolean)showBackButton {
    if ([Gleap open]) {
        [[GleapWidgetManager sharedInstance] sendMessageWithData: @{
            @"name": @"open-feature-requests",
            @"data": @{
                @"hideBackButton": @(!showBackButton)
            }
        }];
    }
}

+ (void)openHelpCenterCollection:(NSString *)collectionId {
    [self openHelpCenterCollection: collectionId andShowBackButton: NO];
}

+ (void)openHelpCenterCollection:(NSString *)collectionId andShowBackButton:(Boolean)showBackButton {
    if ([Gleap open]) {
        [[GleapWidgetManager sharedInstance] sendMessageWithData: @{
            @"name": @"open-help-collection",
            @"data": @{
                @"collectionId": collectionId,
                @"hideBackButton": @(!showBackButton)
            }
        }];
    }
}

+ (void)openHelpCenterArticle:(NSString *)articleId {
    [self openHelpCenterArticle: articleId andShowBackButton: NO];
}

+ (void)openHelpCenterArticle:(NSString *)articleId andShowBackButton:(Boolean)showBackButton {
    if ([Gleap open]) {
        [[GleapWidgetManager sharedInstance] sendMessageWithData: @{
            @"name": @"open-help-article",
            @"data": @{
                @"articleId": articleId,
                @"hideBackButton": @(!showBackButton)
            }
        }];
    }
}

+ (void)openHelpCenter {
    [self openHelpCenter: NO];
}

+ (void)openHelpCenter:(Boolean)showBackButton {
    if ([Gleap open]) {
        [[GleapWidgetManager sharedInstance] sendMessageWithData: @{
            @"name": @"open-helpcenter",
            @"data": @{
                @"hideBackButton": @(!showBackButton)
            }
        }];
    }
}

+ (void)searchHelpCenter:(NSString *)searchTerm {
    [self searchHelpCenter: searchTerm andShowBackButton: NO];
}

+ (void)searchHelpCenter:(NSString *)searchTerm andShowBackButton:(Boolean)showBackButton {
    if ([Gleap open]) {
        [[GleapWidgetManager sharedInstance] sendMessageWithData: @{
            @"name": @"open-helpcenter-search",
            @"data": @{
                @"term": searchTerm,
                @"hideBackButton": @(!showBackButton)
            }
        }];
    }
}

+ (void)close {
    [[GleapWidgetManager sharedInstance] closeWidgetWithAnimation: YES andCompletion:^{}];
}

/**
    Starts the specified feedback flow.
 */
+ (Boolean)startFeedbackFlow:(NSString * _Nullable)feedbackFlow showBackButton:(BOOL)showBackButton {
    return [[Gleap sharedInstance] startFeedbackFlow: feedbackFlow withOptions: @{
        @"hideBackButton": @(!showBackButton)
    }];
}

/**
    Starts a survey.
 */
+ (void)showSurvey:(NSString * _Nullable)surveyId {
    [Gleap showSurvey: surveyId andFormat: SURVEY];
}

/**
    Starts a survey with format.
 */
+ (void)showSurvey:(NSString * _Nullable)surveyId andFormat:(GleapSurveyFormat)format {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [Gleap.sharedInstance startFeedbackFlow: surveyId withOptions: @{
            @"isSurvey": @YES,
            @"format": format == SURVEY_FULL ? @"survey_full" : @"survey",
            @"hideBackButton": @YES
        }];
    });
}

/**
 Starts the bug reporting flow, when a SDK key has been assigned.
 */
- (Boolean)startFeedbackFlow:(NSString * _Nullable)feedbackFlow withOptions:(NSDictionary * _Nullable)options {
    if (GleapSessionHelper.sharedInstance.currentSession == nil) {
        NSLog(@"[GLEAP_SDK] Gleap session not ready.");
        return NO;
    }
    
    if (Gleap.sharedInstance.token == nil || Gleap.sharedInstance.token.length == 0) {
        NSLog(@"[GLEAP_SDK] Please provide a valid Gleap project TOKEN!");
        return NO;
    }
    
    if ([[GleapWidgetManager sharedInstance] isOpened]) {
        return NO;
    }
    
    bool isSurvey = options != nil && [options objectForKey: @"isSurvey"] != nil && [[options objectForKey: @"isSurvey"] boolValue];

    if (isSurvey) {
        NSString *surveyFormat = [options objectForKey: @"format"];
        if (surveyFormat == nil) {
            surveyFormat = @"survey";
        }
        [[GleapWidgetManager sharedInstance] showWidgetFor: surveyFormat];
    } else {
        [[GleapWidgetManager sharedInstance] showWidget];
    }
    
    // Start a feedback flow.
    if (feedbackFlow != nil) {
        NSMutableDictionary *startFeedbackFlowData = [[NSMutableDictionary alloc] initWithDictionary: @{
            @"flow": feedbackFlow
        }];
        if (options != nil) {
            [startFeedbackFlowData addEntriesFromDictionary: options];
        }
        
        NSString *command = @"start-feedbackflow";
        if (isSurvey) {
            command = @"start-survey";
        }
        
        [[GleapWidgetManager sharedInstance] sendMessageWithData: @{
            @"name": command,
            @"data": startFeedbackFlowData,
        }];
    }
    
    return YES;
}

/*
 Sends a silent bug report with type
 */
+ (void)sendSilentCrashReportWith:(NSString *)description andSeverity:(GleapBugSeverity)severity andDataExclusion:(NSDictionary * _Nullable)excludeData andCompletion: (void (^)(bool success))completion {
    dispatch_async(dispatch_get_main_queue(), ^{
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
        [feedback send:^(bool success, NSDictionary* data) {
            completion(success);
        }];
    });
}

/*
 Invoked when a shake gesture is beeing performed.
 */
+ (void)shakeInvocation {
    if ([GleapActivationMethodHelper isActivationMethodActive: SHAKE]) {
        [Gleap open];
    }
}

/**
 Log message to the Gleap logs
 */
+ (void)log:(NSString *)msg {
    [[GleapConsoleLogHelper sharedInstance] log: msg andLogLevel: INFO];
}

/**
 Log message with log level to the Gleap logs
 */
+ (void)log:(NSString *)msg withLogLevel:(GleapLogLevel)logLevel {
    [[GleapConsoleLogHelper sharedInstance] log: msg andLogLevel: logLevel];
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

/*
 Sets tags that are used for new tickets created by the SDK.
 */
+ (void)setTags: (NSArray *)tags {
    [GleapTagHelper setTags: tags];
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

@end
