//
//  GleapSessionHelper.m
//  Gleap
//
//  Created by Lukas Boehler on 23.09.21.
//

#import "GleapSessionHelper.h"
#import "GleapCore.h"
#import "GleapWidgetManager.h"
#import "GleapNotificationHelper.h"
#import "GleapCore.h"
#import "GleapEventLogHelper.h"
#import "GleapTranslationHelper.h"

@implementation GleapSessionHelper

static id ObjectOrNull(id object)
{
  return object ?: [NSNull null];
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

- (id)init {
    self = [super init];
    return self;
}

- (void)startSessionWith:(void (^)(bool success))completion {
    NSMutableURLRequest *request = [NSMutableURLRequest new];
    request.HTTPMethod = @"POST";
    [request setURL: [NSURL URLWithString: [NSString stringWithFormat: @"%@/sessions", Gleap.sharedInstance.apiUrl]]];
    [request setValue: Gleap.sharedInstance.token forHTTPHeaderField: @"Api-Token"];
    [request setValue: @"application/json" forHTTPHeaderField: @"Content-Type"];
    [request setValue: @"application/json" forHTTPHeaderField: @"Accept"];
    
    // Merge guest session.
    NSString *gleapId = [[NSUserDefaults standardUserDefaults] stringForKey:@"gleapId"];
    NSString *gleapHash = [[NSUserDefaults standardUserDefaults] stringForKey:@"gleapHash"];
    if (gleapId != nil && gleapId.length > 0 && gleapHash != nil && gleapHash.length > 0) {
        [request setValue: gleapId forHTTPHeaderField: @"Gleap-Id"];
        [request setValue: gleapHash forHTTPHeaderField: @"Gleap-Hash"];
    }
    
    NSString *lang = [GleapTranslationHelper sharedInstance].language;
    if (lang != nil) {
        NSError *error;
        NSData *jsonBodyData = [NSJSONSerialization dataWithJSONObject: @{
            @"lang": lang
        } options:kNilOptions error: &error];
        if (error == nil) {
            [request setHTTPBody: jsonBodyData];
        }
    }
    
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
        
        if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
            return completion(false);
        }
        
        NSError *jsonError;
        NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError) {
            return completion(false);
        }
        
        [Gleap logEvent: @"sessionStarted"];
        [[GleapEventLogHelper sharedInstance] stop];
        [[GleapEventLogHelper sharedInstance] start];
    
        return [self updateLocalSessionWith: jsonResponse andCompletion: completion];
    }];
    [task resume];
}

- (void)identifySessionWith:(NSString *)userId andData:(nullable GleapUserProperty *)data andUserHash:(NSString * _Nullable)userHash {
    self.openIdentityAction = @{
        @"userId": userId,
        @"userHash": ObjectOrNull(userHash),
        @"data": data
    };
    [self processOpenIdentityAction];
    [self processOpenPushAction];
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
        }
        if ([type isEqualToString: @"conversation"]) {
            [Gleap openConversation: itemId];
        }
    }
    return;
}

- (void)processOpenIdentityAction {
    if (self.openIdentityAction == nil || self.currentSession == nil) {
        return;
    }
    
    NSString *userId = [self.openIdentityAction objectForKey: @"userId"];
    NSString *userHash = [self.openIdentityAction objectForKey: @"userHash"];
    GleapUserProperty *data = [self.openIdentityAction objectForKey: @"data"];
    self.openIdentityAction = nil;
    
    NSMutableDictionary *sessionRequestData = [[NSMutableDictionary alloc] init];
    if (userId != nil) {
        [sessionRequestData setValue: userId forKey: @"userId"];
    }
    if (data != nil && data.name != nil) {
        [sessionRequestData setValue: data.name forKey: @"name"];
    }
    if (data != nil && data.email != nil) {
        [sessionRequestData setValue: data.email forKey: @"email"];
    }
    if (data != nil && data.phone != nil) {
        [sessionRequestData setValue: data.phone forKey: @"phone"];
    }
    if (data != nil && data.value != nil) {
        [sessionRequestData setValue: data.value forKey: @"value"];
    }
    if (userHash != nil) {
        [sessionRequestData setValue: userHash forKey: @"userHash"];
    }
    
    NSString *lang = [GleapTranslationHelper sharedInstance].language;
    if (lang != nil) {
        [sessionRequestData setValue: lang forKey: @"lang"];
    }
    
    @try {
        if (data != nil && data.customData != nil && [[data.customData allKeys] count] > 0) {
            [sessionRequestData addEntriesFromDictionary: data.customData];
        }
    } @catch (id exp) {}
    
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
            for (int i = 0; i < keys.count; i++) {
                NSString *key = [keys objectAtIndex: i];
                [sessionRequestData setValue: [data.customData objectForKey: key] forKey: key];
            }
        }
    } @catch (id exp) {}
    
    NSError *error;
    NSData *jsonBodyData = [NSJSONSerialization dataWithJSONObject: sessionRequestData options:kNilOptions error: &error];
    
    // Check for parsing error.
    if (error != nil) {
        return;
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest new];
    request.HTTPMethod = @"POST";
    [request setURL: [NSURL URLWithString: [NSString stringWithFormat: @"%@/sessions/identify", Gleap.sharedInstance.apiUrl]]];
    [request setValue: Gleap.sharedInstance.token forHTTPHeaderField: @"Api-Token"];
    [request setValue: @"application/json" forHTTPHeaderField: @"Content-Type"];
    [request setValue: @"application/json" forHTTPHeaderField: @"Accept"];
    
    // Merge guest session.
    NSString *gleapId = [[NSUserDefaults standardUserDefaults] stringForKey:@"gleapId"];
    NSString *gleapHash = [[NSUserDefaults standardUserDefaults] stringForKey:@"gleapHash"];
    [request setValue: gleapId forHTTPHeaderField: @"Gleap-Id"];
    [request setValue: gleapHash forHTTPHeaderField: @"Gleap-Hash"];

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
            return;
        }
        
        if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
            return;
        }
        
        NSError *jsonError;
        NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError) {
            return;
        }
        
        if (jsonResponse != nil && [jsonResponse objectForKey: @"errors"] == nil) {
            // Send unregister of previous group.
            [self sendPushMessageUnregister];
            
            [self updateLocalSessionWith: jsonResponse andCompletion:^(bool success) {}];
            
            // Restart logger.
            [Gleap logEvent: @"sessionStarted"];
            [[GleapEventLogHelper sharedInstance] stop];
            [[GleapEventLogHelper sharedInstance] start];
        } else {
            // Clear session due to an error.
            [self clearSession];
        }
    }];
    [task resume];
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
    
    if ([self sessionDataItemNeedsUpgrade: self.currentSession.userId compareTo: [newData objectForKey: @"userId"]]) {
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
    } @catch (id exp) {
        
    }
    
    @try {
        gleapSession.customData = [data objectForKey: @"customData"];
    } @catch (id exp) {
        
    }
    
    self.currentSession = gleapSession;
    
    // Process any open identity actions.
    [self processOpenIdentityAction];
    [self processOpenPushAction];
    
    if (self.currentSession != nil && self.currentSession.gleapHash != nil && self.currentSession.gleapHash.length > 0 && [Gleap sharedInstance].delegate != nil && [Gleap.sharedInstance.delegate respondsToSelector: @selector(registerPushMessageGroup:)]) {
        [[Gleap sharedInstance].delegate registerPushMessageGroup: [NSString stringWithFormat: @"gleapuser-%@", self.currentSession.gleapHash]];
    }
    
    // Update widget session
    [[GleapWidgetManager sharedInstance] sendSessionUpdate];
    
    return completion(true);
}

- (void)sendPushMessageUnregister {
    if (self.currentSession != nil && self.currentSession.gleapHash != nil && self.currentSession.gleapHash.length > 0 && [Gleap sharedInstance].delegate != nil && [Gleap.sharedInstance.delegate respondsToSelector: @selector(unregisterPushMessageGroup:)]) {
        [[Gleap sharedInstance].delegate unregisterPushMessageGroup: [NSString stringWithFormat: @"gleapuser-%@", self.currentSession.gleapHash]];
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
    [GleapNotificationHelper clear];
    
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
    
    return ![data isEqualToDictionary: newData];
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
    
    return !(data == newData);
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
