//
//  GleapSessionHelper.m
//  Gleap
//
//  Created by Lukas Boehler on 23.09.21.
//

#import "GleapSessionHelper.h"
#import "GleapInternal.h"
#import "GleapAPIClient.h"
#import "GleapCore.h"
#import "GleapWidgetManager.h"
#import "GleapUIOverlayHelper.h"
#import "GleapCore.h"
#import "GleapEventLogHelper.h"
#import "GleapTranslationHelper.h"
#import "GleapMetaDataHelper.h"
#import "GleapWebViewSupport.h"

// The file access token is renewed this long before it expires (it lives 15 minutes).
static NSTimeInterval const kGleapFileAccessRenewBefore = 5 * 60;
// Returning to the foreground renews at most this often.
static NSTimeInterval const kGleapFileAccessForegroundInterval = 60;

@interface GleapSessionHelper ()
@property (atomic, assign) BOOL identifyInFlight;
// Bumped by clearSession: an identify answer from before a logout must not restore that user.
@property (nonatomic, assign) NSUInteger sessionEpoch;
// Bumped on each new session and on logout: only the latest scheduled renewal runs.
@property (nonatomic, assign) NSUInteger fileAccessRenewal;
@property (nonatomic, retain, nullable) NSDate *lastForegroundRenewal;
@end

@implementation GleapSessionHelper

// The session and the pending identify, update and push actions are set from whatever thread
// the app (or a wrapper) calls on and read from the main queue; every access holds this
// object's lock, and an action is taken and cleared in one step, so it runs once.
@synthesize currentSession = _currentSession;

- (GleapSession *)currentSession {
    @synchronized (self) {
        return _currentSession;
    }
}

- (void)setCurrentSession:(GleapSession *)currentSession {
    BOOL userChanged = NO;
    @synchronized (self) {
        NSString *previousId = _currentSession.gleapId;
        userChanged = previousId != nil && ![previousId isEqualToString: currentSession.gleapId ?: @""];
        _currentSession = currentSession;
    }
    if (userChanged) {
        // The web views share their localStorage (form drafts, survey answers) while the app
        // runs: never with the next user.
        [GleapWebViewSupport resetSharedDataStore];
    }
}

/*
 Returns the current device type based on the device idiom.
 */
+ (NSString *)getDeviceType
{
    UIUserInterfaceIdiom idiom = [[UIDevice currentDevice] userInterfaceIdiom];
    if (idiom == UIUserInterfaceIdiomPad) {
        return @"tablet";
    }
    if (idiom == UIUserInterfaceIdiomMac) {
        return @"desktop";
    }
    return @"mobile";
}

/*
 Returns a shared instance (singleton).
 */
+ (instancetype)sharedInstance
{
    static GleapSessionHelper *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GleapSessionHelper alloc] init];
    });
    return sharedInstance;
}

+ (void)injectSessionInRequest:(NSMutableURLRequest *)request {
    GleapSession *session = GleapSessionHelper.sharedInstance.currentSession;
    if (session != nil && session.gleapId != nil) {
        [request setValue: session.gleapId forHTTPHeaderField: @"Gleap-Id"];
    }
    if (session != nil && session.gleapHash != nil) {
        [request setValue: session.gleapHash forHTTPHeaderField: @"Gleap-Hash"];
    }
    [request setValue: Gleap.sharedInstance.token forHTTPHeaderField: @"Api-Token"];
}

/*
 The session in a server answer, or nil. Only a 2xx that names the session (gleapId and gleapHash)
 may replace the stored identity: overload (503) and error answers arrive as JSON too, and taking
 them for a session erased the stored identity.
 */
+ (nullable NSDictionary *)sessionDataInResponse:(NSURLResponse *)response data:(NSData *)data {
    if (![GleapAPIClient isSuccessResponse: response] || data == nil) {
        return nil;
    }
    id json = [NSJSONSerialization JSONObjectWithData: data options: 0 error: nil];
    if (![json isKindOfClass: [NSDictionary class]] || [json objectForKey: @"error"] != nil || [json objectForKey: @"errors"] != nil) {
        return nil;
    }
    id gleapId = [json objectForKey: @"gleapId"];
    id gleapHash = [json objectForKey: @"gleapHash"];
    if (![gleapId isKindOfClass: [NSString class]] || [gleapId length] == 0 || ![gleapHash isKindOfClass: [NSString class]] || [gleapHash length] == 0) {
        return nil;
    }
    return json;
}

/*
 YES when the server refused the request itself: a 4xx answer with an explicit error (an `error` or
 `errors` body). Server failures (5xx), timeouts (408) and rate limits (429) are not refusals.
 */
+ (BOOL)isErrorAnswerInResponse:(NSURLResponse *)response data:(NSData *)data {
    NSInteger status = [GleapAPIClient statusCodeOfResponse: response];
    if (status < 400 || status >= 500 || status == 408 || status == 429 || data == nil) {
        return NO;
    }
    id json = [NSJSONSerialization JSONObjectWithData: data options: 0 error: nil];
    return [json isKindOfClass: [NSDictionary class]] && ([json objectForKey: @"error"] != nil || [json objectForKey: @"errors"] != nil);
}

- (id)init {
    self = [super init];
    if (self) {
        // Timers do not run while the app is suspended; renew an expired file access on return.
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(applicationDidBecomeActive)
                                                     name: UIApplicationDidBecomeActiveNotification
                                                   object: nil];
    }
    return self;
}

- (void)startSessionWith:(void (^)(bool success))completion {
    // A stored guest identity is merged into the new session.
    NSMutableURLRequest *request = [GleapAPIClient JSONRequestWithMethod: @"POST" path: @"/sessions" identity: GleapRequestIdentityStoredIfComplete];
    
    NSString *lang = [GleapTranslationHelper sharedInstance].language;
    if (lang != nil) {
        NSError *error;
        NSData *jsonBodyData = [NSJSONSerialization dataWithJSONObject: @{
            @"lang": lang,
            @"platform": @"iOS",
            @"deviceType": [GleapSessionHelper getDeviceType],
        } options:kNilOptions error: &error];
        if (error == nil) {
            [request setHTTPBody: jsonBodyData];
        }
    }
    
    [GleapAPIClient sendRequest: request completion:^(NSData * _Nullable data,
                                                      NSURLResponse * _Nullable response,
                                                      NSError * _Nullable error) {
        // A failed start leaves the stored identity for the next attempt.
        NSDictionary *sessionData = error == nil ? [GleapSessionHelper sessionDataInResponse: response data: data] : nil;
        if (sessionData == nil) {
            return completion(false);
        }
        
        [Gleap logEvent: @"sessionStarted"];
        [[GleapEventLogHelper sharedInstance] stop];
        [[GleapEventLogHelper sharedInstance] start];
    
        [self updateLocalSessionWith: sessionData andCompletion: completion];
        [self refreshFileAccessIfNeeded];
    }];
}

- (void)identifySessionWith:(NSString *)userId andData:(nullable GleapUserProperty *)data andUserHash:(NSString * _Nullable)userHash {
    if (userId == nil) {
        NSLog(@"[GLEAP_SDK] identify needs a user id.");
        return;
    }
    // The user data is optional; without it only the user id is sent.
    @synchronized (self) {
        self.openIdentityAction = @{
            @"userId": userId,
            @"userHash": GleapObjectOrNull(userHash),
            @"data": data ?: [[GleapUserProperty alloc] init]
        };
        self.lastIdentifyAction = self.openIdentityAction;
    }
    [self processOpenIdentityAction];
    [self processOpenPushAction];
}

- (void)updateContact:(nullable GleapUserProperty *)data {
    @synchronized (self) {
        self.openUpdateAction = @{
            @"data": data ?: [[GleapUserProperty alloc] init],
        };
    }
    
    [self processOpenUpdateAction];
}

+ (void)handlePushNotification:(NSDictionary *)notificationData {
    GleapSessionHelper *helper = [GleapSessionHelper sharedInstance];
    @synchronized (helper) {
        helper.openPushAction = notificationData;
    }
    [helper processOpenPushAction];
}

- (void)processOpenPushAction {
    NSDictionary *pushAction;
    @synchronized (self) {
        if (self.openPushAction == nil || self.currentSession == nil) {
            return;
        }
        pushAction = self.openPushAction;
        self.openPushAction = nil;
    }
    
    NSString *type = [pushAction objectForKey: @"type"];
    NSString *itemId = [pushAction objectForKey: @"id"];
    
    if (itemId != nil && itemId.length > 0) {
        if ([type isEqualToString: @"news"]) {
            [Gleap openNewsArticle: itemId];
        } else if ([type isEqualToString: @"checklist"]) {
            [Gleap openChecklist: itemId];
        } else if ([type isEqualToString: @"conversation"]) {
            [Gleap openConversation: itemId];
        }
    }
    return;
}

- (void)processOpenUpdateAction {
    GleapUserProperty *data;
    @synchronized (self) {
        if (self.openUpdateAction == nil || self.currentSession == nil || self.openIdentityAction != nil) {
            return;
        }
        
        NSString *gleapId = [[NSUserDefaults standardUserDefaults] stringForKey:@"gleapId"];
        NSString *gleapHash = [[NSUserDefaults standardUserDefaults] stringForKey:@"gleapHash"];
        if (gleapId == nil || gleapHash == nil || gleapId.length == 0 || gleapHash.length == 0) {
            return;
        }
        data = [self.openUpdateAction objectForKey: @"data"];
        self.openUpdateAction = nil;
    }
    
    NSMutableDictionary *dataToSend = [[data dataDictToSendWith: nil and: nil] mutableCopy];
    
    // Add platform and deviceType to data
    [dataToSend setValue: @"iOS" forKey: @"platform"];
    [dataToSend setValue: [GleapSessionHelper getDeviceType] forKey: @"deviceType"];
    
    // If update is needed, also append all the custom data fields.
    @try {
        NSError *error;
        
        NSData *jsonBodyData = [NSJSONSerialization dataWithJSONObject: @{
            @"data": dataToSend,
            @"ws": @(YES),
            @"type": @"ios",
            @"sdkVersion": SDK_VERSION,
        } options:kNilOptions error: &error];
        
        // Check for parsing error.
        if (error != nil) {
            return;
        }
        
        NSMutableURLRequest *request = [GleapAPIClient JSONRequestWithMethod: @"POST" path: @"/sessions/partialupdate" identity: GleapRequestIdentityStored];
        [request setHTTPBody: jsonBodyData];
        
        [GleapAPIClient sendRequest: request completion:^(NSData * _Nullable data,
                                                          NSURLResponse * _Nullable response,
                                                          NSError * _Nullable error) {
            // A failed update leaves the session as it is.
            NSDictionary *sessionData = error == nil ? [GleapSessionHelper sessionDataInResponse: response data: data] : nil;
            if (sessionData != nil) {
                [self updateLocalSessionWith: sessionData andCompletion:^(bool success) {}];
                [self refreshFileAccessIfNeeded];
            }
        }];
    } @catch (id exp) {}
}

- (void)processOpenIdentityAction {
    NSDictionary *identityAction;
    NSUInteger epoch;
    @synchronized (self) {
        if (self.openIdentityAction == nil || self.currentSession == nil) {
            return;
        }
        identityAction = self.openIdentityAction;
        self.openIdentityAction = nil;
        epoch = self.sessionEpoch;
    }
    
    NSString *userId = [identityAction objectForKey: @"userId"];
    id userHash = [identityAction objectForKey: @"userHash"];
    GleapUserProperty *data = [identityAction objectForKey: @"data"];
    
    NSDictionary *sessionRequestData = [data dataDictToSendWith: userId and: userHash];
    
    // Used to check for update.
    NSMutableDictionary *sessionDataToCheckForUpdate = [sessionRequestData mutableCopy];
    if (data != nil && data.customData != nil) {
        [sessionDataToCheckForUpdate setValue: data.customData forKey: @"customData"];
    }
    
    bool needsUpdate = [self sessionUpgradeWithDataNeeded: sessionDataToCheckForUpdate];
    // Only a verified identify issues the file access token, so it is sent even when nothing changed.
    GleapSession *session = self.currentSession;
    BOOL needsFileAccess = [userHash isKindOfClass: [NSString class]] && [userHash length] > 0 && session.authenticatedFilesRequired &&
        ([[identityAction objectForKey: @"renewFileAccess"] boolValue] || ![session hasFileAccess]);
    if (!needsUpdate && !needsFileAccess) {
        return;
    }
    
    // If update is needed, also append all the custom data fields.
    @try {
        if (data != nil && data.customData != nil) {
            NSArray *keys = data.customData.allKeys;
            for (NSUInteger i = 0; i < keys.count; i++) {
                NSString *key = [keys objectAtIndex: i];
                [sessionRequestData setValue: [data.customData objectForKey: key] forKey: key];
            }
        }
        
        // Add platform and deviceType
        [sessionRequestData setValue: @"iOS" forKey: @"platform"];
        [sessionRequestData setValue: [GleapSessionHelper getDeviceType] forKey: @"deviceType"];
    } @catch (id exp) {}
    
    NSError *error;
    NSData *jsonBodyData = [NSJSONSerialization dataWithJSONObject: sessionRequestData options:kNilOptions error: &error];
    
    // Check for parsing error.
    if (error != nil) {
        return;
    }
    
    // The stored guest identity is merged into the identified session.
    NSMutableURLRequest *request = [GleapAPIClient JSONRequestWithMethod: @"POST" path: @"/sessions/identify" identity: GleapRequestIdentityStored];
    [request setHTTPBody: jsonBodyData];
    
    self.identifyInFlight = YES;
    [GleapAPIClient sendRequest: request completion:^(NSData * _Nullable data,
                                                      NSURLResponse * _Nullable response,
                                                      NSError * _Nullable error) {
        self.identifyInFlight = NO;
        @synchronized (self) {
            // The user logged out while this identify was on its way.
            if (epoch != self.sessionEpoch) {
                return;
            }
        }
        if (error != nil) {
            return;
        }
        
        NSDictionary *sessionData = [GleapSessionHelper sessionDataInResponse: response data: data];
        if (sessionData != nil) {
            // Send unregister of previous group.
            if (![[sessionData objectForKey: @"gleapHash"] isEqual: self.currentSession.gleapHash]) {
                [self sendPushMessageUnregister];
            }
            
            [self updateLocalSessionWith: sessionData andCompletion:^(bool success) {}];
            
            // Restart logger, unless this identify only renewed the file access.
            if (needsUpdate) {
                [Gleap logEvent: @"sessionStarted"];
                [[GleapEventLogHelper sharedInstance] stop];
                [[GleapEventLogHelper sharedInstance] start];
            }
        } else if ([GleapSessionHelper isErrorAnswerInResponse: response data: data]) {
            // The server refused this identity (for example a wrong user hash): start over as a guest.
            [self clearSession];
        }
        // Anything else (overloaded, a server failure, an answer without a session) keeps the identity.
    }];
}

- (BOOL)isCustomData:(NSDictionary *)customDataSubset aSubsetOf:(NSDictionary *)customData {
    for (NSString *key in customDataSubset) {
        if (![customData objectForKey:key] || ![customData[key] isEqual:customDataSubset[key]]) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)sessionUpgradeWithDataNeeded:(NSDictionary *)newData {
    if (self.currentSession == nil) {
        return YES;
    }
    
    if ([self sessionDataItemNeedsUpgrade: self.currentSession.lang compareTo: [newData objectForKey: @"lang"]]) {
        return YES;
    }
    
    if ([self sessionDataItemNeedsUpgrade: self.currentSession.name compareTo: [newData objectForKey: @"name"]]) {
        return YES;
    }
    
    if ([self sessionDataItemNeedsUpgrade: self.currentSession.email compareTo: [newData objectForKey: @"email"]]) {
        return YES;
    }
    
    if ([self sessionDataItemNeedsUpgrade: self.currentSession.phone compareTo: [newData objectForKey: @"phone"]]) {
        return YES;
    }
    
    if ([self sessionDataItemNeedsUpgrade: self.currentSession.plan compareTo: [newData objectForKey: @"plan"]]) {
        return YES;
    }
    
    if ([self sessionDataItemNeedsUpgrade: self.currentSession.companyName compareTo: [newData objectForKey: @"companyName"]]) {
        return YES;
    }
    
    if ([self sessionDataItemNeedsUpgrade: self.currentSession.avatar compareTo: [newData objectForKey: @"avatar"]]) {
        return YES;
    }
    
    if ([self sessionDataItemNeedsUpgrade: self.currentSession.companyId compareTo: [newData objectForKey: @"companyId"]]) {
        return YES;
    }
    
    if ([self sessionDataItemNeedsUpgrade: self.currentSession.userId compareTo: [newData objectForKey: @"userId"]]) {
        return YES;
    }
    
    if ([self sessionDataNumberItemNeedsUpgrade: self.currentSession.sla compareTo: [newData objectForKey: @"sla"]]) {
        return YES;
    }
    
    if ([self sessionDataNumberItemNeedsUpgrade: self.currentSession.value compareTo: [newData objectForKey: @"value"]]) {
        return YES;
    }
    
    if ([self sessionCustomDataItemNeedsUpgrade: self.currentSession.customData compareTo: [newData objectForKey: @"customData"]]) {
        return YES;
    }
    
    return NO;
}

- (void)updateLocalSessionWith:(NSDictionary *)data andCompletion:(void (^)(bool success))completion {
    if (data == nil) {
        return completion(false);
    }
    
    // Save session data from server.
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setValue: [data objectForKey: @"gleapId"] forKey: @"gleapId"];
    [userDefaults setValue: [data objectForKey: @"gleapHash"] forKey: @"gleapHash"];
    
    // Create session and assign it.
    GleapSession *gleapSession = [[GleapSession alloc] init];
    @try {
        gleapSession.gleapId = [data objectForKey: @"gleapId"];
        gleapSession.gleapHash = [data objectForKey: @"gleapHash"];
        gleapSession.userId = [data objectForKey: @"userId"];
    } @catch (id exp) {
        
    }
    
    @try {
        gleapSession.email = [data objectForKey: @"email"];
        gleapSession.phone = [data objectForKey: @"phone"];
        gleapSession.name = [data objectForKey: @"name"];
        gleapSession.value = [data objectForKey: @"value"];
        gleapSession.lang = [data objectForKey: @"lang"];
        gleapSession.companyId = [data objectForKey: @"companyId"];
        gleapSession.companyName = [data objectForKey: @"companyName"];
        gleapSession.avatar = [data objectForKey: @"avatar"];
        gleapSession.sla = [data objectForKey: @"sla"];
        gleapSession.plan = [data objectForKey: @"plan"];
    } @catch (id exp) {
        
    }
    
    @try {
        gleapSession.customData = [data objectForKey: @"customData"];
    } @catch (id exp) {
        
    }
    
    [self applyFileAccessFrom: data to: gleapSession previous: self.currentSession];
    
    // Update local session.
    self.currentSession = gleapSession;
    [self scheduleFileAccessRenewal];
    
    // Process any open identity actions.
    [self processOpenIdentityAction];
    [self processOpenPushAction];
    [self processOpenUpdateAction];
    
    // Only send update when session changed.
    if (self.currentSession != nil && self.currentSession.gleapHash != nil && self.currentSession.gleapHash.length > 0 && [Gleap sharedInstance].delegate != nil && [Gleap.sharedInstance.delegate respondsToSelector: @selector(registerPushMessageGroup:)]) {
        if (self.lastRegisterGleapHash == nil || ![self.lastRegisterGleapHash isEqualToString: self.currentSession.gleapHash]) {
            [[Gleap sharedInstance].delegate registerPushMessageGroup: [NSString stringWithFormat: @"gleapuser-%@", self.currentSession.gleapHash]];
            self.lastRegisterGleapHash = self.currentSession.gleapHash;
        }
    }
    
    // Update widget session
    [[GleapWidgetManager sharedInstance] sendSessionUpdate];
    
    [self processPendingProtectedFile];
    
    return completion(true);
}

- (void)sendPushMessageUnregister {
    if (self.currentSession != nil && self.currentSession.gleapHash != nil && self.currentSession.gleapHash.length > 0 && [Gleap sharedInstance].delegate != nil && [Gleap.sharedInstance.delegate respondsToSelector: @selector(unregisterPushMessageGroup:)]) {
        [[Gleap sharedInstance].delegate unregisterPushMessageGroup: [NSString stringWithFormat: @"gleapuser-%@", self.currentSession.gleapHash]];
        self.lastRegisterGleapHash = nil;
    }
}

- (void)clearSession {
    [self sendPushMessageUnregister];
    [self revokeFileAccess: self.currentSession.fileAccessToken];
    
    @synchronized (self) {
        self.currentSession = nil;
        self.openIdentityAction = nil;
        self.lastIdentifyAction = nil;
        self.pendingProtectedFileId = nil;
        self.sessionEpoch++;
        self.fileAccessRenewal++;
    }
    [[NSUserDefaults standardUserDefaults] removeObjectForKey: @"gleapId"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey: @"gleapHash"];
    
    // Update widget session
    [[GleapWidgetManager sharedInstance] sendSessionUpdate];
    [GleapUIOverlayHelper clear];
    
    // Restart a session.
    [self startSessionWith:^(bool success) {}];
}

#pragma mark - Protected files

/*
 Takes the file access from a session answer. Only identify issues a token; an answer without one
 (session start, partial update) keeps the current token while it is the same session and user.
 */
- (void)applyFileAccessFrom:(NSDictionary *)data to:(GleapSession *)session previous:(nullable GleapSession *)previous {
    id required = [data objectForKey: @"authenticatedFilesRequired"];
    session.authenticatedFilesRequired = [required isKindOfClass: [NSNumber class]] && [required boolValue];
    
    id token = [data objectForKey: @"fileAccessToken"];
    id expiresAt = [data objectForKey: @"fileAccessExpiresAt"];
    if ([token isKindOfClass: [NSString class]] && [token length] > 0 && [expiresAt isKindOfClass: [NSString class]]) {
        session.fileAccessToken = token;
        session.fileAccessExpiresAt = [GleapSessionHelper dateFromISOString: expiresAt];
        return;
    }
    
    if (previous != nil && [previous hasFileAccess] && [previous.gleapId isEqual: session.gleapId] &&
        (previous.userId == session.userId || [previous.userId isEqual: session.userId])) {
        session.fileAccessToken = previous.fileAccessToken;
        session.fileAccessExpiresAt = previous.fileAccessExpiresAt;
    }
}

+ (nullable NSDate *)dateFromISOString:(NSString *)value {
    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    NSDate *date = [formatter dateFromString: value];
    if (date == nil) {
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
        date = [formatter dateFromString: value];
    }
    return date;
}

- (void)applicationDidBecomeActive {
    @synchronized (self) {
        if (self.lastForegroundRenewal != nil && [[NSDate date] timeIntervalSinceDate: self.lastForegroundRenewal] < kGleapFileAccessForegroundInterval) {
            return;
        }
    }
    if ([self refreshFileAccessIfNeeded]) {
        @synchronized (self) {
            self.lastForegroundRenewal = [NSDate date];
        }
    }
}

/*
 Replays the app's last verified identify when the project requires file access and the token is
 missing or about to expire.
 */
- (BOOL)refreshFileAccessIfNeeded {
    GleapSession *session = self.currentSession;
    NSDictionary *identify;
    @synchronized (self) {
        identify = self.lastIdentifyAction;
        if (session == nil || !session.authenticatedFilesRequired || identify == nil || self.openIdentityAction != nil || self.identifyInFlight) {
            return NO;
        }
    }
    id userHash = [identify objectForKey: @"userHash"];
    if (![userHash isKindOfClass: [NSString class]] || [userHash length] == 0) {
        return NO;
    }
    if ([session hasFileAccess] && [session.fileAccessExpiresAt timeIntervalSinceNow] > kGleapFileAccessRenewBefore) {
        return NO;
    }
    [self renewFileAccessWith: identify];
    return YES;
}

- (void)renewFileAccessWith:(NSDictionary *)identify {
    @synchronized (self) {
        if (self.openIdentityAction != nil) {
            return;
        }
        NSMutableDictionary *action = [identify mutableCopy];
        [action setObject: @(YES) forKey: @"renewFileAccess"];
        self.openIdentityAction = action;
    }
    [self processOpenIdentityAction];
}

- (void)scheduleFileAccessRenewal {
    GleapSession *session = self.currentSession;
    NSUInteger renewal;
    @synchronized (self) {
        renewal = ++self.fileAccessRenewal;
    }
    if (![session hasFileAccess]) {
        return;
    }
    NSTimeInterval delay = MAX(0, [session.fileAccessExpiresAt timeIntervalSinceNow] - kGleapFileAccessRenewBefore);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSDictionary *identify;
        @synchronized (self) {
            if (renewal != self.fileAccessRenewal) {
                return;
            }
            identify = self.lastIdentifyAction;
        }
        id userHash = [identify objectForKey: @"userHash"];
        if ([userHash isKindOfClass: [NSString class]] && [userHash length] > 0 && !self.identifyInFlight) {
            [self renewFileAccessWith: identify];
        }
    });
}

- (void)revokeFileAccess:(nullable NSString *)token {
    if (token.length == 0) {
        return;
    }
    // Best effort: offline the token still expires within 15 minutes.
    NSMutableURLRequest *request = [GleapAPIClient requestWithMethod: @"POST" path: @"/files/session/revoke" identity: GleapRequestIdentityNone];
    [request setValue: token forHTTPHeaderField: @"X-File-Session"];
    [GleapAPIClient sendRequest: request completion:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {}];
}

- (BOOL)openProtectedFileFromURL:(NSURL *)url {
    NSString *fileId = nil;
    for (NSURLQueryItem *item in [NSURLComponents componentsWithURL: url resolvingAgainstBaseURL: NO].queryItems) {
        if ([item.name isEqualToString: @"gleapFile"]) {
            fileId = item.value;
        }
    }
    if (fileId == nil || [fileId rangeOfString: @"^[a-f0-9]{24}$" options: NSRegularExpressionSearch].location == NSNotFound) {
        return NO;
    }
    @synchronized (self) {
        self.pendingProtectedFileId = fileId;
    }
    [self processPendingProtectedFile];
    return YES;
}

/*
 Asks the API which conversation holds the requested file and opens it. Waits until a verified
 identify gave the session file access; the file id alone grants nothing.
 */
- (void)processPendingProtectedFile {
    GleapSession *session = self.currentSession;
    NSString *fileId;
    @synchronized (self) {
        if (self.pendingProtectedFileId == nil || ![session hasFileAccess]) {
            return;
        }
        fileId = self.pendingProtectedFileId;
        self.pendingProtectedFileId = nil;
    }
    NSString *token = session.fileAccessToken;
    NSMutableURLRequest *request = [GleapAPIClient requestWithMethod: @"GET" path: [NSString stringWithFormat: @"/files/%@/location", fileId] identity: GleapRequestIdentityNone];
    [request setValue: token forHTTPHeaderField: @"X-File-Session"];
    [GleapAPIClient sendRequest: request completion:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error != nil || ![GleapAPIClient isSuccessResponse: response] || data == nil || ![self.currentSession.fileAccessToken isEqualToString: token]) {
            return;
        }
        id json = [NSJSONSerialization JSONObjectWithData: data options: 0 error: nil];
        id shareToken = [json isKindOfClass: [NSDictionary class]] ? [json objectForKey: @"shareToken"] : nil;
        if ([shareToken isKindOfClass: [NSString class]] && [shareToken length] > 0) {
            [Gleap openConversation: shareToken];
        }
    }];
}

- (BOOL)sessionCustomDataItemNeedsUpgrade:(NSDictionary *)data compareTo:(NSDictionary *)newData {
    if ([data isKindOfClass:[NSNull class]] || [newData isKindOfClass:[NSNull class]]) {
        return YES;
    }
    
    // Both values are nil, no upgrade needed.
    if (data == nil && newData == nil) {
        return NO;
    }
    
    // One value is nil, upgrade needed.
    if (data == nil || newData == nil) {
        return YES;
    }
    
    return ![self isCustomData: newData aSubsetOf: data];
}

- (BOOL)sessionDataItemNeedsUpgrade:(NSString *)data compareTo:(NSString *)newData {
    if ([data isKindOfClass:[NSNull class]] || [newData isKindOfClass:[NSNull class]]) {
        return YES;
    }
    
    // Both values are nil, no upgrade needed.
    if (data == nil && newData == nil) {
        return NO;
    }
    
    // One value is nil, upgrade needed.
    if (data == nil || newData == nil) {
        return YES;
    }
    
    return ![data isEqualToString: newData];
}

- (BOOL)sessionDataNumberItemNeedsUpgrade:(NSNumber *)data compareTo:(NSNumber *)newData {
    if ([data isKindOfClass:[NSNull class]] || [newData isKindOfClass:[NSNull class]]) {
        return YES;
    }
    
    // Both values are nil, no upgrade needed.
    if (data == nil && newData == nil) {
        return NO;
    }
    
    // Both values are nil, no upgrade needed.
    if (data.intValue == 0 && newData == nil) {
        return NO;
    }
    
    // One value is nil, upgrade needed.
    if (data == nil || newData == nil) {
        return YES;
    }
    
    return ![data isEqualToNumber: newData];
}

- (NSString *)getSessionName {
    if (self.currentSession == nil) {
        return @"";
    }
    
    if (self.currentSession.name == nil) {
        return @"";
    }
    
    NSArray *nameParts = [self.currentSession.name componentsSeparatedByString: @"@"];
    nameParts = [[nameParts objectAtIndex: 0] componentsSeparatedByString: @"."];
    nameParts = [[nameParts objectAtIndex: 0] componentsSeparatedByString: @"+"];
    nameParts = [[nameParts objectAtIndex: 0] componentsSeparatedByString: @" "];
    
    return [[nameParts objectAtIndex: 0] capitalizedString];
}

@end
