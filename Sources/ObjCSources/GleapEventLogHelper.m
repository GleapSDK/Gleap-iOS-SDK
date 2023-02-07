//
//  GleapReplayHelper.m
//  Gleap
//
//  Created by Lukas Boehler on 15.01.21.
//

#import "GleapEventLogHelper.h"
#import "GleapSessionHelper.h"
#import "GleapCore.h"
#import "GleapUIHelper.h"
#import "GleapWidgetManager.h"
#import "GleapMetaDataHelper.h"
#import "GleapNotificationHelper.h"

@implementation GleapEventLogHelper

/*
 Returns a shared instance (singleton).
 */
+ (instancetype)sharedInstance
{
    static GleapEventLogHelper *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GleapEventLogHelper alloc] init];
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
    self.disableInAppNotifications = NO;
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

- (void)stop {
    if (self.eventStreamTimer != nil) {
        [self.eventStreamTimer invalidate];
        self.eventStreamTimer = nil;
    }
}

- (void)start {
    if (self.eventStreamTimer != nil) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self lastPageNameUpdate];
        [self sendEventStreamToServer];
        
        self.pageNameTimer = [NSTimer scheduledTimerWithTimeInterval: 1
                                                              target: self
                                                            selector: @selector(lastPageNameUpdate)
                                                            userInfo: nil
                                                             repeats: YES];
        
        self.eventStreamTimer = [NSTimer scheduledTimerWithTimeInterval: 10.0
                                             target: self
                                           selector: @selector(sendEventStreamToServer)
                                           userInfo: nil
                                            repeats: YES];
    });
}

// Track page views.
- (void)lastPageNameUpdate {
    NSString *currentViewControllerName = [GleapUIHelper getTopMostViewControllerName];
    if (
        currentViewControllerName != nil
        && ![currentViewControllerName isEqualToString: self.lastPageName]
        && Gleap.sharedInstance.applicationType == NATIVE
        && ![[GleapWidgetManager sharedInstance] isOpened]
    ) {
        self.lastPageName = currentViewControllerName;
        
        // Append the page view.
        [Gleap logEvent: @"pageView" withData: @{
            @"page": currentViewControllerName
        }];
    }
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
        || self.streamedLog == nil
    ) {
        return;
    }
    
    NSDictionary *data = @{
        @"time": [NSNumber numberWithDouble: [[GleapMetaDataHelper sharedInstance] sessionDuration]],
        @"events": self.streamedLog,
        @"opened": @([Gleap isOpened])
    };
    
    @try {
        NSError *error;
        NSData *jsonBodyData = [NSJSONSerialization dataWithJSONObject: data options:kNilOptions error: &error];
        
        // Check for parsing error.
        if (error != nil) {
            return;
        }
        
        NSMutableURLRequest *request = [NSMutableURLRequest new];
        request.HTTPMethod = @"POST";
        [request setURL: [NSURL URLWithString: [NSString stringWithFormat: @"%@/sessions/ping", [Gleap sharedInstance].apiUrl]]];
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
            NSDictionary *actionData = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            if (jsonError) {
                return;
            }
            
            @try {
                NSArray *actions = [actionData objectForKey: @"a"];
                if (actions != nil) {
                    for (int i = 0; i < actions.count; i++) {
                        NSDictionary *action = [actions objectAtIndex: i];
                        if ([[action objectForKey: @"actionType"] isEqualToString: @"notification"]) {
                            if (self.disableInAppNotifications == NO) {
                                [GleapNotificationHelper showNotification: action];
                            }
                        } else {
                            if ([action objectForKey: @"actionType"] != nil) {
                                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                                    [Gleap.sharedInstance startFeedbackFlow: [action objectForKey: @"actionType"] withOptions: @{
                                        @"isSurvey": @YES,
                                        @"format": [action objectForKey: @"format"],
                                        @"hideBackButton": @YES
                                    }];
                                });
                            }
                        }
                    }
                }
                
                int unreadCount = [[actionData objectForKey: @"u"] intValue];
                [GleapNotificationHelper updateNotificationCount: unreadCount];
            }
            @catch(id exception) {}
        }];
        [task resume];
    } @catch(id exception) {
        
    }
    
    // Clear items.
    [self.streamedLog removeAllObjects];
}

- (NSString *)getCurrentJSDate {
    return [GleapUIHelper getJSStringForNSDate: [[NSDate alloc] init]];
}


- (void)clear {
    self.log = [[NSMutableArray alloc] init];
}

@end
