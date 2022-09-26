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
}

- (void)processOpenIdentityAction {
    if (self.openIdentityAction == nil || self.currentSession == nil) {
        return;
    }
    
    NSString *userId = [self.openIdentityAction objectForKey: @"userId"];
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
    
    if (![self sessionUpgradeWithDataNeeded: sessionRequestData]) {
        return;
    }
    
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
        
        [self updateLocalSessionWith: jsonResponse andCompletion:^(bool success) {}];
    }];
    [task resume];
}

- (void)updateLocalSessionWith:(NSDictionary *)data andCompletion:(void (^)(bool success))completion {
    // Save session data from server.
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setValue: [data objectForKey: @"gleapId"] forKey: @"gleapId"];
    [userDefaults setValue: [data objectForKey: @"gleapHash"] forKey: @"gleapHash"];
    
    // Create session and assign it.
    GleapSession *gleapSession = [[GleapSession alloc] init];
    gleapSession.gleapId = [data objectForKey: @"gleapId"];
    gleapSession.gleapHash = [data objectForKey: @"gleapHash"];
    gleapSession.userId = [data objectForKey: @"userId"];
    gleapSession.email = [data objectForKey: @"email"];
    gleapSession.phone = [data objectForKey: @"phone"];
    gleapSession.name = [data objectForKey: @"name"];
    
    self.currentSession = gleapSession;
    
    // Process any open identity actions.
    [self processOpenIdentityAction];
    
    // Update widget session
    [[GleapWidgetManager sharedInstance] sendSessionUpdate];
    
    return completion(true);
}

- (void)clearSession {
    self.currentSession = nil;
    [[NSUserDefaults standardUserDefaults] removeObjectForKey: @"gleapId"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey: @"gleapHash"];
    
    // Update widget session
    [[GleapWidgetManager sharedInstance] sendSessionUpdate];
    [GleapNotificationHelper clear];
    
    // Restart a session.
    [self startSessionWith:^(bool success) {}];
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
    
    // One value is nil, upgrade needed.
    if (data == nil || newData == nil) {
        return YES;
    }
    
    return !(data == newData);
}

- (BOOL)sessionUpgradeWithDataNeeded:(NSDictionary *)newData {
    if (self.currentSession == nil) {
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
    
    return NO;
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
