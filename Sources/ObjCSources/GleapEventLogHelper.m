//
//  GleapEventLogHelper.m
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
#import "GleapUIOverlayHelper.h"
#import "GleapWebSocketHelper.h"
#import "GleapAPIClient.h"
#import "GleapPingBackoff.h"

// At most this many events wait for a ping; the oldest ones (other than a session start) make room.
static NSUInteger const kGleapMaxQueuedEvents = 500;
// One ping carries the oldest events up to these limits; the rest follows once it was delivered.
static NSUInteger const kGleapMaxEventsPerPing = 100;
static NSUInteger const kGleapMaxPingBytes = 256 * 1024;

@interface GleapEventLogHelper ()
// When pings may go out again after failed ones.
@property (nonatomic, strong) GleapPingBackoff *pingBackoff;
// The ping waiting for its answer, 0 when none is: never more than one at a time.
@property (nonatomic, assign) NSUInteger pingInFlight;
@property (nonatomic, assign) NSUInteger lastPingId;
@end

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
    self.webSocketEnabled = NO;
    self.disableInAppNotifications = NO;
    self.log = [[NSMutableArray alloc] init];
    self.streamedLog = [[NSMutableArray alloc] init];
    self.pingBackoff = [[GleapPingBackoff alloc] init];
}

- (NSMutableArray *)mutableArrayFromArray:(NSArray *)array {
    if ([array isKindOfClass:[NSMutableArray class]]) {
        return (NSMutableArray *)array;
    }
    
    return array != nil ? [array mutableCopy] : [[NSMutableArray alloc] init];
}

- (NSArray *)getLogs {
    return self.log;
}

- (void)checkLogSize {
    self.log = [self mutableArrayFromArray:self.log];
    if (self.log.count >= 1000) {
        [self.log removeObjectAtIndex: 0];
    }
}

// Call with the lock held. Keeps the events waiting for a ping at the limit: the oldest one that
// is not a session start makes room, or the oldest one when all are.
- (void)trimStreamedLog {
    while (self.streamedLog.count > kGleapMaxQueuedEvents) {
        NSUInteger index = [self.streamedLog indexOfObjectPassingTest:^BOOL(id event, NSUInteger idx, BOOL *stop) {
            return !([event isKindOfClass: [NSDictionary class]] && [[(NSDictionary *)event objectForKey: @"name"] isEqual: @"sessionStarted"]);
        }];
        [self.streamedLog removeObjectAtIndex: index != NSNotFound ? index : 0];
    }
}

- (void)logEvent: (NSString *)name {
    @synchronized (self) {
        self.streamedLog = [self mutableArrayFromArray:self.streamedLog];
        [self checkLogSize];
        [self.log addObject: @{
            @"name": name,
            @"date": [self getCurrentJSDate]
        }];
        [self.streamedLog addObject: @{
            @"name": name,
            @"date": [self getCurrentJSDate]
        }];
        [self trimStreamedLog];
    }
}

- (void)logEvent: (NSString *)name withData: (NSDictionary *)data {
    @try {
        @synchronized (self) {
            self.streamedLog = [self mutableArrayFromArray:self.streamedLog];
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
            [self trimStreamedLog];
        }
    } @catch (id exp) {
        NSLog(@"[GLEAP]: Invalid data passed to Gleap.trackEvent() for event %@", name);
    }
}

- (void)stop {
    if (self.eventStreamTimer != nil) {
        [self.eventStreamTimer invalidate];
        self.eventStreamTimer = nil;
    }
    [self.pageNameTimer invalidate];
}

- (void)start {
    if (self.eventStreamTimer != nil) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        GleapSession *session = GleapSessionHelper.sharedInstance.currentSession;
        if (session != nil && session.gleapId != nil && session.gleapHash != nil) {
            self.webSocketEnabled = YES;
            NSString *urlToConnectTo = [NSString stringWithFormat: @"%@?gleapId=%@&gleapHash=%@&apiKey=%@&sdkVersion=%@", [Gleap sharedInstance].wsApiUrl, session.gleapId, session.gleapHash, [Gleap sharedInstance].token, SDK_VERSION];
            [[GleapWebSocketHelper sharedInstance] connectToURL: [NSURL URLWithString: urlToConnectTo]];
        }
        
        [self lastPageNameUpdate];
        [self sendEventStreamToServer];
        
        // Two starts in a row both get here before either timer exists: replace, don't add.
        [self.pageNameTimer invalidate];
        [self.eventStreamTimer invalidate];
        self.pageNameTimer = [NSTimer scheduledTimerWithTimeInterval: 1
                                                              target: self
                                                            selector: @selector(lastPageNameUpdate)
                                                            userInfo: nil
                                                             repeats: YES];
        
        self.eventStreamTimer = [NSTimer scheduledTimerWithTimeInterval: self.webSocketEnabled ? 3.0 : 10.0
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
 Streams the queued events to the backend (POST /sessions/ping): only with a session, one ping at a
 time, the oldest events first and at most 100 events or about 256 KB per ping. Events leave the
 queue once a 2xx answer delivered them, and the rest of a longer queue follows right away. After a
 429, a 5xx, any other error answer or a network error the events stay queued and the pings back
 off (see GleapPingBackoff); the timer ticks in between do nothing.
 */
- (void)sendEventStreamToServer {
    // The ping state lives on the main queue, where the timers and the answers arrive.
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self sendEventStreamToServer];
        });
        return;
    }
    
    GleapSession *session = GleapSessionHelper.sharedInstance.currentSession;
    if (
        [Gleap sharedInstance].token == NULL
        || [[Gleap sharedInstance].token isEqualToString: @""]
        || [Gleap sharedInstance].apiUrl == NULL
        || [[Gleap sharedInstance].apiUrl isEqualToString: @""]
        || session == nil
        || session.gleapId.length == 0
        || session.gleapHash.length == 0
        || self.streamedLog == nil
    ) {
        return;
    }
    
    if (self.pingInFlight != 0 || [self.pingBackoff remainingAt: NSProcessInfo.processInfo.systemUptime] > 0) {
        return;
    }
    
    BOOL hasMore = NO;
    NSArray *eventsToSend = [self nextPingBatchHasMore: &hasMore];
    
    // When websocket mode is enabled, don't send empty events.
    if (self.webSocketEnabled && eventsToSend.count == 0) {
        return;
    }
    
    NSDictionary *body = @{
        @"time": [NSNumber numberWithDouble: [[GleapMetaDataHelper sharedInstance] sessionDuration]],
        @"events": eventsToSend,
        @"opened": @([Gleap isOpened]),
        @"ws": @(self.webSocketEnabled),
        @"type": @"ios",
        @"sdkVersion": SDK_VERSION,
    };
    
    NSData *jsonBodyData = nil;
    @try {
        jsonBodyData = [NSJSONSerialization dataWithJSONObject: body options: kNilOptions error: nil];
    } @catch(id exception) {}
    if (jsonBodyData == nil) {
        return;
    }
    
    NSMutableURLRequest *request = [GleapAPIClient JSONRequestWithMethod: @"POST" path: @"/sessions/ping" identity: GleapRequestIdentityCurrentSession];
    [request setHTTPBody: jsonBodyData];
    self.lastPingId += 1;
    NSUInteger pingId = self.lastPingId;
    self.pingInFlight = pingId;
    [GleapAPIClient sendPingRequest: request completion:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        [self pingDidFinish: pingId sentEvents: eventsToSend hasMore: hasMore data: data response: response error: error];
    }];
}

- (void)pingDidFinish:(NSUInteger)pingId sentEvents:(NSArray *)sentEvents hasMore:(BOOL)hasMore data:(NSData *)data response:(NSURLResponse *)response error:(NSError *)error {
    // The queue was cleared in between: nobody waits for this answer any more.
    if (self.pingInFlight != pingId) {
        return;
    }
    self.pingInFlight = 0;
    
    if (error == nil && [GleapAPIClient isSuccessResponse: response]) {
        [self.pingBackoff reset];
        [self removeSentEvents: sentEvents];
        
        // Only a delivered ping carries actions and the unread count; an error answer would reset the badge.
        if (!self.webSocketEnabled && data != nil) {
            id actionData = [NSJSONSerialization JSONObjectWithData: data options: 0 error: nil];
            if ([actionData isKindOfClass: [NSDictionary class]]) {
                [self parseUpdate: actionData];
            }
        }
        
        if (hasMore) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self sendEventStreamToServer];
            });
        }
        return;
    }
    
    NSTimeInterval retryAfter = -1;
    if (error == nil && [response isKindOfClass: [NSHTTPURLResponse class]]) {
        NSString *value = [(NSHTTPURLResponse *)response valueForHTTPHeaderField: @"Retry-After"];
        retryAfter = [GleapPingBackoff retryAfterFromValue: value now: [NSDate date]];
    }
    double random = (double)arc4random() / ((double)UINT32_MAX + 1.0);
    [self.pingBackoff failureAt: NSProcessInfo.processInfo.systemUptime retryAfter: retryAfter random: random];
}

// The oldest queued events for one ping: at most 100, and no more than about 256 KB of JSON (a
// single larger event goes alone). An event that cannot be sent as JSON is dropped, so it does not
// hold back the others.
- (NSArray *)nextPingBatchHasMore:(BOOL *)hasMore {
    NSMutableArray *batch = [NSMutableArray array];
    NSMutableArray *broken = [NSMutableArray array];
    @synchronized (self) {
        self.streamedLog = [self mutableArrayFromArray: self.streamedLog];
        // The brackets of the array, and a comma per event.
        NSUInteger bytes = 2;
        for (id event in self.streamedLog) {
            if (batch.count >= kGleapMaxEventsPerPing) {
                break;
            }
            NSData *json = nil;
            @try {
                if ([NSJSONSerialization isValidJSONObject: event]) {
                    json = [NSJSONSerialization dataWithJSONObject: event options: kNilOptions error: nil];
                }
            } @catch(id exception) {}
            if (json == nil) {
                [broken addObject: event];
                continue;
            }
            NSUInteger size = json.length + 1;
            if (batch.count > 0 && bytes + size > kGleapMaxPingBytes) {
                break;
            }
            [batch addObject: event];
            bytes += size;
        }
        for (id event in broken) {
            [self.streamedLog removeObjectIdenticalTo: event];
        }
        *hasMore = batch.count < self.streamedLog.count;
    }
    for (id event in broken) {
        NSLog(@"[GLEAP]: Dropped the event %@, its data cannot be sent as JSON.", [event isKindOfClass: [NSDictionary class]] ? [(NSDictionary *)event objectForKey: @"name"] : event);
    }
    return batch;
}

// Removes exactly the delivered events; events tracked while the ping was in flight wait for the next one.
- (void)removeSentEvents:(NSArray *)sentEvents {
    @synchronized (self) {
        self.streamedLog = [self mutableArrayFromArray: self.streamedLog];
        for (id event in sentEvents) {
            [self.streamedLog removeObjectIdenticalTo: event];
        }
    }
}

- (void)parseUpdate:(NSDictionary *)actionData {
    @try {
        if (![Gleap isOpened]) {
            NSArray *actions = [actionData objectForKey: @"a"];
            if (actions != nil) {
                for (NSUInteger i = 0; i < actions.count; i++) {
                    NSDictionary *action = [actions objectAtIndex: i];
                    if ([[action objectForKey: @"actionType"] isEqualToString: @"notification"]) {
                        NSDictionary *data = action[@"data"];
                        
                        // NOTIFICATIONS
                        if (data != nil && data[@"checklist"] != nil && [data[@"checklist"][@"popupType"] isEqualToString:@"widget"]) {
                            [Gleap openChecklist: data[@"checklist"][@"id"] andShowBackButton: YES];
                        } else {
                            if (!self.disableInAppNotifications) {
                                [GleapUIOverlayHelper showNotification:action];
                            }
                        }
                    } else if ([[action objectForKey: @"actionType"] isEqualToString: @"banner"]) {
                        // BANNER
                        [GleapUIOverlayHelper showBanner: action];
                    } else if ([[action objectForKey: @"actionType"] isEqualToString: @"modal"]) {
                        // MODAL
                        [GleapUIOverlayHelper showModal: action];
                    } else {
                        // FEEDBACK FORMS
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
        }
        
        int unreadCount = [[actionData objectForKey: @"u"] intValue];
        [GleapUIOverlayHelper updateNotificationCount: unreadCount];
    }
    @catch(id exception) {}
}

- (NSString *)getCurrentJSDate {
    return [GleapUIHelper getJSStringForNSDate: [[NSDate alloc] init]];
}


- (void)clear {
    @synchronized (self) {
        self.log = [[NSMutableArray alloc] init];
        self.streamedLog = [[NSMutableArray alloc] init];
    }
    
    // Also forget where the pings stand: no backoff, and the answer to a ping in flight is ignored.
    void (^resetPings)(void) = ^{
        self.pingInFlight = 0;
        [self.pingBackoff reset];
    };
    if ([NSThread isMainThread]) {
        resetPings();
    } else {
        dispatch_async(dispatch_get_main_queue(), resetPings);
    }
}

@end
