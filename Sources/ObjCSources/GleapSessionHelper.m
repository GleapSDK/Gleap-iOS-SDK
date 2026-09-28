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

@implementation GleapSessionHelper

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
 YES when the server answered with an explicit error (an `error` or `errors` body) that is not a
 server failure (5xx), i.e. it refused the request itself rather than failing to handle it.
 */
+ (BOOL)isErrorAnswerInResponse:(NSURLResponse *)response data:(NSData *)data {
    NSInteger status = [GleapAPIClient statusCodeOfResponse: response];
    if (status == 0 || status >= 500 || data == nil) {
        return NO;
    }
    id json = [NSJSONSerialization JSONObjectWithData: data options: 0 error: nil];
    return [json isKindOfClass: [NSDictionary class]] && ([json objectForKey: @"error"] != nil || [json objectForKey: @"errors"] != nil);
}

- (id)init {
    self = [super init];
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
    
        return [self updateLocalSessionWith: sessionData andCompletion: completion];
    }];
}

- (void)identifySessionWith:(NSString *)userId andData:(nullable GleapUserProperty *)data andUserHash:(NSString * _Nullable)userHash {
    if (userId == nil) {
        NSLog(@"[GLEAP_SDK] identify needs a user id.");
        return;
    }
    // The user data is optional; without it only the user id is sent.
    self.openIdentityAction = @{
        @"userId": userId,
        @"userHash": GleapObjectOrNull(userHash),
        @"data": data ?: [[GleapUserProperty alloc] init]
    };
    [self processOpenIdentityAction];
    [self processOpenPushAction];
}

- (void)updateContact:(nullable GleapUserProperty *)data {
    self.openUpdateAction = @{
        @"data": data ?: [[GleapUserProperty alloc] init],
    };
    
    [self processOpenUpdateAction];
}

+ (void)handlePushNotification:(NSDictionary *)notificationData {
    [GleapSessionHelper sharedInstance].openPushAction = notificationData;
    [[GleapSessionHelper sharedInstance] processOpenPushAction];
}

- (void)processOpenPushAction {
    if (self.openPushAction == nil || self.currentSession == nil) {
        return;
    }
    
    NSString *type = [self.openPushAction objectForKey: @"type"];
    NSString *itemId = [self.openPushAction objectForKey: @"id"];
    self.openPushAction = nil;
    
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
    if (self.openUpdateAction == nil || self.currentSession == nil || self.openIdentityAction != nil) {
        return;
    }
    
    NSString *gleapId = [[NSUserDefaults standardUserDefaults] stringForKey:@"gleapId"];
    NSString *gleapHash = [[NSUserDefaults standardUserDefaults] stringForKey:@"gleapHash"];
    if (gleapId == nil || gleapHash == nil || gleapId.length == 0 || gleapHash.length == 0) {
        return;
    }
    GleapUserProperty *data = [self.openUpdateAction objectForKey: @"data"];
    self.openUpdateAction = nil;
    
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
            }
        }];
    } @catch (id exp) {}
}

- (void)processOpenIdentityAction {
    if (self.openIdentityAction == nil || self.currentSession == nil) {
        return;
    }
    
    NSString *userId = [self.openIdentityAction objectForKey: @"userId"];
    NSString *userHash = [self.openIdentityAction objectForKey: @"userHash"];
    GleapUserProperty *data = [self.openIdentityAction objectForKey: @"data"];
    self.openIdentityAction = nil;
    
    NSDictionary *sessionRequestData = [data dataDictToSendWith: userId and: userHash];
    
    // Used to check for update.
    NSMutableDictionary *sessionDataToCheckForUpdate = [sessionRequestData mutableCopy];
    if (data != nil && data.customData != nil) {
        [sessionDataToCheckForUpdate setValue: data.customData forKey: @"customData"];
    }
    
    bool needsUpdate = [self sessionUpgradeWithDataNeeded: sessionDataToCheckForUpdate];
    if (!needsUpdate) {
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
    
    [GleapAPIClient sendRequest: request completion:^(NSData * _Nullable data,
                                                      NSURLResponse * _Nullable response,
                                                      NSError * _Nullable error) {
        if (error != nil) {
            return;
        }
        
        NSDictionary *sessionData = [GleapSessionHelper sessionDataInResponse: response data: data];
        if (sessionData != nil) {
            // Send unregister of previous group.
            [self sendPushMessageUnregister];
            
            [self updateLocalSessionWith: sessionData andCompletion:^(bool success) {}];
            
            // Restart logger.
            [Gleap logEvent: @"sessionStarted"];
            [[GleapEventLogHelper sharedInstance] stop];
            [[GleapEventLogHelper sharedInstance] start];
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
    
    // Update local session.
    self.currentSession = gleapSession;
    
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
    
    self.currentSession = nil;
    self.openIdentityAction = nil;
    [[NSUserDefaults standardUserDefaults] removeObjectForKey: @"gleapId"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey: @"gleapHash"];
    
    // Update widget session
    [[GleapWidgetManager sharedInstance] sendSessionUpdate];
    [GleapUIOverlayHelper clear];
    
    // Restart a session.
    [self startSessionWith:^(bool success) {}];
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
