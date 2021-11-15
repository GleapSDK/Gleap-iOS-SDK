//
//  GleapReplayHelper.m
//  Gleap
//
//  Created by Lukas Boehler on 15.01.21.
//

#import "GleapLogHelper.h"
#import "GleapSessionHelper.h"
#import "GleapCore.h"

@implementation GleapLogHelper

/*
 Returns a shared instance (singleton).
 */
+ (instancetype)sharedInstance
{
    static GleapLogHelper *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GleapLogHelper alloc] init];
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

- (void)initHelper {
    self.log = [[NSMutableArray alloc] init];
    self.streamedLog = [[NSMutableArray alloc] init];
}

- (NSArray *)getLogs {
    return self.log;
}

- (void)checkLogSize {
    if (self.log.count >= 1000) {
        [self.log removeObjectAtIndex: 0];
    }
}

- (void)logEvent: (NSString *)name {
    [self checkLogSize];
    [self.log addObject: @{
        @"name": name,
        @"date": [self getCurrentJSDate]
    }];
    [self.streamedLog addObject: @{
        @"name": name,
        @"date": [self getCurrentJSDate]
    }];
}

- (void)logEvent: (NSString *)name withData: (NSDictionary *)data {
    [self checkLogSize];
    [self.log addObject: @{
        @"name": name,
        @"data": data,
        @"date": [self getCurrentJSDate]
    }];
    [self.streamedLog addObject: @{
        @"name": name,
        @"data": data,
        @"date": [self getCurrentJSDate]
    }];
    
}

- (void)start {
    if (self.eventStreamTimer != nil) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.eventStreamTimer = [NSTimer scheduledTimerWithTimeInterval: 2
                                             target: self
                                           selector: @selector(sendEventStreamToServer)
                                           userInfo: nil
                                            repeats: YES];
    });
}

/*
 Stream logs to backend.
 */
- (void)sendEventStreamToServer {
    if (
        [Gleap sharedInstance].token == NULL
        || [[Gleap sharedInstance].token isEqualToString: @""]
        || [Gleap sharedInstance].apiUrl == NULL
        || [[Gleap sharedInstance].apiUrl isEqualToString: @""]
        || GleapSessionHelper.sharedInstance.currentSession == nil
        || self.streamedLog == nil || self.streamedLog.count <= 0
    ) {
        return;
    }
    
    NSDictionary *data = @{
        @"events": self.streamedLog
    };
    
    NSError *error;
    NSData *jsonBodyData = [NSJSONSerialization dataWithJSONObject: data options:kNilOptions error: &error];
    
    // Check for parsing error.
    if (error != nil) {
        return;
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest new];
    request.HTTPMethod = @"POST";
    [request setURL: [NSURL URLWithString: [NSString stringWithFormat: @"%@/sessions/stream", [Gleap sharedInstance].apiUrl]]];
    [GleapSessionHelper injectSessionInRequest: request];
    [request setValue: @"application/json" forHTTPHeaderField: @"Content-Type"];
    [request setValue: @"application/json" forHTTPHeaderField: @"Accept"];
    [request setHTTPBody: jsonBodyData];
    
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config
                                                          delegate:nil
                                                     delegateQueue:[NSOperationQueue mainQueue]];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error != nil) {
            return;
        }
        
        if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
            return;
        }
        
        NSError *jsonError;
        NSDictionary *action = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError) {
            return;
        }
        
        if ([action objectForKey: @"actionType"] != nil && [action objectForKey: @"outbound"] != nil) {
            GleapAction *gleapAction = [[GleapAction alloc] init];
            gleapAction.actionType = [action objectForKey: @"actionType"];
            gleapAction.outbound = [action objectForKey: @"outbound"];
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [Gleap.sharedInstance performAction: gleapAction];
            });
        }
    }];
    [task resume];
    
    // Clear items.
    [self.streamedLog removeAllObjects];
}

- (NSString *)getCurrentJSDate {
    return [[Gleap sharedInstance] getJSStringForNSDate: [[NSDate alloc] init]];
}


- (void)clear {
    self.log = [[NSMutableArray alloc] init];
}

@end
