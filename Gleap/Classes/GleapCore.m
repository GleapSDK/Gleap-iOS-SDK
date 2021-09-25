//
//  Gleap.m
//  AyAyObjectiveCPort
//
//  Created by Lukas on 13.01.19.
//  Copyright © 2019 Gleap. All rights reserved.
//

#import "GleapCore.h"
#import "GleapWidgetViewController.h"
#import "GleapReplayHelper.h"
#import "GleapHttpTrafficRecorder.h"
#import "GleapSessionHelper.h"
#import "GleapUserSession.h"
#import "GleapLogHelper.h"
#import <sys/utsname.h>

@interface Gleap ()

@property (strong, nonatomic) UIImage *screenshot;
@property (retain, nonatomic) NSDate *sessionStart;
@property (retain, nonatomic) NSMutableArray *consoleLog;
@property (retain, nonatomic) NSMutableArray *callstack;
@property (retain, nonatomic) NSMutableArray *stepsToReproduce;
@property (retain, nonatomic) NSMutableDictionary *customData;
@property (retain, nonatomic) NSMutableDictionary *customActions;
@property (retain, nonatomic) NSPipe *inputPipe;
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
    self.apiUrl = @"https://api.gleap.io";
    self.widgetUrl = @"https://widget.gleap.io";
    self.activationMethods = [[NSArray alloc] init];
    self.applicationType = NATIVE;
    self.screenshot = nil;
    self.data = [[NSMutableDictionary alloc] init];
    self.sessionStart = [[NSDate alloc] init];
    self.consoleLog = [[NSMutableArray alloc] init];
    self.callstack = [[NSMutableArray alloc] init];
    self.stepsToReproduce = [[NSMutableArray alloc] init];
    self.customData = [[NSMutableDictionary alloc] init];
    self.language = [[NSLocale preferredLanguages] firstObject];
}

+ (void)afterBugReportCleanup {
    if ([Gleap sharedInstance].replaysEnabled) {
        [[GleapReplayHelper sharedInstance] start];
    }
    
    Gleap.sharedInstance.currentlyOpened = NO;
}

+ (void)setLanguage: (NSString *)language {
    [Gleap sharedInstance].language = language;
}

+ (void)disableConsoleLog {
    [Gleap sharedInstance].consoleLogDisabled = true;
}

+ (void)enableReplays: (BOOL)enable {
    [Gleap sharedInstance].replaysEnabled = enable;
    
    if ([Gleap sharedInstance].replaysEnabled) {
        // Starts the replay helper.
        [[GleapReplayHelper sharedInstance] start];
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

+ (void)initializeWithToken: (NSString *)token andUserSession: (nullable GleapUserSession *)userSession {
    Gleap* instance = [Gleap sharedInstance];
    [instance setSDKToken: token];
    [[GleapSessionHelper sharedInstance] startSessionWithData: userSession andCompletion:^(bool success) {
        [self autoConfigure];
    }];
}

/*
 Autoconfigure with token
 */
+ (void)initializeWithToken: (NSString *)token {
    [Gleap initializeWithToken: token andUserSession: nil];
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
        
        NSLog(@"Bugbattle: Auto-configuration failed. Please check your API key and internet connection.");
    }] resume];
}

- (void)configureGleapWithConfig: (NSDictionary *)config {
    if ([config objectForKey: @"enableNetworkLogs"] != nil && [[config objectForKey: @"enableNetworkLogs"] boolValue] == YES) {
        [Gleap startNetworkRecording];
    }
    if ([config objectForKey: @"enableReplays"] != nil) {
        [Gleap enableReplays: [[config objectForKey: @"enableReplays"] boolValue]];
    }
    NSMutableArray * activationMethods = [[NSMutableArray alloc] init];
    if ([config objectForKey: @"activationMethodShake"] != nil && [[config objectForKey: @"activationMethodShake"] boolValue] == YES) {
        [activationMethods addObject: @(SHAKE)];
    }
    if ([config objectForKey: @"activationMethodScreenshotGesture"] != nil && [[config objectForKey: @"activationMethodScreenshotGesture"] boolValue] == YES) {
        [activationMethods addObject: @(SCREENSHOT)];
    }
    if ([config objectForKey: @"activationMethodThreeFingerDoubleTab"] != nil && [[config objectForKey: @"activationMethodThreeFingerDoubleTab"] boolValue] == YES) {
        [activationMethods addObject: @(THREE_FINGER_DOUBLE_TAB)];
    }
    
    if (activationMethods.count > 0) {
        _activationMethods = activationMethods;
        [self performActivationMethodInit];
    }
}

/**
 * Updates a session's user data.
 * @author Gleap
 *
 * @param data The updated user data.
 */
+ (void)updateUserSessionWithData:(nullable GleapUserSession *)data {
    [GleapSessionHelper.sharedInstance startSessionWithData: data andCompletion:^(bool success) {}];
}

/**
 * Clears a user session.
 * @author Gleap
 */
+ (void)clearUserSession {
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

/**
    Performs initial checks for activation methods.
 */
- (void)performActivationMethodInit {
    if ([self isActivationMethodActive: THREE_FINGER_DOUBLE_TAB]) {
        [self initializeGestureRecognizer];
    }
    
    if ([self isActivationMethodActive: SCREENSHOT]) {
        [self initializeScreenshotRecognizer];
    }
}

- (void)initializeScreenshotRecognizer {
    NSOperationQueue *mainQueue = [NSOperationQueue mainQueue];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationUserDidTakeScreenshotNotification
                                                      object:nil
                                                       queue:mainQueue
                                                  usingBlock:^(NSNotification *note) {
                                                    [Gleap startFeedbackFlow];
                                                  }];
}

- (void)initializeGestureRecognizer {
    UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget: self action: @selector(handleTapGestureActivation:)];
    tapGestureRecognizer.numberOfTapsRequired = 2;
    tapGestureRecognizer.numberOfTouchesRequired = 3;
    tapGestureRecognizer.cancelsTouchesInView = false;
    
    [[[[UIApplication sharedApplication] delegate] window] addGestureRecognizer: tapGestureRecognizer];
}

- (void)handleTapGestureActivation: (UITapGestureRecognizer *)recognizer
{
    [Gleap startFeedbackFlow];
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

/*
 Starts the bug reporting flow, when a SDK key has been assigned.
 */
+ (void)startFeedbackFlow {
    UIImage * screenshot = [Gleap.sharedInstance captureScreen];
    [self startFeedbackFlowWithScreenshot: screenshot];
}

/*
 Starts a silent bug reporting flow, when a SDK key has been assigned.
 */
+ (void)sendSilentBugReportWith:(NSString *)email andDescription:(NSString *)description andPriority:(GleapBugPriority)priority {
    NSMutableDictionary *dataToAppend = [[NSMutableDictionary alloc] init];
    
    NSString *bugReportPriority = @"LOW";
    if (priority == MEDIUM) {
        bugReportPriority = @"MEDIUM";
    }
    if (priority == HIGH) {
        bugReportPriority = @"HIGH";
    }
    
    [dataToAppend setValue: email forKey: @"reportedBy"];
    [dataToAppend setValue: description forKey: @"description"];
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
        NSLog(@"WARN: Gleap session not ready.");
        return;
    }
    
    if (Gleap.sharedInstance.currentlyOpened) {
        NSLog(@"WARN: Gleap is already opened.");
        return;
    }
    
    if (Gleap.sharedInstance.token.length == 0) {
        NSLog(@"WARN: Please provide a valid Gleap project TOKEN!");
        return;
    }
    
    Gleap.sharedInstance.currentlyOpened = YES;
    
    if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(bugWillBeSent)]) {
        [Gleap.sharedInstance.delegate bugWillBeSent];
    }
    
    // Update last screen name
    [Gleap.sharedInstance updateLastScreenName];
    
    // Stop replays
    [[GleapReplayHelper sharedInstance] stop];
    [Gleap attachScreenshot: screenshot];
    
    if (ui) {
        // UI flow
        UIStoryboard* storyboard = [UIStoryboard storyboardWithName: @"GleapStoryboard" bundle: [Gleap frameworkBundle]];
        GleapWidgetViewController *bugBattleWidget = [storyboard instantiateViewControllerWithIdentifier: @"GleapWidgetViewController"];
        [bugBattleWidget setScreenshot: screenshot];
        
        UINavigationController * navController = [[UINavigationController alloc] initWithRootViewController: bugBattleWidget];
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
        // No UI flow
        [Gleap.sharedInstance sendReport:^(bool success) {
            if (success) {
                if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(bugSent)]) {
                    [Gleap.sharedInstance.delegate bugSent];
                }
            } else {
                if (Gleap.sharedInstance.delegate && [Gleap.sharedInstance.delegate respondsToSelector: @selector(bugSendingFailed)]) {
                    [Gleap.sharedInstance.delegate bugSendingFailed];
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
    if (self.replaysEnabled) {
        [[Gleap sharedInstance] uploadStepImages: [GleapReplayHelper sharedInstance].replaySteps andCompletion:^(bool success, NSArray * _Nonnull fileUrls) {
            if (success) {
                // Attach replay
                [Gleap attachData: @{ @"replay": @{
                                                  @"interval": @1000,
                                                  @"frames": fileUrls
                } }];
            }
            
            [self uploadScreenshotAndSendBugReport:^(bool success) {
                completion(success);
            }];
        }];
    } else {
        [self uploadScreenshotAndSendBugReport:^(bool success) {
            completion(success);
        }];
    }
}

- (void)updateLastScreenName {
    _lastScreenName = [self getTopMostViewControllerName];
}

- (void)uploadScreenshotAndSendBugReport: (void (^)(bool success))completion {
    // Process with image upload
    [self uploadImage: self.screenshot andCompletion:^(bool success, NSString *fileUrl) {
        if (!success) {
            return completion(false);
        }
        
        // Set screenshot url.
        NSMutableDictionary *dataToAppend = [[NSMutableDictionary alloc] init];
        [dataToAppend setValue: fileUrl forKey: @"screenshotUrl"];
        [Gleap attachData: dataToAppend];
        
        // Fetch additional metadata.
        [Gleap attachData: @{ @"metaData": [self getMetaData] }];
        
        // Attach console log.
        [Gleap attachData: @{ @"consoleLog": self->_consoleLog }];
        
        // Attach steps to reproduce.
        [Gleap attachData: @{ @"actionLog": self->_stepsToReproduce }];
        
        // Attach custom data.
        [Gleap attachData: @{ @"customData": [self customData] }];
        
        // Attach custom event log.
        [Gleap attachData: @{ @"customEventLog": [[GleapLogHelper sharedInstance] getLogs] }];
        
        // Attach custom data.
        if ([[[GleapHttpTrafficRecorder sharedRecorder] networkLogs] count] > 0) {
            [Gleap attachData: @{ @"networkLogs": [[GleapHttpTrafficRecorder sharedRecorder] networkLogs] }];
        }
        
        // Sending report to server.
        [self sendReportToServer:^(bool success) {
            completion(success);
        }];
    }];
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
 Upload files
 */
- (void)uploadStepImages: (NSArray *)steps andCompletion: (void (^)(bool success, NSArray *fileUrls))completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableURLRequest *request = [NSMutableURLRequest new];
        [request setURL: [NSURL URLWithString: [NSString stringWithFormat: @"%@/uploads/sdksteps", self->_apiUrl]]];
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
            if (imageData) {
                NSString *contentType = @"image/jpeg";
                [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
                [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=%@; filename=%@\r\n", @"file", filename] dataUsingEncoding:NSUTF8StringEncoding]];
                [body appendData:[[NSString stringWithFormat: @"Content-Type: %@\r\n\r\n", contentType] dataUsingEncoding:NSUTF8StringEncoding]];
                [body appendData: imageData];
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
                NSMutableArray *replayArray = [[NSMutableArray alloc] init];
                
                for (int i = 0; i < steps.count; i++) {
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
    NSString *applicationType = @"Native";
    if (self.applicationType == FLUTTER) {
        applicationType = @"Flutter";
    } else if (self.applicationType == REACTNATIVE) {
        applicationType = @"ReactNative";
    }
    return applicationType;
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
        @"applicationType": [self getApplicationTypeAsString],
        @"lastScreenName": _lastScreenName,
        @"preferredUserLocale": preferredUserLocale
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
    if (isatty(STDERR_FILENO)) {
        NSLog(@"[Gleap] Console logs are captured only when the debugger is not attached.");
        return;
    }
    
    _inputPipe = [[NSPipe alloc] init];
    
    dup2([[_inputPipe fileHandleForWriting] fileDescriptor], STDERR_FILENO);
    
    [NSNotificationCenter.defaultCenter addObserver: self selector: @selector(receiveLogNotification:)  name: NSFileHandleReadCompletionNotification object: _inputPipe.fileHandleForReading];
    
    [_inputPipe.fileHandleForReading readInBackgroundAndNotify];
}

/*
 This callback receives all console output notifications and saves them for further use.
 */
- (void)receiveLogNotification:(NSNotification *) notification
{
    [_inputPipe.fileHandleForReading readInBackgroundAndNotify];
    NSData *data = notification.userInfo[NSFileHandleNotificationDataItem];
    
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
                if (_consoleLog.count > 1000) {
                    [_consoleLog removeObjectAtIndex: 0];
                }
                [_consoleLog addObject: log];
            }
        }
    }
}

@end
