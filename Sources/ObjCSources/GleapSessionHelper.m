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
#import "GleapUserJwt.h"
#import "GleapGrant.h"

// The file access token is renewed this long before it expires (it lives 15 minutes).
static NSTimeInterval const kGleapFileAccessRenewBefore = 5 * 60;
// Returning to the foreground renews at most this often.
static NSTimeInterval const kGleapFileAccessForegroundInterval = 60;
// A survey waits at most this long for an identify or contact update on its way.
static NSTimeInterval const kGleapContactSettleTimeout = 5;
// An identity token that expires within this window is renewed through the JWT provider before a replay.
static NSTimeInterval const kGleapUserJwtRefreshWindow = 5 * 60;
// The grant is renewed (the app's last signed identify replayed) this long before it expires.
static NSTimeInterval const kGleapGrantRenewBefore = 5 * 60;

@interface GleapSessionHelper ()
@property (atomic, assign) BOOL identifyInFlight;
// Bumped by clearSession: an identify answer from before a logout must not restore that user.
@property (nonatomic, assign) NSUInteger sessionEpoch;
// Bumped on each new session and on logout: only the latest scheduled renewal runs.
@property (nonatomic, assign) NSUInteger fileAccessRenewal;
@property (nonatomic, retain, nullable) NSDate *lastForegroundRenewal;
// Identify and contact update requests on their way, and what waits for their answers (main queue).
@property (nonatomic, assign) NSUInteger contactRequestsInFlight;
@property (nonatomic, strong, nullable) NSMutableArray<dispatch_block_t> *waitingForContact;
// Gleap.setUserJwtProvider: one call at a time, a pause after a failure.
@property (nonatomic, strong) GleapUserJwtProviderGate *userJwtGate;
// The identity token the server last accepted, and for which session (memory only): a new token is
// sent even when nothing else changed.
@property (nonatomic, copy, nullable) NSString *sentUserJwt; // identityFingerprintOf: the last token sent
@property (nonatomic, copy, nullable) NSString *sentUserJwtGleapId;
// Gleap.setAuthTokens (memory only): the tokens, names removed but not yet sent, and the session
// that has them all (nil while a change waits).
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *authTokens;
@property (nonatomic, strong) NSMutableSet<NSString *> *removedAuthTokens;
@property (nonatomic, copy, nullable) NSString *authTokensSentFor;
// Bumped whenever a grant is stored or dropped: only the latest scheduled renewal runs.
@property (nonatomic, assign) NSUInteger grantRenewal;
// The last grant renewal started: at most one a minute (an expired token without a provider).
@property (nonatomic, retain, nullable) NSDate *lastGrantRenewal;
// `identity.mode` of the last session answer that carried `identity` ('signed' or nil): Classic
// projects send no `identity`.
@property (nonatomic, copy, nullable) NSString *identityMode;
// The session a signed identify was sent for while it had no grant (memory only): a returning user
// on a project that switched to Signed gets one identify per app launch and session, never a loop.
@property (nonatomic, copy, nullable) NSString *signedGrantRequestedFor;
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
    // The grant of this session, when a signed identify issued one.
    [[GleapGrant sharedInstance] applyToRequest: request];
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
        _userJwtGate = [[GleapUserJwtProviderGate alloc] init];
        _authTokens = [[NSMutableDictionary alloc] init];
        _removedAuthTokens = [[NSMutableSet alloc] init];
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

- (BOOL)hasIdentifiedUser {
    NSString *identifiedUserId = self.lastIdentifyAction[@"userId"] ?: self.openIdentityAction[@"userId"];
    if ([identifiedUserId isKindOfClass: [NSString class]] && identifiedUserId.length > 0) {
        return YES;
    }
    return self.currentSession.userId != nil && self.currentSession.userId.length > 0;
}

- (void)adoptSessionWithId:(nullable NSString *)gleapId hash:(nullable NSString *)gleapHash {
    if (![gleapId isKindOfClass: [NSString class]] || gleapId.length == 0 || ![gleapHash isKindOfClass: [NSString class]] || gleapHash.length == 0) {
        return;
    }
    // The app's own identify always wins: an identified user is never swapped by the widget.
    if ([self hasIdentifiedUser]) {
        return;
    }
    if ([self.currentSession.gleapId isEqualToString: gleapId]) {
        return;
    }

    // The server answers with the handed-over session only when the hash signs that id.
    NSMutableURLRequest *request = [GleapAPIClient JSONRequestWithMethod: @"POST" path: @"/sessions" identity: GleapRequestIdentityNone];
    [request setValue: Gleap.sharedInstance.token forHTTPHeaderField: @"Api-Token"];
    [request setValue: gleapId forHTTPHeaderField: @"Gleap-Id"];
    [request setValue: gleapHash forHTTPHeaderField: @"Gleap-Hash"];

    NSString *lang = [GleapTranslationHelper sharedInstance].language;
    NSData *jsonBodyData = [NSJSONSerialization dataWithJSONObject: @{
        @"lang": lang ?: @"en",
        @"platform": @"iOS",
        @"deviceType": [GleapSessionHelper getDeviceType],
    } options: kNilOptions error: nil];
    if (jsonBodyData != nil) {
        [request setHTTPBody: jsonBodyData];
    }

    [GleapAPIClient sendRequest: request completion:^(NSData * _Nullable data,
                                                      NSURLResponse * _Nullable response,
                                                      NSError * _Nullable error) {
        NSDictionary *sessionData = error == nil ? [GleapSessionHelper sessionDataInResponse: response data: data] : nil;
        // The app may have identified its user while the request was out.
        if (sessionData == nil || ![sessionData[@"gleapId"] isEqual: gleapId] || [self hasIdentifiedUser]) {
            return;
        }
        [self updateLocalSessionWith: sessionData andCompletion:^(bool success) {}];
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

#pragma mark - Identity token

- (void)setUserJwt:(NSString *)token {
    NSString *userId = [GleapUserJwt userIdOf: token];
    if (userId == nil) {
        NSLog(@"[GLEAP_SDK] setUserJwt expects a JWT (three base64url parts, at most 4096 characters) whose payload has a userId (or user_id). Nothing was sent.");
        return;
    }
    @synchronized (self) {
        // The token is the whole identify: no contact fields are sent next to it.
        self.openIdentityAction = @{
            @"userId": userId,
            @"userHash": token,
            @"data": [[GleapUserProperty alloc] init],
            @"jwtOnly": @(YES),
        };
        self.lastIdentifyAction = self.openIdentityAction;
    }
    [self processOpenIdentityAction];
    [self processOpenPushAction];
}

- (void)setUserJwtProvider:(nullable GleapUserJwtProvider)provider {
    self.userJwtGate.provider = provider;
}

/*
 Runs `send` with the identify action, or with a copy carrying a fresh token when the action's
 identity token expires within 5 minutes and a JWT provider is set. Synchronous otherwise. A logout
 or another identify while the provider runs wins.
 */
- (void)withFreshUserJwt:(NSDictionary *)identify send:(void (^)(NSDictionary *identify))send {
    id userHash = [identify objectForKey: @"userHash"];
    if (self.userJwtGate.provider == nil || ![GleapUserJwt token: userHash expiresWithin: kGleapUserJwtRefreshWindow of: [NSDate date]]) {
        send(identify);
        return;
    }
    NSUInteger epoch;
    @synchronized (self) {
        epoch = self.sessionEpoch;
    }
    [self.userJwtGate requestToken:^(NSString * _Nullable token) {
        NSDictionary *latest;
        @synchronized (self) {
            if (epoch != self.sessionEpoch || ![[self.lastIdentifyAction objectForKey: @"userHash"] isEqual: userHash]) {
                return;
            }
            latest = self.lastIdentifyAction;
        }
        if (token == nil) {
            send(identify);
            return;
        }
        NSDictionary *fresh = [self identify: latest withUserJwt: token];
        @synchronized (self) {
            self.lastIdentifyAction = fresh;
        }
        NSMutableDictionary *action = [fresh mutableCopy];
        if ([identify objectForKey: @"renewFileAccess"] != nil) {
            [action setObject: [identify objectForKey: @"renewFileAccess"] forKey: @"renewFileAccess"];
        }
        send(action);
    }];
}

// The identify action with `token` as user hash and the token's user id.
- (NSDictionary *)identify:(NSDictionary *)identify withUserJwt:(NSString *)token {
    NSMutableDictionary *action = [identify mutableCopy];
    [action setObject: token forKey: @"userHash"];
    [action setObject: [GleapUserJwt userIdOf: token] ?: [identify objectForKey: @"userId"] forKey: @"userId"];
    [action removeObjectForKey: @"renewFileAccess"];
    [action removeObjectForKey: @"jwtRetried"];
    return action;
}

/*
 An identify refused with token_expired or token_invalid keeps the identity and the session
 (contract §3). An expired token is renewed through the provider and the identify sent once more.
 */
- (void)handleUserJwtRefusal:(NSString *)refusal forIdentify:(NSDictionary *)identityAction epoch:(NSUInteger)epoch {
    id userHash = [identityAction objectForKey: @"userHash"];
    BOOL mayRetry = [refusal isEqualToString: @"token_expired"] && self.userJwtGate.provider != nil && ![[identityAction objectForKey: @"jwtRetried"] boolValue];
    if (!mayRetry) {
        if ([refusal isEqualToString: @"token_expired"]) {
            NSLog(@"[GLEAP_SDK] The identity token has expired. Pass a fresh one to Gleap.setUserJwt, or set Gleap.setUserJwtProvider.");
        } else {
            NSLog(@"[GLEAP_SDK] The identity token was refused (token_invalid): check the signing key and the userId claim.");
        }
        return;
    }
    [self.userJwtGate requestToken:^(NSString * _Nullable token) {
        NSDictionary *retry;
        @synchronized (self) {
            if (token == nil || epoch != self.sessionEpoch || ![[self.lastIdentifyAction objectForKey: @"userHash"] isEqual: userHash]) {
                return;
            }
            NSDictionary *fresh = [self identify: self.lastIdentifyAction withUserJwt: token];
            self.lastIdentifyAction = fresh;
            NSMutableDictionary *action = [fresh mutableCopy];
            [action setObject: @(YES) forKey: @"jwtRetried"];
            if ([identityAction objectForKey: @"renewFileAccess"] != nil) {
                [action setObject: [identityAction objectForKey: @"renewFileAccess"] forKey: @"renewFileAccess"];
            }
            // A newer identify waiting to go out wins.
            if (self.openIdentityAction != nil) {
                return;
            }
            self.openIdentityAction = action;
            retry = action;
        }
        if (retry != nil) {
            [self processOpenIdentityAction];
        }
    }];
}

#pragma mark - Auth tokens

- (void)setAuthTokens:(NSDictionary<NSString *, id> *)tokens {
    if (![tokens isKindOfClass: [NSDictionary class]]) {
        NSLog(@"[GLEAP_SDK] setAuthTokens expects a dictionary of { name: token }.");
        return;
    }
    NSRegularExpression *validName = [NSRegularExpression regularExpressionWithPattern: @"^[a-zA-Z][a-zA-Z0-9_-]{0,39}$" options: 0 error: nil];
    BOOL changed = NO;
    @synchronized (self) {
        for (id name in tokens) {
            id value = [tokens objectForKey: name];
            if (![name isKindOfClass: [NSString class]] || [validName numberOfMatchesInString: name options: 0 range: NSMakeRange(0, [name length])] == 0) {
                NSLog(@"[GLEAP_SDK] Auth token name \"%@\" skipped: use a letter followed by up to 39 letters, digits, _ or -.", name);
                continue;
            }
            if (value == nil || value == [NSNull null]) {
                [self.authTokens removeObjectForKey: name];
                [self.removedAuthTokens addObject: name];
            } else if ([value isKindOfClass: [NSString class]]) {
                [self.authTokens setObject: value forKey: name];
                [self.removedAuthTokens removeObject: name];
            } else {
                NSLog(@"[GLEAP_SDK] Auth token \"%@\" skipped: the value must be a string, or NSNull to remove it.", name);
                continue;
            }
            changed = YES;
        }
        if (changed) {
            self.authTokensSentFor = nil;
        }
    }
    if (changed) {
        [self sendAuthTokensIfNeeded];
    }
}

/*
 POST /sessions/auth-tokens with every token and the names removed since the last delivery, once
 the session is there and no identify is on its way; after a signed identify the next session gets
 them again.
 */
- (void)sendAuthTokensIfNeeded {
    NSString *gleapId;
    NSMutableDictionary *body;
    NSSet *removed;
    @synchronized (self) {
        gleapId = self.currentSession.gleapId;
        if (gleapId.length == 0 || self.openIdentityAction != nil || self.identifyInFlight) {
            return;
        }
        if (self.authTokens.count == 0 && self.removedAuthTokens.count == 0) {
            return;
        }
        if ([self.authTokensSentFor isEqualToString: gleapId]) {
            return;
        }
        body = [self.authTokens mutableCopy];
        removed = [self.removedAuthTokens copy];
        for (NSString *name in removed) {
            [body setObject: [NSNull null] forKey: name];
        }
    }
    NSData *jsonBodyData = [NSJSONSerialization dataWithJSONObject: @{ @"tokens": body } options: kNilOptions error: nil];
    if (jsonBodyData == nil) {
        return;
    }
    NSMutableURLRequest *request = [GleapAPIClient JSONRequestWithMethod: @"POST" path: @"/sessions/auth-tokens" identity: GleapRequestIdentityStored];
    [request setHTTPBody: jsonBodyData];
    [GleapAPIClient sendRequest: request completion:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error != nil) {
            return;
        }
        NSInteger status = [GleapAPIClient statusCodeOfResponse: response];
        if ([GleapAPIClient isSuccessResponse: response]) {
            @synchronized (self) {
                if ([self.currentSession.gleapId isEqualToString: gleapId]) {
                    [self.removedAuthTokens minusSet: removed];
                    // A change made while this request was out is sent next.
                    BOOL unchanged = YES;
                    for (NSString *name in self.authTokens) {
                        if (![[body objectForKey: name] isEqual: [self.authTokens objectForKey: name]]) {
                            unchanged = NO;
                        }
                    }
                    if (unchanged && self.removedAuthTokens.count == 0) {
                        self.authTokensSentFor = gleapId;
                    }
                }
            }
        } else if (status == 401) {
            NSLog(@"[GLEAP_SDK] Auth tokens need a signed identity: call Gleap.setUserJwt first. They are kept and sent after the next signed identify.");
        }
    }];
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
        
        [self contactRequestStarted];
        [GleapAPIClient sendRequest: request completion:^(NSData * _Nullable data,
                                                          NSURLResponse * _Nullable response,
                                                          NSError * _Nullable error) {
            // A failed update leaves the session as it is.
            NSDictionary *sessionData = error == nil ? [GleapSessionHelper sessionDataInResponse: response data: data] : nil;
            if (sessionData != nil) {
                [self updateLocalSessionWith: sessionData andCompletion:^(bool success) {}];
                [self refreshFileAccessIfNeeded];
            }
            [self contactRequestEnded];
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
    
    GleapSession *session = self.currentSession;
    bool needsUpdate;
    if ([[identityAction objectForKey: @"jwtOnly"] boolValue]) {
        // setUserJwt sends no contact fields: only another user or language is a change.
        needsUpdate = [self sessionDataItemNeedsUpgrade: session.userId compareTo: userId] ||
            [self sessionDataItemNeedsUpgrade: session.lang compareTo: [sessionDataToCheckForUpdate objectForKey: @"lang"]];
    } else {
        needsUpdate = [self sessionUpgradeWithDataNeeded: sessionDataToCheckForUpdate];
    }
    // Only a verified identify issues the file access token, so it is sent even when nothing changed.
    BOOL needsFileAccess = [userHash isKindOfClass: [NSString class]] && [userHash length] > 0 && session.authenticatedFilesRequired &&
        ([[identityAction objectForKey: @"renewFileAccess"] boolValue] || ![session hasFileAccess]);
    // A grant about to expire is renewed by sending the verified identify again.
    BOOL needsGrant = [userHash isKindOfClass: [NSString class]] && [userHash length] > 0 && [[identityAction objectForKey: @"renewGrant"] boolValue] &&
        [[GleapGrant sharedInstance] needsRenewalForGleapId: session.gleapId within: kGleapGrantRenewBefore];
    // A new identity token is sent even when the contact data is the same.
    BOOL isUserJwt = [GleapUserJwt isUserJwt: userHash];
    BOOL needsUserJwt;
    BOOL hasHash = [userHash isKindOfClass: [NSString class]] && [userHash length] > 0;
    BOOL needsSignedGrant;
    @synchronized (self) {
        // Compared by what the token says, so a token re-minted per launch or login for the same
        // user and data is not sent again.
        needsUserJwt = isUserJwt && !([self.sentUserJwt isEqualToString: [GleapUserJwt identityFingerprintOf: userHash]] && [self.sentUserJwtGleapId isEqualToString: session.gleapId]);
        // The project switched to Signed and this identified session has no grant yet: the held
        // hash or token is sent once, even unchanged, so a returning user gets one.
        needsSignedGrant = hasHash && [self signedGrantMissingFor: session];
    }
    if (!needsUpdate && !needsFileAccess && !needsUserJwt && !needsGrant && !needsSignedGrant) {
        [self sendAuthTokensIfNeeded];
        return;
    }
    // Sent only to get the grant: a refusal keeps the session it was sent for.
    BOOL signedGrantOnly = needsSignedGrant && !needsUpdate && !needsFileAccess && !needsUserJwt && !needsGrant;
    if (hasHash) {
        @synchronized (self) {
            if ([self signedGrantMissingFor: session]) {
                self.signedGrantRequestedFor = session.gleapId;
            }
        }
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
        // Gleap.setSessionDuration: caps the grant's lifetime (milliseconds).
        NSNumber *sessionDuration = self.sessionDuration;
        if (sessionDuration != nil) {
            [sessionRequestData setValue: sessionDuration forKey: @"sessionDuration"];
        }
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
    
    // A renewal of the file access alone changes nothing a survey reads.
    if (needsUpdate) {
        [self contactRequestStarted];
    }
    GleapAPICompletion handleAnswer = ^(NSData * _Nullable data,
                                        NSURLResponse * _Nullable response,
                                        NSError * _Nullable error) {
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
            
            if (isUserJwt) {
                @synchronized (self) {
                    self.sentUserJwt = [GleapUserJwt identityFingerprintOf: userHash];
                    self.sentUserJwtGleapId = [sessionData objectForKey: @"gleapId"];
                }
            }
            [self updateLocalSessionWith: sessionData andCompletion:^(bool success) {}];
            
            // Restart logger, unless this identify only renewed the file access.
            if (needsUpdate) {
                [Gleap logEvent: @"sessionStarted"];
                [[GleapEventLogHelper sharedInstance] stop];
                [[GleapEventLogHelper sharedInstance] start];
            }
        } else if ([GleapUserJwt isIdentityMismatchForStatus: [GleapAPIClient statusCodeOfResponse: response] body: data]) {
            // Another user's session (spec §1.3): drop the local session and identify once more as a
            // fresh visitor; the server merges that visitor into the token's contact.
            [self restartForIdentify: identityAction];
        } else if ([GleapUserJwt refusalCodeForStatus: [GleapAPIClient statusCodeOfResponse: response] body: data] != nil) {
            // A refused identity token keeps the identity and the session (contract §3).
            NSString *refusedToken = [userHash isKindOfClass: [NSString class]] ? userHash : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.userJwtGate rememberRefusedToken: refusedToken];
            });
            [self handleUserJwtRefusal: [GleapUserJwt refusalCodeForStatus: [GleapAPIClient statusCodeOfResponse: response] body: data]
                           forIdentify: identityAction
                                 epoch: epoch];
        } else if ([GleapSessionHelper isErrorAnswerInResponse: response data: data]) {
            if ([GleapUserJwt isSignatureRequiredForStatus: [GleapAPIClient statusCodeOfResponse: response] body: data]) {
                NSLog(@"[GLEAP_SDK] Gleap: this project enforces identity verification and the identify had no valid signature (signature_required). Pass a token from your backend to setUserJwt.");
            }
            if (signedGrantOnly) {
                // Only asked for the grant of a session the server already identified: it stays.
                NSLog(@"[GLEAP_SDK] The signed identify for this session was refused; the session stays unsigned. Pass a token from your backend to setUserJwt.");
                return;
            }
            // The server refused this identity (for example a wrong user hash): start over as a guest.
            [self clearSession];
        }
        // Anything else (overloaded, a server failure, an answer without a session) keeps the identity.
    };
    self.identifyInFlight = YES;
    [GleapAPIClient sendRequest: request completion:^(NSData * _Nullable data,
                                                      NSURLResponse * _Nullable response,
                                                      NSError * _Nullable error) {
        self.identifyInFlight = NO;
        handleAnswer(data, response, error);
        if (needsUpdate) {
            [self contactRequestEnded];
        }
        // Auth tokens need the signed session: sent after a verified identify.
        if ([userHash isKindOfClass: [NSString class]] && [userHash length] > 0 && [GleapAPIClient isSuccessResponse: response]) {
            [self sendAuthTokensIfNeeded];
        }
    }];
}

#pragma mark - Waiting for the contact

/*
 A survey reads the contact (user id, email, name, phone) once, when it starts, to skip the contact
 questions it already knows. Started while an identify is on its way it would ask the user for what
 the app just gave, or be torn down when the identified session (a new gleapId) reaches the widget.
 Runs `block` on the main queue once the identify and contact updates on their way are answered, at
 the latest after kGleapContactSettleTimeout. NO (and `block` does not run) when none is on its way.
 */
- (BOOL)runWhenContactSettled:(dispatch_block_t)block {
    __block BOOL ran = NO;
    dispatch_block_t once = ^{
        if (ran) {
            return;
        }
        ran = YES;
        block();
    };
    @synchronized (self) {
        if (self.contactRequestsInFlight == 0) {
            return NO;
        }
        if (self.waitingForContact == nil) {
            self.waitingForContact = [[NSMutableArray alloc] init];
        }
        [self.waitingForContact addObject: once];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kGleapContactSettleTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), once);
    return YES;
}

- (void)contactRequestStarted {
    @synchronized (self) {
        self.contactRequestsInFlight++;
    }
}

// After the answer is applied: the waiting survey starts with the session it brought.
- (void)contactRequestEnded {
    NSArray<dispatch_block_t> *waiting;
    @synchronized (self) {
        if (self.contactRequestsInFlight > 0) {
            self.contactRequestsInFlight--;
        }
        if (self.contactRequestsInFlight > 0) {
            return;
        }
        waiting = self.waitingForContact;
        self.waitingForContact = nil;
    }
    for (dispatch_block_t block in waiting) {
        dispatch_async(dispatch_get_main_queue(), block);
    }
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
    
    // The grant of a signed identify; a grant for another session never rides along.
    GleapGrant *grants = [GleapGrant sharedInstance];
    [grants applySessionAnswer: data];
    id identity = [data objectForKey: @"identity"];
    if ([identity isKindOfClass: [NSDictionary class]]) {
        id mode = [identity objectForKey: @"mode"];
        @synchronized (self) {
            self.identityMode = [mode isKindOfClass: [NSString class]] ? mode : nil;
        }
    }
    if ([grants expiresAt] != nil && [grants grantForGleapId: gleapSession.gleapId] == nil) {
        [grants clear];
    }
    
    // Update local session.
    self.currentSession = gleapSession;
    [self scheduleFileAccessRenewal];
    [self scheduleGrantRenewal];
    
    // Process any open identity actions.
    [self processOpenIdentityAction];
    [self requestSignedGrantIfNeeded];
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
        // The identity token and the auth tokens go with the user; the JWT provider stays.
        self.sentUserJwt = nil;
        self.sentUserJwtGleapId = nil;
        [self.authTokens removeAllObjects];
        [self.removedAuthTokens removeAllObjects];
        self.authTokensSentFor = nil;
        self.identityMode = nil;
        self.sessionEpoch++;
        self.fileAccessRenewal++;
        self.grantRenewal++;
    }
    [[NSUserDefaults standardUserDefaults] removeObjectForKey: @"gleapId"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey: @"gleapHash"];
    [[GleapGrant sharedInstance] clear];
    
    // Update widget session
    [[GleapWidgetManager sharedInstance] sendSessionUpdate];
    [GleapUIOverlayHelper clear];
    
    // Restart a session.
    [self startSessionWith:^(bool success) {}];
}

#pragma mark - Grant

/*
 YES when the project runs Signed (`identity.mode`), `session` is identified (has a userId) and has
 no grant, and no signed identify was sent for it yet in this app launch. Holds the lock.
 */
- (BOOL)signedGrantMissingFor:(nullable GleapSession *)session {
    @synchronized (self) {
        if (session.gleapId.length == 0 || session.userId.length == 0 || ![self.identityMode isEqualToString: @"signed"]) {
            return NO;
        }
        if ([self.signedGrantRequestedFor isEqualToString: session.gleapId]) {
            return NO;
        }
        return [[GleapGrant sharedInstance] grantForGleapId: session.gleapId] == nil;
    }
}

/*
 A returning user on a project that switched to Signed: the session is identified but has no grant,
 and the app's identify of this launch (its hash or token) was skipped as unchanged. Sends it once
 (through the JWT provider when the token is about to expire); processOpenIdentityAction marks the
 session so it never repeats.
 */
- (void)requestSignedGrantIfNeeded {
    NSDictionary *identify;
    @synchronized (self) {
        GleapSession *session = self.currentSession;
        identify = self.lastIdentifyAction;
        if (identify == nil || self.openIdentityAction != nil || self.identifyInFlight || ![self signedGrantMissingFor: session]) {
            return;
        }
        id userHash = [identify objectForKey: @"userHash"];
        if (![userHash isKindOfClass: [NSString class]] || [userHash length] == 0 || ![[identify objectForKey: @"userId"] isEqual: session.userId]) {
            return;
        }
    }
    [self withFreshUserJwt: identify send:^(NSDictionary *fresh) {
        @synchronized (self) {
            if (self.openIdentityAction != nil) {
                return;
            }
            self.openIdentityAction = fresh;
        }
        [self processOpenIdentityAction];
    }];
}

/*
 The server answered identity_mismatch: the session belongs to another user. Drops the local
 session (the grant, the stored gleapId / gleapHash; the identify, the JWT provider and the auth
 tokens stay), starts a fresh visitor session and sends the identify once more on it. A second
 mismatch starts over as a guest.
 */
- (void)restartForIdentify:(NSDictionary *)identityAction {
    if ([[identityAction objectForKey: @"mismatchRetried"] boolValue]) {
        NSLog(@"[GLEAP_SDK] The identity was refused twice (identity_mismatch). Starting over as a guest.");
        [self clearSession];
        return;
    }
    [self sendPushMessageUnregister];
    [self revokeFileAccess: self.currentSession.fileAccessToken];
    @synchronized (self) {
        NSMutableDictionary *retry = [identityAction mutableCopy];
        [retry setObject: @(YES) forKey: @"mismatchRetried"];
        [retry removeObjectForKey: @"renewFileAccess"];
        [retry removeObjectForKey: @"renewGrant"];
        // A newer identify waiting to go out wins.
        if (self.openIdentityAction == nil) {
            self.openIdentityAction = retry;
        }
        self.currentSession = nil;
        self.sentUserJwt = nil;
        self.sentUserJwtGleapId = nil;
        self.authTokensSentFor = nil;
        self.sessionEpoch++;
        self.fileAccessRenewal++;
        self.grantRenewal++;
    }
    [[NSUserDefaults standardUserDefaults] removeObjectForKey: @"gleapId"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey: @"gleapHash"];
    [[GleapGrant sharedInstance] clear];
    [[GleapWidgetManager sharedInstance] sendSessionUpdate];
    // The new session's answer sends the identify waiting above.
    [self startSessionWith:^(bool success) {}];
}

/*
 Replays the app's last verified identify (through the JWT provider when its token is about to
 expire) when the grant of the current session has expired or expires within 5 minutes. YES when a
 renewal started.
 */
- (BOOL)refreshGrantIfNeeded {
    GleapSession *session = self.currentSession;
    NSDictionary *identify;
    @synchronized (self) {
        identify = self.lastIdentifyAction;
        if (session == nil || identify == nil || self.openIdentityAction != nil || self.identifyInFlight) {
            return NO;
        }
    }
    id userHash = [identify objectForKey: @"userHash"];
    if (![userHash isKindOfClass: [NSString class]] || [userHash length] == 0) {
        return NO;
    }
    if (![[GleapGrant sharedInstance] needsRenewalForGleapId: session.gleapId within: kGleapGrantRenewBefore]) {
        return NO;
    }
    NSTimeInterval throttled = 0;
    NSUInteger renewal = 0;
    @synchronized (self) {
        NSTimeInterval since = self.lastGrantRenewal != nil ? [[NSDate date] timeIntervalSinceDate: self.lastGrantRenewal] : kGleapFileAccessForegroundInterval;
        if (since < kGleapFileAccessForegroundInterval) {
            throttled = kGleapFileAccessForegroundInterval - since;
            renewal = self.grantRenewal;
        } else {
            self.lastGrantRenewal = [NSDate date];
        }
    }
    if (throttled > 0) {
        // At most one renewal a minute: try again once the minute is over (a short grant renewed
        // at half its lifetime would otherwise lapse), unless a newer grant reschedules first.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((throttled + 1) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @synchronized (self) {
                if (renewal != self.grantRenewal) {
                    return;
                }
            }
            [self refreshGrantIfNeeded];
        });
        return NO;
    }
    [self withFreshUserJwt: identify send:^(NSDictionary *fresh) {
        @synchronized (self) {
            if (self.openIdentityAction != nil) {
                return;
            }
            NSMutableDictionary *action = [fresh mutableCopy];
            [action setObject: @(YES) forKey: @"renewGrant"];
            self.openIdentityAction = action;
        }
        [self processOpenIdentityAction];
    }];
    return YES;
}

- (void)scheduleGrantRenewal {
    NSUInteger renewal;
    @synchronized (self) {
        renewal = ++self.grantRenewal;
    }
    NSDate *expiresAt = [[GleapGrant sharedInstance] expiresAt];
    if (expiresAt == nil || [[GleapGrant sharedInstance] grantForGleapId: self.currentSession.gleapId] == nil) {
        return;
    }
    // min(5 minutes, half the grant's lifetime) before it expires.
    NSTimeInterval delay = MAX(0, [expiresAt timeIntervalSinceNow] - [[GleapGrant sharedInstance] renewBefore: kGleapGrantRenewBefore]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @synchronized (self) {
            if (renewal != self.grantRenewal) {
                return;
            }
        }
        [self refreshGrantIfNeeded];
    });
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
    // Timers do not run while the app is suspended: an expired grant is renewed on return.
    [self refreshGrantIfNeeded];
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
    // An identity token about to expire is renewed through the JWT provider first.
    [self withFreshUserJwt: identify send:^(NSDictionary *fresh) {
        @synchronized (self) {
            if (self.openIdentityAction != nil) {
                return;
            }
            NSMutableDictionary *action = [fresh mutableCopy];
            [action setObject: @(YES) forKey: @"renewFileAccess"];
            self.openIdentityAction = action;
        }
        [self processOpenIdentityAction];
    }];
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
