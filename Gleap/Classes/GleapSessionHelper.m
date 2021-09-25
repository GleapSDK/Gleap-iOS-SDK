//
//  GleapSessionHelper.m
//  Gleap
//
//  Created by Lukas Boehler on 23.09.21.
//

#import "GleapSessionHelper.h"
#import "GleapCore.h"

@implementation GleapSessionHelper

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
    if (session != nil && session.userId != nil) {
        [request setValue: session.userId forHTTPHeaderField: @"Gleap-Id"];
    }
    if (session != nil && session.userHash != nil) {
        [request setValue: session.userHash forHTTPHeaderField: @"Gleap-Hash"];
    }
    [request setValue: Gleap.sharedInstance.token forHTTPHeaderField: @"Api-Token"];
}

- (id)init {
    self = [super init];
    return self;
}

- (void)startSessionWithData:(nullable GleapUserSession *)data andCompletion:(void (^)(bool success))completion {
    NSMutableDictionary *sessionRequestData = [[NSMutableDictionary alloc] init];
    
    if (data != nil && data.name != nil) {
        [sessionRequestData setValue: data.name forKey: @"name"];
    }
    if (data != nil && data.email != nil) {
        [sessionRequestData setValue: data.email forKey: @"email"];
    }
    
    NSError *error;
    NSData *jsonBodyData = [NSJSONSerialization dataWithJSONObject: sessionRequestData options:kNilOptions error: &error];
    
    // Check for parsing error.
    if (error != nil) {
        return completion(false);
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest new];
    request.HTTPMethod = @"POST";
    [request setURL: [NSURL URLWithString: [NSString stringWithFormat: @"%@/sessions/start", Gleap.sharedInstance.apiUrl]]];
    [request setValue: Gleap.sharedInstance.token forHTTPHeaderField: @"Api-Token"];
    [request setValue: @"application/json" forHTTPHeaderField: @"Content-Type"];
    [request setValue: @"application/json" forHTTPHeaderField: @"Accept"];
    
    // Merge guest session.
    NSString *sessionType = [[NSUserDefaults standardUserDefaults] stringForKey:@"glSessionType"];
    if ([sessionType isEqualToString: @"GUEST"]) {
        NSString *glSessionId = [[NSUserDefaults standardUserDefaults] stringForKey:@"glSessionId"];
        [request setValue: glSessionId forHTTPHeaderField: @"Guest-Id"];
        NSString *glSessionHash = [[NSUserDefaults standardUserDefaults] stringForKey:@"glSessionHash"];
        [request setValue: glSessionHash forHTTPHeaderField: @"Guest-Hash"];
    }
    
    // Additionally set the user id
    if (data != nil && data.userId != nil) {
        [request setValue: data.userId forHTTPHeaderField: @"User-Id"];
    }
    if (data != nil && data.userHash != nil) {
        [request setValue: data.userHash forHTTPHeaderField: @"User-Hash"];
    }
    
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
        
        if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
            return completion(false);
        }
        
        NSError *jsonError;
        NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError) {
            return completion(false);
        }
        
        // Save session data from server.
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        [userDefaults setValue: [jsonResponse objectForKey: @"type"] forKey: @"glSessionType"];
        [userDefaults setValue: [jsonResponse objectForKey: @"hash"] forKey: @"glSessionHash"];
        [userDefaults setValue: [jsonResponse objectForKey: @"id"] forKey: @"glSessionId"];
        
        // Create session and assign it.
        GleapSession *gleapSession = [[GleapSession alloc] init];
        gleapSession.type = [jsonResponse objectForKey: @"type"];
        gleapSession.userHash = [jsonResponse objectForKey: @"hash"];
        gleapSession.userId = [jsonResponse objectForKey: @"id"];
        
        self.currentSession = gleapSession;
        
        return completion(true);
    }];
    [task resume];
}

- (void)clearSession {
    self.currentSession = nil;
    [[NSUserDefaults standardUserDefaults] removeObjectForKey: @"glSessionType"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey: @"glSessionHash"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey: @"glSessionId"];
    
    // Restart a session.
    [self startSessionWithData: nil andCompletion:^(bool success) {}];
}

@end
