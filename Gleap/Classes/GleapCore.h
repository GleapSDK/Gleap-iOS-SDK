//
//  Gleap.h
//  AyAyObjectiveCPort
//
//  Created by Lukas on 13.01.19.
//  Copyright © 2019 Gleap. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "GleapUserSession.h"

NS_ASSUME_NONNULL_BEGIN

typedef enum activationMethodTypes { NONE, SHAKE, THREE_FINGER_DOUBLE_TAB, SCREENSHOT } GleapActivationMethod;
typedef enum bugPriorityTypes { LOW, MEDIUM, HIGH } GleapBugPriority;
typedef enum applicationType { NATIVE, REACTNATIVE, FLUTTER } GleapApplicationType;

@protocol GleapDelegate <NSObject>
@optional
- (void) bugWillBeSent;
- (void) bugSent;
- (void) bugSendingFailed;
- (void) customActionCalled: (NSString *)customAction;
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
 * Auto-configures the Gleap SDK from the remote config.
 * @author Gleap
 *
 * @param token The SDK key, which can be found on dashboard.bugbattle.io
 * @param userSession The GleapSession for the current user.
 */
+ (void)initializeWithToken: (NSString *)token andUserSession: (nullable GleapUserSession *)userSession;

/**
 * Manually start the bug reporting workflow. This is used, when you use the activation method "NONE".
 * @author Gleap
 *
 */
+ (void)startFeedbackFlow;

/**
 * Manually start a silent bug reporting workflow.
 * @author Gleap
 *
 */
+ (void)sendSilentBugReportWith:(NSString *)email andDescription:(NSString *)description andPriority:(GleapBugPriority)priority;

/**
 * Updates a session's user data.
 * @author Gleap
 *
 * @param data The updated user data.
 */
+ (void)updateUserSessionWithData:(nullable GleapUserSession *)data;

/**
 * Clears a user session.
 * @author Gleap
 */
+ (void)clearUserSession;

/**
 * Enables replays
 * @author Gleap
 *
 */
+ (void)enableReplays: (BOOL)enable;

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
 * Sets a custom widget url.
 * @author Gleap
 *
 * @param widgetUrl The custom widget url.
 */
+ (void)setWidgetUrl: (NSString *)widgetUrl;

/**
 * Disables the console logging. This must be called BEFORE initializing the SDK.
 * @author Gleap
 *
 */
+ (void)disableConsoleLog;

/**
 * Set's the current userinterface language.
 * @author Gleap
 *
 * @param language The 2 digit ISO code language to set
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
+ (void)attachData: (NSDictionary *)data;
+ (NSBundle *)frameworkBundle;
+ (void)shakeInvocation;
+ (void)attachScreenshot: (UIImage *)screenshot;
+ (UIImage *)getAttachedScreenshot;
+ (void)afterBugReportCleanup;

- (void)sendReport: (void (^)(bool success))completion;
- (void)uploadStepImages: (NSArray *)steps andCompletion: (void (^)(bool success, NSArray *fileUrls))completion;
- (UIViewController *)getTopMostViewController;
- (NSString *)getTopMostViewControllerName;
- (NSString *)getJSStringForNSDate:(NSDate *)date;
- (UIImage *)captureScreen;

@property (nonatomic, retain) NSString* language;
@property (nonatomic, retain) NSString* token;
@property (nonatomic, retain) NSString* apiUrl;
@property (nonatomic, retain) NSString* widgetUrl;
@property (nonatomic, retain) NSArray *activationMethods;
@property (nonatomic, retain) NSString *logoUrl;
@property (nonatomic, retain) NSMutableDictionary* data;
@property (nonatomic, assign) bool replaysEnabled;
@property (nonatomic, assign) bool consoleLogDisabled;
@property (nonatomic, assign) GleapApplicationType applicationType;
@property (nonatomic, weak) id <GleapDelegate> delegate;
@property (retain, nonatomic) NSString *lastScreenName;
@property (nonatomic, assign) bool currentlyOpened;

@end

NS_ASSUME_NONNULL_END
