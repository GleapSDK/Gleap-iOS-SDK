//
//  Gleap.h
//  Gleap
//
//  Created by Lukas on 13.01.19.
//  Copyright © 2019 Gleap. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "GleapUserProperty.h"
#import "GleapAction.h"

NS_ASSUME_NONNULL_BEGIN

typedef enum activationMethodTypes { NONE, SHAKE, SCREENSHOT } GleapActivationMethod;
typedef enum bugSeverityTypes { LOW, MEDIUM, HIGH } GleapBugSeverity;
typedef enum gleapLogLevel { INFO, WARNING, ERROR } GleapLogLevel;
typedef enum applicationType { NATIVE, REACTNATIVE, FLUTTER, CORDOVA, CAPACITOR } GleapApplicationType;
typedef enum surveyFormat { SURVEY, SURVEY_FULL } GleapSurveyFormat;

@protocol GleapDelegate <NSObject>
@optional
- (void) feedbackFlowStarted: (NSDictionary *)feedbackAction;
- (void) feedbackSent: (NSDictionary *)data;
- (void) feedbackSendingFailed;
- (void) customActionCalled: (NSString *)customAction;
- (void) configLoaded: (NSDictionary *)config;
- (void) widgetOpened;
- (void) widgetClosed;
- (void) registerPushMessageGroup: (NSString *)pushMessageGroup;
- (void) unregisterPushMessageGroup: (NSString *)pushMessageGroup;
@required
@end

@interface Gleap : NSObject

/**
 * Returns a new shared instance of Gleap.
 * @author Gleap
 *
 * @return A new shared instance of Gleap.
 */
+ (instancetype)sharedInstance;

/**
 * Auto-configures the Gleap SDK from the remote config.
 * @author Gleap
 *
 * @param token The SDK key, which can be found on dashboard.bugbattle.io
 */
+ (void)initializeWithToken: (NSString *)token;

/**
 * Shows the survey with ID.
 * @author Gleap
 *
 * @param surveyId The ID of the survey
 */
+ (void)showSurvey:(NSString * _Nullable)surveyId;
+ (void)showSurvey:(NSString * _Nullable)surveyId andFormat:(GleapSurveyFormat)format;

/**
 * Show the Gleap widget.
 * @author Gleap
 *
 */
+ (Boolean)open;

/**
 * Show the news list.
 * @author Gleap
 *
 */
+ (void)openNews;
+ (void)openNews:(Boolean)showBackButton;

/**
 * Disable in-app notifications.
 * @author Gleap
 *
 */
+ (void)setDisableInAppNotifications:(Boolean)disableInAppNotifications;

/**
 * Open a conversation.
 * @author Gleap
 *
 */
+ (void)openConversation:(NSString *)shareToken;

/**
 * Show a news article.
 * @author Gleap
 *
 */
+ (void)openNewsArticle:(NSString *)articleId;
+ (void)openNewsArticle:(NSString *)articleId andShowBackButton:(Boolean)showBackButton;

/**
 * Show the feature requests.
 * @author Gleap
 *
 */
+ (void)openFeatureRequests;
+ (void)openFeatureRequests:(Boolean)showBackButton;

/**
 * Show the help center.
 * @author Gleap
 *
 */
+ (void)openHelpCenter;
+ (void)openHelpCenter:(Boolean)showBackButton;

/**
 * Show the help center collection.
 * @author Gleap
 *
 */
+ (void)openHelpCenterCollection:(NSString *)collectionId andShowBackButton:(Boolean)showBackButton;
+ (void)openHelpCenterCollection:(NSString *)collectionId;

/**
 * Show the help center article.
 * @author Gleap
 *
 */
+ (void)openHelpCenterArticle:(NSString *)articleId;
+ (void)openHelpCenterArticle:(NSString *)articleId andShowBackButton:(Boolean)showBackButton;

/**
 * Search the help center.
 * @author Gleap
 *
 */
+ (void)searchHelpCenter:(NSString *)searchTerm;
+ (void)searchHelpCenter:(NSString *)searchTerm andShowBackButton:(Boolean)showBackButton;

/**
 * Close the Gleap widget.
 * @author Gleap
 *
 */
+ (void)close;

/**
 * Start a feedback flow.
 * @author Gleap
 *
 */
+ (Boolean)startFeedbackFlow:(NSString * _Nullable)feedbackFlow showBackButton:(BOOL)showBackButton;

/**
 * Start the bot with the given id.
 * @author Gleap
 *
 */
+ (void)startBot:(NSString * _Nullable)botId showBackButton:(BOOL)showBackButton;

/**
 * Set the visibility of the feedback button.
 * @author Gleap
 *
 */
+ (void)showFeedbackButton:(BOOL)show;

/**
 * Sends a silent crash report.
 * @author Gleap
 *
 */
+ (void)sendSilentCrashReportWith:(NSString *)description andSeverity:(GleapBugSeverity)severity andDataExclusion:(NSDictionary * _Nullable)excludeData andCompletion: (void (^)(bool success))completion;

/**
 * Logs a message to the Gleap activity log
 * @author Gleap
 *
 * @param msg The logged message
 */
+ (void)log:(NSString *)msg;

/**
 * Handels a push notification tap.
 * @author Gleap
 *
 * @param notificationData The push notification data.
 */
+ (void)handlePushNotification:(NSDictionary *)notificationData;

/**
 * Logs a message with a given log level to the Gleap activity log
 * @author Gleap
 *
 * @param msg The logged message
 */
+ (void)log:(NSString *)msg withLogLevel:(GleapLogLevel)logLevel;

/**
 * Updates a session's identity.
 * @author Gleap
 *
 * @param userId The user ID of the the user (can be an email as well)
 * @param data The updated user data.
 */
+ (void)identifyUserWith:(NSString *)userId andData:(nullable GleapUserProperty *)data;

/**
 * Updates a session's identity.
 * @author Gleap
 *
 * @param userId The user ID of the the user (can be an email as well)
 * @param data The updated user data.
 * @param userHash The calculated user hash to verify ownership.
 */
+ (void)identifyUserWith:(NSString *)userId andData:(nullable GleapUserProperty *)data andUserHash:(NSString *)userHash;

/**
 * Clears a user session.
 * @author Gleap
 */
+ (void)clearIdentity;

/**
 * Returns the user's identity.
 * @author Gleap
 */
+ (NSDictionary *)getIdentity;

/**
 * Returns the user's identity state.
 * @author Gleap
 */
+ (BOOL)isUserIdentified;

/**
 * Prefills the widget form with data.
 * @author Gleap
 *
 * @param data The data you want to prefill the form with.
 */
+ (void)preFillForm: (NSDictionary *)data;

/**
 * Sets tags that are used for new tickets created by the SDK.
 * @author Gleap
 *
 * @param tags The tags array to set
 */
+ (void)setTags: (NSArray *)tags;

/**
 * Attaches custom data, which can be viewed in the Gleap dashboard. New data will be merged with existing custom data.
 * @author Gleap
 *
 * @param customData The data to attach to a bug report.
 */
+ (void)attachCustomData: (NSDictionary *)customData;

/**
 * Attach one key value pair to existing custom data.
 * @author Gleap
 *
 * @param value The value you want to add
 * @param key The key of the attribute
 */
+ (void)setCustomData: (NSString *)value forKey: (NSString *)key;

/**
 * Removes one key from existing custom data.
 * @author Gleap
 *
 * @param key The key of the attribute
 */
+ (void)removeCustomDataForKey: (NSString *)key;

/**
 * Clears all custom data.
 * @author Gleap
 */
+ (void)clearCustomData;

/**
 * Sets a custom api url.
 * @author Gleap
 *
 * @param apiUrl The custom api url.
 */
+ (void)setApiUrl: (NSString *)apiUrl;

/**
 * Sets a custom frame url.
 * @author Gleap
 *
 * @param frameUrl The custom frame url.
 */
+ (void)setFrameUrl: (NSString *)frameUrl;

/**
 * Disables the console logging. This must be called BEFORE initializing the SDK.
 * @author Gleap
 *
 */
+ (void)disableConsoleLog;

/**
 * Enables the debug console logging. This must be called BEFORE initializing the SDK.
 * @author Gleap
 *
 */
+ (void)enableDebugConsoleLog;

/**
 * Set's the current userinterface language.
 * @author Gleap
 *
 * @param language The 2 or 4 digit ISO code language to set
 */
+ (void)setLanguage: (NSString *)language;

/**
 * Logs a custom event
 * @author Gleap
 *
 * @param name Name of the event
 *
 */
+ (void)logEvent: (NSString *)name;

/**
 * Logs a custom event with data
 * @author Gleap
 *
 * @param name Name of the event
 * @param data Data passed with the event.
 *
 */
+ (void)logEvent: (NSString *)name withData: (NSDictionary *)data;

/**
 * Logs a custom event
 * @author Gleap
 *
 * @param name Name of the event
 *
 */
+ (void)trackEvent: (NSString *)name;

/**
 * Logs a custom event with data
 * @author Gleap
 *
 * @param name Name of the event
 * @param data Data passed with the event.
 *
 */
+ (void)trackEvent: (NSString *)name withData: (NSDictionary *)data;

/**
 * Attaches a file to the bug report
 * @author Gleap
 *
 * @param filePath The file to attach to the bug report
 */
+ (bool)addAttachmentWithPath: (NSString *)filePath;

/**
 * Attaches a file to the bug report
 * @author Gleap
 *
 * @param data The data to attach to the bug report
 * @param name The filename including the file extension
 */
+ (bool)addAttachmentWithData: (NSData *)data andName: (NSString *)name;

/**
 * Attaches external data to all feedback items.
 * @author Gleap
 *
 * @param data The external data to attach to the bug report
 */
+ (void)attachExternalData: (NSDictionary *)data;

/**
 * Removes all attachments
 * @author Gleap
 */
+ (void)removeAllAttachments;

/**
 * Returns the widget state
 * @author Gleap
 */
+ (BOOL)isOpened;

/**
 * Starts network recording.
 * @author Gleap
 *
 */
+ (void)startNetworkRecording;

/**
 * Starts network recording with a session configuration.
 * @author Gleap
 *
 * @param configuration the NSURLSessionConfiguration which should be logged
 *
 */
+ (void)startNetworkRecordingForSessionConfiguration:(NSURLSessionConfiguration *)configuration;

/**
 * Stops network recording.
 * @author Gleap
 *
 */
+ (void)stopNetworkRecording;

// Helper
+ (void)setApplicationType: (GleapApplicationType)applicationType;
+ (void)setActivationMethods: (NSArray *)activationMethods;
+ (NSArray *)getActivationMethods;
+ (BOOL)isActivationMethodActive: (GleapActivationMethod)activationMethod;
+ (void)shakeInvocation;
+ (void)setAutoActivationMethodsDisabled;
- (Boolean)startFeedbackFlow:(NSString * _Nullable)feedbackFlow withOptions:(NSDictionary * _Nullable)options;

@property (nonatomic, retain) NSString* token;
@property (nonatomic, retain) NSString* apiUrl;
@property (nonatomic, retain) NSString* frameUrl;
@property (nonatomic, assign) int initialized;
@property (nonatomic, assign) GleapApplicationType applicationType;
@property (nonatomic, weak) id <GleapDelegate> delegate;

@end

NS_ASSUME_NONNULL_END
