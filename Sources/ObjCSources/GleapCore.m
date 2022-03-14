//
//  Gleap.m
//  GleapCore
//
//  Created by Lukas on 13.01.19.
//  Copyright © 2021 Gleap. All rights reserved.
//

#define SDK_VERSION @"6.4.2"

#import "GleapCore.h"
#import "GleapWidgetViewController.h"
#import "GleapReplayHelper.h"
#import "GleapHttpTrafficRecorder.h"
#import "GleapSessionHelper.h"
#import "GleapUserProperty.h"
#import "GleapLogHelper.h"
#import <sys/utsname.h>

@interface Gleap ()

@property (strong, nonatomic) UIImage *screenshot;
@property (retain, nonatomic) NSDate *sessionStart;
@property (retain, nonatomic) NSMutableArray *consoleLog;
@property (retain, nonatomic) NSMutableArray *callstack;
@property (retain, nonatomic) NSMutableDictionary *customData;
@property (retain, nonatomic) NSMutableDictionary *customActions;
@property (retain, nonatomic) NSMutableArray *customAttachments;
@property (retain, nonatomic) NSPipe *inputPipe;
@property (retain, nonatomic) NSPipe *outputPipe;
@property (nonatomic, retain) UITapGestureRecognizer *tapGestureRecognizer;

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
    self.lastScreenName = @"";
    self.token = @"";
    self.logoUrl = @"";
    self.startFlow = @"";
    self.apiUrl = @"https://api.gleap.io";
    self.widgetUrl = @"https://widget.gleap.io";
    self.replayInterval = 5;
    self.initialized = NO;
    self.debugConsoleLogDisabled = YES;
    self.consoleLogDisabled = NO;
    self.activationMethods = [[NSArray alloc] init];
    self.applicationType = NATIVE;
    self.screenshot = nil;
    self.networkLogPropsToIgnore = [[NSArray alloc] init];
    self.data = [[NSMutableDictionary alloc] init];
    self.sessionStart = [[NSDate alloc] init];
    self.consoleLog = [[NSMutableArray alloc] init];
    self.callstack = [[NSMutableArray alloc] init];
    self.customAttachments = [[NSMutableArray alloc] init];
    self.customData = [[NSMutableDictionary alloc] init];
    self.language = [[NSLocale preferredLanguages] firstObject];
    self.excludeData = [[NSDictionary alloc] init];
    self.disableAutoActivationMethods = NO;
}

+ (void)setActivationMethods: (NSArray *)activationMethods {
    [Gleap sharedInstance].activationMethods = activationMethods;
}

+ (void)setAutoActivationMethodsDisabled {
    [Gleap sharedInstance].disableAutoActivationMethods = YES;
}

+ (void)afterBugReportCleanup {
    if ([Gleap sharedInstance].replaysEnabled) {
        [[GleapReplayHelper sharedInstance] startWithInterval: [Gleap sharedInstance].replayInterval];
    }
    
    Gleap.sharedInstance.data = [[NSMutableDictionary alloc] init];
    Gleap.sharedInstance.currentlyOpened = NO;
    Gleap.sharedInstance.startFlow = @"";
    Gleap.sharedInstance.action = nil;
}

+ (void)setLanguage: (NSString *)language {
    [Gleap sharedInstance].language = language;
}

+ (void)disableConsoleLog {
    [Gleap sharedInstance].consoleLogDisabled = YES;
}

+ (void)enableDebugConsoleLog {
    [Gleap sharedInstance].debugConsoleLogDisabled = NO;
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

- (NSString *)getTopMostViewControllerName {
    NSString *currentViewControllerName = @"NotSet";
    UIViewController *topViewController = [self getTopMostViewController];
    if (topViewController != nil) {
        if (topViewController.title != nil) {
            currentViewControllerName = topViewController.title;
        } else {
            currentViewControllerName = NSStringFromClass([topViewController class]);
        }
    }
    return currentViewControllerName;
}

/*
 Returns the top most view controller.
 */
- (UIViewController *)getTopMostViewController {
    UIWindow *keyWindow = [[UIApplication sharedApplication] keyWindow];
    return [self topViewControllerWith: keyWindow.rootViewController];
}

/*
 Returns the top most view controller.
 */
- (UIViewController *)topViewControllerWith:(UIViewController *)rootViewController {
    if (rootViewController == nil) {
        return nil;
    }
    
    UIViewController *presentedViewController = rootViewController.presentedViewController;
    if (presentedViewController == nil) {
        if ([rootViewController isKindOfClass: [UINavigationController class]]) {
            UINavigationController *navController = (UINavigationController *)rootViewController;
            return [self topViewControllerWith: navController.viewControllers.lastObject];
        }
        
        if ([rootViewController isKindOfClass: [UITabBarController class]]) {
            UITabBarController *tabBarController = (UITabBarController *)rootViewController;
            return [self topViewControllerWith: tabBarController.selectedViewController];
        }
        
        return rootViewController;
    }
    return [self topViewControllerWith: presentedViewController];
}

- (void)setSDKToken:(NSString *)token {
    self.token = token;
    
    if (self.consoleLogDisabled != YES) {
        [self openConsoleLog];
    }
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
    [[GleapSessionHelper sharedInstance] startSessionWith:^(bool success) {
        [Gleap logEvent: @"sessionStarted"];
        [[GleapLogHelper sharedInstance] start];
        [self autoConfigure];
    }];
    [[Gleap sharedInstance] initializeScreenshotRecognizer];
}

+ (void)autoConfigure {
    NSString *widgetConfigURL = [NSString stringWithFormat: @"%@/appwidget/%@/config?s=ios", Gleap.sharedInstance.widgetUrl, Gleap.sharedInstance.token];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    [request setHTTPMethod:@"GET"];
    [request setURL: [NSURL URLWithString: widgetConfigURL]];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:
      ^(NSData * _Nullable data,
        NSURLResponse * _Nullable response,
        NSError * _Nullable error) {
        if (error == nil) {
            NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSError *e = nil;
            NSData *jsonData = [responseString dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *configData = [NSJSONSerialization JSONObjectWithData:jsonData options: NSJSONReadingMutableContainers error: &e];
            if (e == nil && configData != nil) {
                [Gleap.sharedInstance configureGleapWithConfig: configData];
                return;
            }
        }
        
        NSLog(@"[GLEAP_SDK] Gleap auto-configuration failed. Please check your API key and internet connection.");
    }] resume];
}

- (void)configureGleapWithConfig: (NSDictionary *)config {
    if ([config objectForKey: @"enableNetworkLogs"] != nil && [[config objectForKey: @"enableNetworkLogs"] boolValue] == YES) {
        [Gleap startNetworkRecording];
    }
    
    if ([config objectForKey: @"replaysInterval"] != nil) {
        int interval = [[config objectForKey: @"replaysInterval"] intValue];
        if (interval > 0) {
            self.replayInterval = interval;
        }
    }
    
    if ([config objectForKey: @"enableReplays"] != nil) {
        [Gleap enableReplays: [[config objectForKey: @"enableReplays"] boolValue]];
    }
    
    
    if ([config objectForKey: @"networkLogPropsToIgnore"] != nil && [[config objectForKey: @"networkLogPropsToIgnore"] isKindOfClass:[NSArray class]]) {
        self.networkLogPropsToIgnore = [config objectForKey: @"networkLogPropsToIgnore"];
    }
    
    if (!self.disableAutoActivationMethods) {
        NSMutableArray * activationMethods = [[NSMutableArray alloc] init];
        if ([config objectForKey: @"activationMethodShake"] != nil && [[config objectForKey: @"activationMethodShake"] boolValue] == YES) {
            [activationMethods addObject: @(SHAKE)];
        }
        if ([config objectForKey: @"activationMethodScreenshotGesture"] != nil && [[config objectForKey: @"activationMethodScreenshotGesture"] boolValue] == YES) {
            [activationMethods addObject: @(SCREENSHOT)];
        }
        self.activationMethods = activationMethods;
    }
    
    if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(configLoaded:)]) {
        [Gleap.sharedInstance.delegate configLoaded: config];
    }
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

/**
 Check if activation method exists
 */
- (BOOL)isActivationMethodActive: (GleapActivationMethod)activationMethod {
    for (int i = 0; i < self.activationMethods.count; i++) {
        GleapActivationMethod currentActivationMethod = [[self.activationMethods objectAtIndex: i] intValue];
        if (currentActivationMethod == activationMethod) {
            return true;
        }
    }
    return false;
}

- (void)initializeScreenshotRecognizer {
    @try {
        NSOperationQueue *mainQueue = [NSOperationQueue mainQueue];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationUserDidTakeScreenshotNotification
                                                          object:nil
                                                           queue:mainQueue
                                                      usingBlock:^(NSNotification *note) {
            if ([self isActivationMethodActive: SCREENSHOT]) {
                [Gleap startFeedbackFlow];
            }
        }];
    } @catch(id anException) {}
}

+ (void)setApiUrl: (NSString *)apiUrl {
    Gleap.sharedInstance.apiUrl = apiUrl;
}

+ (void)setWidgetUrl: (NSString *)widgetUrl {
    Gleap.sharedInstance.widgetUrl = widgetUrl;
}

/*
 Get's the framework's NSBundle.
 */
+ (NSBundle *)frameworkBundle {
    return [NSBundle bundleForClass: [Gleap class]];
}

+ (void)open {
    [self startFeedbackFlow];
}

/*
 Starts the bug reporting flow, when a SDK key has been assigned.
 */
+ (void)startFeedbackFlow {
    UIImage * screenshot = [Gleap.sharedInstance captureScreen];
    [self startFeedbackFlowWithScreenshot: screenshot];
}

+ (void)startFeedbackFlow:(NSString *)feedbackFlow; {
    Gleap.sharedInstance.startFlow = feedbackFlow;
    [self startFeedbackFlow];
}

/*
 Sends a silent bug report.
 */
+ (void)sendSilentBugReportWith:(NSString *)description andSeverity:(GleapBugSeverity)severity; {
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
    
    [Gleap attachData: dataToAppend];
    
    UIImage * screenshot = [Gleap.sharedInstance captureScreen];
    [self startFeedbackFlowWithScreenshot: screenshot andUI: false];
}

/*
 Starts the bug reporting flow, when a SDK key has been assigned.
 */
+ (void)startFeedbackFlowWithScreenshot:(UIImage *)screenshot {
    [self startFeedbackFlowWithScreenshot: screenshot andUI: true];
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
    [Gleap.sharedInstance updateLastScreenName];
    
    // Stop replays
    [[GleapReplayHelper sharedInstance] stop];
    [Gleap attachScreenshot: screenshot];
    
    if (ui) {
        GleapWidgetViewController *gleapWidget = [[GleapWidgetViewController alloc] init];
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
        UIViewController *topMostViewController = [Gleap.sharedInstance getTopMostViewController];
        [topMostViewController presentViewController: navController animated: YES completion:^{
            
        }];
    } else {
        // startFeedbackFlowWithScreenshot
        // No UI flow
        [Gleap.sharedInstance sendReport:^(bool success) {
            if (success) {
                if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(feedbackSent)]) {
                    [Gleap.sharedInstance.delegate feedbackSent];
                }
            } else {
                if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(feedbackSendingFailed)]) {
                    [Gleap.sharedInstance.delegate feedbackSendingFailed];
                }
            }
            [Gleap afterBugReportCleanup];
        }];
    }
}

/*
 Invoked when a shake gesture is beeing performed.
 */
+ (void)shakeInvocation {
    if ([[Gleap sharedInstance] isActivationMethodActive: SHAKE]) {
        [Gleap startFeedbackFlow];
    }
}

/*
 Attaches custom data, which can be viewed in the Gleap dashboard. New data will be merged with existing custom data.
 */
+ (void)attachCustomData: (NSDictionary *)customData {
    [[Gleap sharedInstance].customData addEntriesFromDictionary: customData];
}

/*
 Clears all custom data.
 */
+ (void)clearCustomData {
    [[Gleap sharedInstance].customData removeAllObjects];
}

/**
 * Attach one key value pair to existing custom data.
 */
+ (void)setCustomData: (NSString *)value forKey: (NSString *)key {
    [[Gleap sharedInstance].customData setObject: value forKey: key];
}

/**
 * Removes one key from existing custom data.
 */
+ (void)removeCustomDataForKey: (NSString *)key {
    [[Gleap sharedInstance].customData removeObjectForKey: key];
}

/**
 * Attaches a file to the bug report
 */
+ (bool)addAttachmentWithPath: (NSString *)filePath {
    if (![[NSFileManager defaultManager] fileExistsAtPath: filePath]) {
        return false;
    }
    
    NSError* error = nil;
    NSData* data = [NSData dataWithContentsOfFile: filePath options:0 error: &error];
    if (error == nil && data != nil) {
        return [self addAttachmentWithData: data andName: filePath];
    } else {
        return false;
    }
}

+ (bool)addAttachmentWithData:(NSData *)data andName:(NSString *)name {
    if ([Gleap sharedInstance].customAttachments.count > 6) {
        NSLog(@"[GLEAP_SDK] Attachment limit of 6 files reached.");
        return false;
    }
    
    NSString * mimeType = @"text/plain";
    NSString *pathExtension = [name pathExtension];
    
    if ([pathExtension isEqualToString: @"json"]) {
        mimeType = @"application/json";
    }
    if ([pathExtension isEqualToString: @"xml"]) {
        mimeType = @"application/xml";
    }
    if ([pathExtension isEqualToString: @"svg"]) {
        mimeType = @"image/svg+xml";
    }
    if ([pathExtension isEqualToString: @"jpg"] || [pathExtension isEqualToString: @"jpeg"]) {
        mimeType = @"image/jpeg";
    }
    if ([pathExtension isEqualToString: @"png"]) {
        mimeType = @"image/png";
    }
    if ([pathExtension isEqualToString: @"mp4"]) {
        mimeType = @"video/mp4";
    }
    
    [[Gleap sharedInstance].customAttachments addObject: @{
        @"name": [name lastPathComponent],
        @"data": data,
        @"type": mimeType,
    }];
    
    return true;
}

/**
 * Removes all attachments
 */
+ (void)removeAllAttachments {
    [[Gleap sharedInstance].customAttachments removeAllObjects];
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

/*
 Attaches custom data to a report.
 */
+ (void)attachData: (NSDictionary *)data {
    [Gleap.sharedInstance.data addEntriesFromDictionary: data];
}

/**
 Sets the application type.
 */
+ (void)setApplicationType: (GleapApplicationType)applicationType {
    Gleap.sharedInstance.applicationType = applicationType;
}

/*
 Captures the current screen as UIImage.
 */
- (UIImage *)captureScreen {
    UIWindow *keyWindow = [[UIApplication sharedApplication] keyWindow];
    
    if (self.applicationType == FLUTTER) {
        UIGraphicsBeginImageContextWithOptions([keyWindow bounds].size, false, [UIScreen mainScreen].scale);
        NSArray *views = [keyWindow subviews];
        for (int i = 0; i < views.count; i++) {
            UIView *view = [views objectAtIndex: i];
            [view drawViewHierarchyInRect: view.bounds afterScreenUpdates: true];
        }
    } else {
        UIGraphicsBeginImageContextWithOptions([keyWindow bounds].size, false, [UIScreen mainScreen].scale);
        CGContextRef context = UIGraphicsGetCurrentContext();
        [keyWindow.layer renderInContext: context];
    }
    
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

/*
 Sends a bugreport to our backend.
 */
- (void)sendReport: (void (^)(bool success))completion {
    [self optionallyUploadReplaySteps:^(bool success) {
        [self optionallyUploadAttachments:^(bool success) {
            [self uploadScreenshotAndSendBugReport:^(bool success) {
                [self prepareScreenshotDataAndSend:^(bool success) {
                    completion(success);
                }];
            }];
        }];
    }];
}

/*
 Optionally upload attachments (if any exist)
 */
- (void)optionallyUploadAttachments: (void (^)(bool success))completion {
    if ([self.excludeData objectForKey: @"attachments"] != nil && [[self.excludeData objectForKey: @"attachments"] boolValue] == YES) {
        completion(YES);
    } else {
        if (self.customAttachments.count > 0) {
            [self uploadFiles: self.customAttachments forEndpoint: @"attachments" andCompletion:^(bool success, NSArray *fileUrls) {
                if (success) {
                    // Attach attachments
                    NSMutableArray *attachmentsArray = [[NSMutableArray alloc] init];
                    
                    for (int i = 0; i < self.customAttachments.count; i++) {
                        NSMutableDictionary *currentAttachment = [[self.customAttachments objectAtIndex: i] mutableCopy];
                        NSString *currentAttachmentURL = [fileUrls objectAtIndex: i];
                        [currentAttachment setObject: currentAttachmentURL forKey: @"url"];
                        [currentAttachment removeObjectForKey: @"data"];
                        [attachmentsArray addObject: currentAttachment];
                    }
                    
                    [Gleap attachData: @{ @"attachments": attachmentsArray }];
                }
                
                completion(success);
            }];
        } else {
            completion(YES);
        }
    }
}

/*
 Optionally upload replays steps (if any exist)
 */
- (void)optionallyUploadReplaySteps: (void (^)(bool success))completion {
    if ([self.excludeData objectForKey: @"replays"] != nil && [[self.excludeData objectForKey: @"replays"] boolValue] == YES) {
        completion(YES);
    } else {
        NSNumber *replayInterval = [NSNumber numberWithInt: self.replayInterval * 1000];
        if (self.replaysEnabled) {
            [[Gleap sharedInstance] uploadStepImages: [GleapReplayHelper sharedInstance].replaySteps andCompletion:^(bool success, NSArray * _Nonnull fileUrls) {
                if (success) {
                    // Attach replay
                    [Gleap attachData: @{ @"replay": @{
                                                      @"interval": replayInterval,
                                                      @"frames": fileUrls
                    } }];
                }
                
                completion(success);
            }];
        } else {
            completion(YES);
        }
    }
}

- (void)updateLastScreenName {
    _lastScreenName = [self getTopMostViewControllerName];
}

- (void)uploadScreenshotAndSendBugReport: (void (^)(bool success))completion {
    if ([self.excludeData objectForKey: @"replays"] != nil && [[self.excludeData objectForKey: @"replays"] boolValue] == YES) {
        completion(YES);
    } else {
        // Process with image upload
        [self uploadImage: self.screenshot andCompletion:^(bool success, NSString *fileUrl) {
            if (!success) {
                return completion(false);
            }
            
            // Set screenshot url.
            NSMutableDictionary *dataToAppend = [[NSMutableDictionary alloc] init];
            [dataToAppend setValue: fileUrl forKey: @"screenshotUrl"];
            [Gleap attachData: dataToAppend];
            
            return completion(YES);
        }];
    }
}

- (void)prepareScreenshotDataAndSend: (void (^)(bool success))completion {
    // Fetch additional metadata.
    [Gleap attachData: @{ @"metaData": [self getMetaData] }];
    
    // Attach and merge console log.
    NSMutableArray *consoleLogs = [[NSMutableArray alloc] initWithArray: self->_consoleLog];
    if ([Gleap.sharedInstance.data objectForKey: @"consoleLog"] != nil) {
        NSArray *existingConsoleLogs = [Gleap.sharedInstance.data objectForKey: @"consoleLog"];
        if (existingConsoleLogs != nil && existingConsoleLogs.count > 0) {
            [consoleLogs addObjectsFromArray: existingConsoleLogs];
        }
    }
    [Gleap attachData: @{ @"consoleLog": consoleLogs }];
    
    // Attach custom data.
    [Gleap attachData: @{ @"customData": [self customData] }];
    
    // Attach custom event log.
    [Gleap attachData: @{ @"customEventLog": [[GleapLogHelper sharedInstance] getLogs] }];
    
    // Attach and merge network logs.
    NSMutableArray *networkLogs = [[NSMutableArray alloc] initWithArray: [[GleapHttpTrafficRecorder sharedRecorder] networkLogs]];
    if ([Gleap.sharedInstance.data objectForKey: @"networkLogs"] != nil) {
        NSArray *existingNetworkLogs = [Gleap.sharedInstance.data objectForKey: @"networkLogs"];
        if (existingNetworkLogs != nil && existingNetworkLogs.count > 0) {
            [networkLogs addObjectsFromArray: existingNetworkLogs];
        }
    }
    if ([networkLogs count] > 0) {
        [Gleap attachData: @{ @"networkLogs": [self filterNetworkLogs: networkLogs] }];
    }
    
    // Add outbound
    if (Gleap.sharedInstance.action != nil) {
        [Gleap attachData: @{ @"outbound": Gleap.sharedInstance.action.outbound }];
    }
    
    [self excludeExcludedData];
    
    // Sending report to server.
    return [self sendReportToServer:^(bool success) {
        completion(success);
    }];
}

- (NSArray *)filterNetworkLogs:(NSArray *)networkLogs {
    if (self.networkLogPropsToIgnore == nil || [self.networkLogPropsToIgnore count] <= 0) {
        return networkLogs;
    }
    
    NSMutableArray* processedNetworkLogs = [[NSMutableArray alloc] init];
    
    // Filter networklog properties.
    for (int i = 0; i < [networkLogs count]; i++) {
        NSMutableDictionary * log =  [[NSMutableDictionary alloc] initWithDictionary: [networkLogs objectAtIndex: i]];
        
        if ([log objectForKey: @"request"] != nil) {
            NSMutableDictionary *request = [[NSMutableDictionary alloc] initWithDictionary: [log objectForKey: @"request"]];
            if (request != nil && [request objectForKey: @"headers"]) {
                if ([request objectForKey: @"headers"] != nil) {
                    NSMutableDictionary *mutableHeaders = [[NSMutableDictionary alloc] initWithDictionary: [request objectForKey: @"headers"]];
                    [mutableHeaders removeObjectsForKeys: self.networkLogPropsToIgnore];
                    [request setObject: mutableHeaders forKey: @"headers"];
                }
            }
            
            if (request != nil && [request objectForKey: @"payload"]) {
                if ([request objectForKey: @"payload"] != nil) {
                    NSError *jsonError;
                    NSMutableDictionary *jsonObject = [NSJSONSerialization JSONObjectWithData:[[request objectForKey: @"payload"] dataUsingEncoding:NSUTF8StringEncoding]  options: NSJSONReadingMutableContainers error:&jsonError];
                    if (jsonError == nil && jsonObject != nil) {
                        [jsonObject removeObjectsForKeys: self.networkLogPropsToIgnore];
                        
                        NSError *jsonDataError;
                        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonObject
                                                                           options:0
                                                                             error:&jsonDataError];
                        if (jsonData != nil) {
                            NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                            if (jsonString != nil) {
                                [request setObject: jsonString forKey: @"payload"];
                            }
                        }
                    }
                }
            }
            if (request != nil) {
                [log setObject: request forKey: @"request"];
            }
        }
        
        if ([log objectForKey: @"response"] != nil) {
            NSMutableDictionary *response = [[NSMutableDictionary alloc] initWithDictionary: [log objectForKey: @"response"]];
            if (response != nil && [response objectForKey: @"responseText"] != nil) {
                NSError *jsonError;
                NSMutableDictionary *jsonObject = [NSJSONSerialization JSONObjectWithData:[[response objectForKey: @"responseText"] dataUsingEncoding:NSUTF8StringEncoding]  options: NSJSONReadingMutableContainers error:&jsonError];
                if (jsonError == nil && jsonObject != nil) {
                    [jsonObject removeObjectsForKeys: self.networkLogPropsToIgnore];
                    
                    NSError *jsonDataError;
                    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonObject
                                                                       options:0
                                                                         error:&jsonDataError];
                    if (jsonData != nil) {
                        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                        if (jsonString != nil) {
                            [response setObject: jsonString forKey: @"responseText"];
                        }
                    }
                }
                
                [log setObject: response forKey: @"response"];
            }
        }
        
        [processedNetworkLogs addObject: log];
    }
    
    return [processedNetworkLogs copy];
}

- (void)excludeExcludedData {
    if (self.excludeData == nil) {
        return;
    }
    
    for (int i = 0; i < self.excludeData.allKeys.count; i++) {
        NSString *key = [self.excludeData.allKeys objectAtIndex: i];
        if ([[self.excludeData objectForKey: key] boolValue] == YES) {
            [Gleap.sharedInstance.data removeObjectForKey: key];
        }
    }
}

/*
 Sends a bugreport to our backend.
 */
- (void)sendReportToServer: (void (^)(bool success))completion {
    if (_token == NULL || [_token isEqualToString: @""]) {
        return completion(false);
    }
    
    NSError *error;
    NSData *jsonBodyData = [NSJSONSerialization dataWithJSONObject: _data options:kNilOptions error: &error];
    
    // Check for parsing error.
    if (error != nil) {
        return completion(false);
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest new];
    request.HTTPMethod = @"POST";
    [request setURL: [NSURL URLWithString: [NSString stringWithFormat: @"%@/bugs", _apiUrl]]];
    [GleapSessionHelper injectSessionInRequest: request];
    [request setValue: @"application/json" forHTTPHeaderField: @"Content-Type"];
    [request setValue: @"application/json" forHTTPHeaderField: @"Accept"];
    [request setHTTPBody: jsonBodyData];
    
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config
                                                          delegate:nil
                                                     delegateQueue:[NSOperationQueue mainQueue]];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData * _Nullable data,
                                                                NSURLResponse * _Nullable response,
                                                                NSError * _Nullable error) {
                                                if (error != nil) {
                                                    return completion(false);
                                                }
                                                return completion(true);
                                            }];
    [task resume];
}

/*
 Upload file
 */
- (void)uploadFile: (NSData *)fileData andFileName: (NSString*)filename andContentType: (NSString*)contentType andCompletion: (void (^)(bool success, NSString *fileUrl))completion {
    NSMutableURLRequest *request = [NSMutableURLRequest new];
    [request setURL: [NSURL URLWithString: [NSString stringWithFormat: @"%@/uploads/sdk", _apiUrl]]];
    [GleapSessionHelper injectSessionInRequest: request];
    [request setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
    [request setHTTPShouldHandleCookies:NO];
    [request setTimeoutInterval:60];
    [request setHTTPMethod:@"POST"];
    
    // Build multipart/form-data
    NSString *boundary = @"BBBOUNDARY";
    NSString *headerContentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
    [request setValue: headerContentType forHTTPHeaderField: @"Content-Type"];
    NSMutableData *body = [NSMutableData data];
    
    // Add file data
    if (fileData) {
        [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=%@; filename=%@\r\n", @"file", filename] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat: @"Content-Type: %@\r\n\r\n", contentType] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData: fileData];
        [body appendData:[[NSString stringWithFormat:@"\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    }
    
    [body appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    
    // Setting the body of the post to the reqeust
    [request setHTTPBody:body];
    
    // Set the content-length
    NSString *postLength = [NSString stringWithFormat:@"%lu", (unsigned long)[body length]];
    [request setValue:postLength forHTTPHeaderField:@"Content-Length"];
    
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:[NSOperationQueue mainQueue]];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error != NULL) {
            return completion(false, nil);
        }
        
        NSError *parseError = nil;
        NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData: data options: 0 error:&parseError];
        if (!parseError) {
            NSString* fileUrl = [responseDict objectForKey: @"fileUrl"];
            return completion(true, fileUrl);
        } else {
            return completion(false, nil);
        }
    }];
    [task resume];
}

/*
 Upload image
 */
- (void)uploadImage: (UIImage *)image andCompletion: (void (^)(bool success, NSString *fileUrl))completion {
    NSData *imageData = UIImageJPEGRepresentation(image, 0.8);
    NSString *contentType = @"image/jpeg";
    [self uploadFile: imageData andFileName: @"screenshot.jpeg" andContentType: contentType andCompletion: completion];
}

/*
 Upload SDK steps
 */
- (void)uploadStepImages: (NSArray *)steps andCompletion: (void (^)(bool success, NSArray *fileUrls))completion {
    // Prepare images for upload.
    NSMutableArray * files = [[NSMutableArray alloc] init];
    for (int i = 0; i < steps.count; i++) {
        NSDictionary *currentStep = [steps objectAtIndex: i];
        UIImage *currentImage = [currentStep objectForKey: @"image"];
        
        // Resize screenshot
        CGSize size = CGSizeMake(currentImage.size.width * 0.5, currentImage.size.height * 0.5);
        UIGraphicsBeginImageContext(size);
        [currentImage drawInRect:CGRectMake(0, 0, size.width, size.height)];
        UIImage *destImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        NSData *imageData = UIImageJPEGRepresentation(destImage, 0.9);
        NSString *filename = [NSString stringWithFormat: @"step_%i", i];
        
        if (imageData != nil) {
            [files addObject: @{
                @"name": filename,
                @"data": imageData,
                @"type": @"image/jpeg",
            }];
        }
    }
    
    [self uploadFiles: files forEndpoint: @"sdksteps" andCompletion:^(bool success, NSArray *fileUrls) {
        if (success) {
            NSMutableArray *replayArray = [[NSMutableArray alloc] init];
            
            for (int i = 0; i < fileUrls.count; i++) {
                NSMutableDictionary *currentStep = [[steps objectAtIndex: i] mutableCopy];
                NSString *currentImageUrl = [fileUrls objectAtIndex: i];
                [currentStep setObject: currentImageUrl forKey: @"url"];
                [currentStep removeObjectForKey: @"image"];
                [replayArray addObject: currentStep];
            }
            
            return completion(true, replayArray);
        } else {
            return completion(false, nil);
        }
    }];
}

/*
 Upload files
 */
- (void)uploadFiles: (NSArray *)files forEndpoint:(NSString *)endpoint andCompletion: (void (^)(bool success, NSArray *fileUrls))completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableURLRequest *request = [NSMutableURLRequest new];
        [request setURL: [NSURL URLWithString: [NSString stringWithFormat: @"%@/uploads/%@", self->_apiUrl, endpoint]]];
        [GleapSessionHelper injectSessionInRequest: request];
        [request setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
        [request setHTTPShouldHandleCookies:NO];
        [request setTimeoutInterval:60];
        [request setHTTPMethod:@"POST"];
        
        // Build multipart/form-data
        NSString *boundary = @"BBBOUNDARY";
        NSString *headerContentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
        [request setValue: headerContentType forHTTPHeaderField: @"Content-Type"];
        NSMutableData *body = [NSMutableData data];
        
        for (int i = 0; i < files.count; i++) {
            NSDictionary *currentFile = [files objectAtIndex: i];
            NSData *fileData = [currentFile objectForKey: @"data"];
            NSData *fileName = [currentFile objectForKey: @"name"];
            NSData *fileContentType = [currentFile objectForKey: @"type"];
            
            if (fileData != nil && fileName != nil) {
                [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
                [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=%@; filename=%@\r\n", @"file", fileName] dataUsingEncoding:NSUTF8StringEncoding]];
                [body appendData:[[NSString stringWithFormat: @"Content-Type: %@\r\n\r\n", fileContentType] dataUsingEncoding:NSUTF8StringEncoding]];
                [body appendData: fileData];
                [body appendData:[[NSString stringWithFormat:@"\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
            }
        }
        
        [body appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        [request setHTTPBody:body];
        NSString *postLength = [NSString stringWithFormat:@"%lu", (unsigned long)[body length]];
        [request setValue:postLength forHTTPHeaderField:@"Content-Length"];
        
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:[NSOperationQueue mainQueue]];
        NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            if (error != NULL) {
                return completion(false, nil);
            }
            
            NSError *parseError = nil;
            NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData: data options: 0 error:&parseError];
            if (!parseError) {
                NSArray* fileUrls = [responseDict objectForKey: @"fileUrls"];
                return completion(true, fileUrls);
            } else {
                return completion(false, nil);
            }
        }];
        [task resume];
    });
}

/*
 Returns the session's duration.
 */
- (double)sessionDuration {
    return [_sessionStart timeIntervalSinceNow] * -1.0;
}

/**
    Returns the device model name;
 */
- (NSString*)getDeviceModelName
{
    struct utsname systemInfo;
    uname(&systemInfo);
    return [NSString stringWithCString: systemInfo.machine
                              encoding:NSUTF8StringEncoding];
}

- (NSString *)getApplicationTypeAsString {
    NSString *applicationType = @"iOS";
    if (self.applicationType == FLUTTER) {
        applicationType = @"Flutter/iOS";
    } else if (self.applicationType == REACTNATIVE) {
        applicationType = @"ReactNative/iOS";
    }
    return applicationType;
}

- (NSString *)getPhoneChargingState {
    UIDevice *currentDevice = [UIDevice currentDevice];
    [currentDevice setBatteryMonitoringEnabled:YES];
    switch ([currentDevice batteryState]) {
        case UIDeviceBatteryStateCharging:
            return @"Charging";
        case UIDeviceBatteryStateFull:
            return @"Full";
        case UIDeviceBatteryStateUnplugged:
            return @"Unplugged";
        case UIDeviceBatteryStateUnknown:
            return @"Unknown";
    }
    
    return @"Unknown";
}

- (NSDictionary *)getDiskInfo {
    NSString* totalSpace = @"Unknown";
    NSString* totalFreeSpace = @"Unknown";
    NSError *error = nil;
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSDictionary *dictionary = [[NSFileManager defaultManager] attributesOfFileSystemForPath:[paths lastObject] error: &error];
    if (dictionary) {
        NSNumber *fileSystemSizeInBytes = [dictionary objectForKey: NSFileSystemSize];
        NSNumber *freeFileSystemSizeInBytes = [dictionary objectForKey:NSFileSystemFreeSize];
        totalSpace = [NSString stringWithFormat: @"%llu", ([fileSystemSizeInBytes unsignedLongLongValue]/1000ll/1000ll/1000ll)];
        totalFreeSpace = [NSString stringWithFormat: @"%llu", ([freeFileSystemSizeInBytes unsignedLongLongValue]/1000ll/1000ll/1000ll)];
        
        if (@available(iOS 11.0, *)) {
            NSURL *homePathURL = [[NSURL alloc] initFileURLWithPath: NSHomeDirectory()];
            id resourceResults = [homePathURL resourceValuesForKeys:@[NSURLVolumeAvailableCapacityForImportantUsageKey] error:nil];
            if (resourceResults[NSURLVolumeAvailableCapacityForImportantUsageKey] != nil) {
                totalFreeSpace = [NSString stringWithFormat: @"%lld", ([resourceResults[NSURLVolumeAvailableCapacityForImportantUsageKey] longLongValue] / 1024ll / 1024ll / 1024ll)];
            }
        }
    }
    
    return @{
        @"totalSpace": totalSpace,
        @"totalFreeSpace": totalFreeSpace,
    };
}

/*
 Returns all meta data as an NSDictionary.
 */
- (NSDictionary *)getMetaData {
    UIDevice *currentDevice = [UIDevice currentDevice];
    NSString *deviceName = currentDevice.name;
    NSString *deviceModel = [self getDeviceModelName];
    NSString *systemName = currentDevice.systemName;
    NSString *systemVersion = currentDevice.systemVersion;
    NSString *deviceIdentifier = [[currentDevice identifierForVendor] UUIDString];
    NSString *bundleId = NSBundle.mainBundle.bundleIdentifier;
    NSString *releaseVersionNumber = [NSBundle.mainBundle.infoDictionary objectForKey: @"CFBundleShortVersionString"];
    NSString *buildVersionNumber = [NSBundle.mainBundle.infoDictionary objectForKey: @"CFBundleVersion"];
    NSNumber *sessionDuration = [NSNumber numberWithDouble: [self sessionDuration]];
    NSString *preferredUserLocale = [[[NSBundle mainBundle] preferredLocalizations] firstObject];
    NSString *batteryLevel = @"Unknown";
    NSString * phoneChargingState = [self getPhoneChargingState];
    if (![phoneChargingState isEqualToString: @"Unknown"]) {
        batteryLevel = [NSString stringWithFormat:@"%.f", (float)[currentDevice batteryLevel] * 100];
    }
    NSString *lowPowerModeEnabled = [[NSProcessInfo processInfo] isLowPowerModeEnabled] ? @"true": @"false";
    NSDictionary *diskInfo = [self getDiskInfo];
    NSString *buildMode = @"DEBUG";
    #ifdef RELEASE
    buildMode = @"RELEASE";
    #endif
        
    return @{
        @"deviceName": deviceName,
        @"deviceModel": deviceModel,
        @"deviceIdentifier": deviceIdentifier,
        @"bundleID": bundleId,
        @"systemName": systemName,
        @"systemVersion": systemVersion,
        @"buildVersionNumber": buildVersionNumber,
        @"releaseVersionNumber": releaseVersionNumber,
        @"sessionDuration": sessionDuration,
        @"lastScreenName": _lastScreenName,
        @"preferredUserLocale": preferredUserLocale,
        @"sdkType": [self getApplicationTypeAsString],
        @"sdkVersion": SDK_VERSION,
        @"buildMode": buildMode,
        @"batteryLevel": batteryLevel,
        @"phoneChargingStatus": phoneChargingState,
        @"batterySaveMode": lowPowerModeEnabled,
        @"totalDiskSpace": [diskInfo objectForKey: @"totalSpace"],
        @"totalFreeDiskSpace": [diskInfo objectForKey: @"totalFreeSpace"]
    };
}

- (NSString *)getJSStringForNSDate:(NSDate *)date {
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZ";
    return [dateFormatter stringFromDate: date];
}

/*
 Starts reading the console output.
 */
- (void)openConsoleLog {
    @try
    {
        #ifdef DEBUG
        if (self.debugConsoleLogDisabled != YES) {
            _inputPipe = [[NSPipe alloc] init];
            _outputPipe = [[NSPipe alloc] init];
            
            dup2(STDOUT_FILENO, _outputPipe.fileHandleForWriting.fileDescriptor);
            dup2(_inputPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO);
            dup2(_inputPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO);
            
            [NSNotificationCenter.defaultCenter addObserver: self selector: @selector(receiveLogNotification:)  name: NSFileHandleReadCompletionNotification object: _inputPipe.fileHandleForReading];
            
            [_inputPipe.fileHandleForReading readInBackgroundAndNotify];
        }
        #else
        _inputPipe = [[NSPipe alloc] init];
        
        dup2([[_inputPipe fileHandleForWriting] fileDescriptor], STDERR_FILENO);
        
        [NSNotificationCenter.defaultCenter addObserver: self selector: @selector(receiveLogNotification:)  name: NSFileHandleReadCompletionNotification object: _inputPipe.fileHandleForReading];
        
        [_inputPipe.fileHandleForReading readInBackgroundAndNotify];
        #endif
    }
    @catch(id anException) {}
}

- (void)performAction:(GleapAction *)action {
    if (self.action != nil) {
        NSLog(@"[GLEAP_SDK] Already performing action.");
        return;
    }
    
    self.action = action;
    [Gleap startFeedbackFlow: action.actionType];
}

/*
 This callback receives all console output notifications and saves them for further use.
 */
- (void)receiveLogNotification:(NSNotification *) notification
{
    [_inputPipe.fileHandleForReading readInBackgroundAndNotify];
    NSData *data = notification.userInfo[NSFileHandleNotificationDataItem];
    
    // Write data to output pipe
    if (_outputPipe != nil) {
        [[_outputPipe fileHandleForWriting] writeData: data];
    }
    
    NSString *consoleLogLines = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
    if (consoleLogLines != NULL) {
        
        NSError *error = nil;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\d+-\\d+-\\d+ \\d+:\\d+:\\d+.\\d+\\+\\d+ .+\\[.+:.+\\] " options:NSRegularExpressionCaseInsensitive error:&error];
        consoleLogLines = [regex stringByReplacingMatchesInString: consoleLogLines options: 0 range:NSMakeRange(0, [consoleLogLines length]) withTemplate:@"#BBNL#"];
        
        NSArray *lines = [consoleLogLines componentsSeparatedByString: @"#BBNL#"];
        for (int i = 0; i < lines.count; i++) {
            NSString *line = [lines objectAtIndex: i];
            if (line != NULL && ![line isEqualToString: @""]) {
                NSString *dateString = [self getJSStringForNSDate: [[NSDate alloc] init]];
                NSDictionary *log = @{ @"date": dateString, @"log": line, @"priority": @"INFO" };
                if (!Gleap.sharedInstance.currentlyOpened) {
                    if (_consoleLog.count > 1000) {
                        [_consoleLog removeObjectAtIndex: 0];
                    }
                    [_consoleLog addObject: log];
                }
            }
        }
    }
}

@end
