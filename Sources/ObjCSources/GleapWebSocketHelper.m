//
//  GleapWebSocketHelper.m
//
//
//  Created by Lukas Boehler on 29.09.23.
//
//  The realtime socket. All of its state lives on the main queue (a serial queue), where the
//  socket's answers, the timers and the app lifecycle notifications arrive; calls from other
//  threads hop over to it.
//
//  - connectToURL: only asks for the channel. The socket opens 1.5 s after the last ask, so a
//    session start followed right away by an identify opens one socket, and an ask for the
//    channel that is already open (or opening) keeps that socket.
//  - The SDK closes its sockets with a close code: 1000 (normal) when it replaces one, 1001
//    (going away) when the app stays in the background.
//  - After an error it reconnects with a growing delay (GleapWebSocketPolicy: 2 s up to 60 s,
//    ±20 %), which starts over once a socket received a message or stayed open for 30 s.
//  - In the background (after a 10 s grace) and while offline there is no socket and no
//    reconnect; returning to the foreground or getting back online connects again.
//

#import "GleapWebSocketHelper.h"
#import "GleapEventLogHelper.h"
#import "GleapCaptureManager.h"
#import "GleapWebSocketPolicy.h"
#import <UIKit/UIKit.h>
#import <Network/Network.h>

static NSTimeInterval const kGleapSocketPingInterval = 40.0;
static NSTimeInterval const kGleapSocketConnectDebounce = 1.5;
static NSTimeInterval const kGleapSocketBackgroundGrace = 10.0;

static void GleapOnMain(dispatch_block_t block) {
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

@interface GleapWebSocketHelper ()
// One session for all connections; a session per connection was never invalidated. Messages
// arrive on the main queue, like the answers to the HTTP event stream.
@property (nonatomic, strong) NSURLSession *urlSession;
// The channel of the socket in webSocketTask (reconnectURL is the channel that is wanted).
@property (nonatomic, strong, nullable) NSURL *currentURL;
// Bumped by every scheduled connect: only the latest one runs.
@property (nonatomic, assign) NSUInteger connectGeneration;
// Failed connections in a row, for the reconnect delay.
@property (nonatomic, assign) NSInteger reconnectFailures;
// When the current socket was opened (system uptime) and whether it received a message.
@property (nonatomic, assign) NSTimeInterval openedAt;
@property (nonatomic, assign) BOOL receivedMessage;
@property (nonatomic, assign) BOOL inBackground;
@property (nonatomic, assign) BOOL online;
// Bumped when the app enters or leaves the background: only the latest grace close runs.
@property (nonatomic, assign) NSUInteger backgroundGeneration;
@property (nonatomic, assign) UIBackgroundTaskIdentifier backgroundTask;
@property (nonatomic, strong, nullable) nw_path_monitor_t pathMonitor;
@end

@implementation GleapWebSocketHelper

+ (instancetype)sharedInstance {
    static GleapWebSocketHelper *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GleapWebSocketHelper alloc] init];
        [sharedInstance initialSetup];
    });
    return sharedInstance;
}

- (void)initialSetup {
    self.urlSession = [NSURLSession sessionWithConfiguration: NSURLSessionConfiguration.defaultSessionConfiguration
                                                   delegate: nil
                                              delegateQueue: [NSOperationQueue mainQueue]];
    self.online = YES;
    self.backgroundTask = UIBackgroundTaskInvalid;

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver: self selector: @selector(appDidEnterBackground) name: UIApplicationDidEnterBackgroundNotification object: nil];
    [center addObserver: self selector: @selector(appWillEnterForeground) name: UIApplicationWillEnterForegroundNotification object: nil];
    [center addObserver: self selector: @selector(appWillEnterForeground) name: UIApplicationDidBecomeActiveNotification object: nil];

    GleapOnMain(^{
        // An app launched in the background (a push, a background fetch) opens no socket until it
        // comes to the foreground.
        UIApplication *application = [UIApplication sharedApplication];
        if (application != nil && application.applicationState == UIApplicationStateBackground) {
            self.inBackground = YES;
        }
    });

    [self startPathMonitor];
}

#pragma mark - Connecting

- (BOOL)connectToURL:(NSURL *)url {
    GleapOnMain(^{
        self.reconnectURL = url;
        [self scheduleConnectAfter: kGleapSocketConnectDebounce];
    });
    return YES;
}

- (void)scheduleConnectAfter:(NSTimeInterval)delay {
    NSUInteger generation = ++self.connectGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != self.connectGeneration) {
            return;
        }
        [self connectIfNeeded];
    });
}

- (BOOL)socketAlive {
    if (self.webSocketTask == nil) {
        return NO;
    }
    NSURLSessionTaskState state = self.webSocketTask.state;
    return state == NSURLSessionTaskStateRunning || state == NSURLSessionTaskStateSuspended;
}

- (void)connectIfNeeded {
    GleapWebSocketAction action = [GleapWebSocketPolicy actionForDesiredURL: self.reconnectURL
                                                                 currentURL: self.currentURL
                                                                socketAlive: [self socketAlive]
                                                               inBackground: self.inBackground
                                                                     online: self.online];
    if (action != GleapWebSocketActionConnect) {
        return;
    }

    [self closeWithCode: NSURLSessionWebSocketCloseCodeNormalClosure reason: @"reconnect"];

    NSURL *url = self.reconnectURL;
    NSURLSessionWebSocketTask *task = [self.urlSession webSocketTaskWithURL: url];
    self.webSocketTask = task;
    self.currentURL = url;
    self.openedAt = NSProcessInfo.processInfo.systemUptime;
    self.receivedMessage = NO;
    [task resume];
    [self startPingTimer];
    [self sendPingPong];
    [self receiveMessageFromTask: task];
}

- (void)closeWithCode:(NSURLSessionWebSocketCloseCode)code reason:(NSString *)reason {
    NSURLSessionWebSocketTask *task = self.webSocketTask;
    // Cleared first: the closed socket's pending receive then sees it was replaced and stops.
    self.webSocketTask = nil;
    self.currentURL = nil;
    self.connected = NO;
    [self stopPingTimer];
    if (task != nil) {
        [task cancelWithCloseCode: code reason: [reason dataUsingEncoding: NSUTF8StringEncoding]];
    }
}

#pragma mark - Ping

- (void)startPingTimer {
    [self.pingTimer invalidate];
    self.pingTimer = [NSTimer scheduledTimerWithTimeInterval: kGleapSocketPingInterval
                                                      target: self
                                                    selector: @selector(sendPingPong)
                                                    userInfo: nil
                                                     repeats: YES];
}

- (void)stopPingTimer {
    [self.pingTimer invalidate];
}

- (void)sendPingPong {
    NSURLSessionWebSocketTask *task = self.webSocketTask;
    if (task != nil && task.state == NSURLSessionTaskStateRunning) {
        [task sendPingWithPongReceiveHandler:^(NSError * _Nullable error) {
            GleapOnMain(^{
                if (task != self.webSocketTask) {
                    return;
                }
                if (error != nil) {
                    self.connected = NO;
                } else if (self.connected == NO) {
                    self.connected = YES;

                    // We got connected, send events.
                    [[GleapEventLogHelper sharedInstance] sendEventStreamToServer];
                }
            });
        }];
    }
}

#pragma mark - Receiving

- (void)receiveMessageFromTask:(NSURLSessionWebSocketTask *)task {
    [task receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage * _Nullable message, NSError * _Nullable error) {
        GleapOnMain(^{
            [self handleMessage: message error: error fromTask: task];
        });
    }];
}

- (void)handleMessage:(NSURLSessionWebSocketMessage *)message error:(NSError *)error fromTask:(NSURLSessionWebSocketTask *)task {
    // A connection that was replaced or closed in the meantime is done. Its cancellation used
    // to count as a failure and reconnect, which replaced the current connection in turn and
    // kept the SDK reconnecting every 5 seconds.
    if (task != self.webSocketTask) {
        return;
    }

    if (error) {
        [self reconnectAfterFailure];
        return;
    }

    self.receivedMessage = YES;
    self.reconnectFailures = 0;

    // Process message.
    if (message.type == NSURLSessionWebSocketMessageTypeString) {
        if (message.string) {
            NSData *data = [message.string dataUsingEncoding:NSUTF8StringEncoding];

            @try {
                NSError *jsonError;
                NSDictionary *parsedData = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];

                if (jsonError == nil) {
                    NSString *eventName = [parsedData objectForKey: @"name"];
                    if ([eventName isEqualToString: @"update"]) {
                        [[GleapEventLogHelper sharedInstance] parseUpdate: [parsedData objectForKey: @"data"]];
                    } else if ([eventName isEqualToString: @"capture-request"]) {
                        // A background log request; handled whether the widget is open or not.
                        [[GleapCaptureManager sharedInstance] handleCaptureRequests: [parsedData objectForKey: @"data"]];
                    }
                }
            }
            @catch (NSException *exception) {}
        }
    }

    // Receive the next message.
    [self receiveMessageFromTask: task];
}

- (void)reconnectAfterFailure {
    NSTimeInterval openFor = NSProcessInfo.processInfo.systemUptime - self.openedAt;
    if ([GleapWebSocketPolicy shouldResetBackoffAfterOpenFor: openFor receivedMessage: self.receivedMessage]) {
        self.reconnectFailures = 0;
    }
    self.reconnectFailures++;

    [self closeWithCode: NSURLSessionWebSocketCloseCodeNormalClosure reason: @"error"];

    // In the background or offline the scheduled connect does nothing; the return to the
    // foreground or the network connects again.
    NSTimeInterval delay = [GleapWebSocketPolicy reconnectDelayAfterFailures: self.reconnectFailures
                                                                      random: (double)arc4random_uniform(UINT32_MAX) / (double)UINT32_MAX];
    [self scheduleConnectAfter: delay];
}

#pragma mark - App lifecycle

- (void)appDidEnterBackground {
    GleapOnMain(^{
        if (self.inBackground) {
            return;
        }
        self.inBackground = YES;
        // No connect while in the background.
        self.connectGeneration++;

        NSUInteger generation = ++self.backgroundGeneration;
        if (self.webSocketTask == nil) {
            return;
        }

        // Keep the socket for a short grace (the user often comes right back), then close it
        // cleanly. The background task gives the app the time to send the close frame.
        [self endBackgroundTask];
        UIApplication *application = [UIApplication sharedApplication];
        if (application != nil) {
            self.backgroundTask = [application beginBackgroundTaskWithName: @"Gleap socket close" expirationHandler:^{
                [self closeWithCode: NSURLSessionWebSocketCloseCodeGoingAway reason: @"background"];
                [self endBackgroundTask];
            }];
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kGleapSocketBackgroundGrace * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (generation != self.backgroundGeneration || !self.inBackground) {
                return;
            }
            [self closeWithCode: NSURLSessionWebSocketCloseCodeGoingAway reason: @"background"];
            [self endBackgroundTask];
        });
    });
}

- (void)appWillEnterForeground {
    GleapOnMain(^{
        if (!self.inBackground) {
            return;
        }
        self.inBackground = NO;
        // Cancels a pending grace close: a socket that is still open stays.
        self.backgroundGeneration++;
        [self endBackgroundTask];

        if (self.reconnectURL != nil) {
            [self scheduleConnectAfter: kGleapSocketConnectDebounce];
        }
    });
}

- (void)endBackgroundTask {
    if (self.backgroundTask != UIBackgroundTaskInvalid) {
        UIBackgroundTaskIdentifier task = self.backgroundTask;
        self.backgroundTask = UIBackgroundTaskInvalid;
        [[UIApplication sharedApplication] endBackgroundTask: task];
    }
}

#pragma mark - Network

- (void)startPathMonitor {
    nw_path_monitor_t monitor = nw_path_monitor_create();
    nw_path_monitor_set_queue(monitor, dispatch_get_main_queue());
    __weak GleapWebSocketHelper *weakSelf = self;
    nw_path_monitor_set_update_handler(monitor, ^(nw_path_t _Nonnull path) {
        [weakSelf networkChanged: nw_path_get_status(path) == nw_path_status_satisfied];
    });
    nw_path_monitor_start(monitor);
    self.pathMonitor = monitor;
}

- (void)networkChanged:(BOOL)online {
    BOOL wasOnline = self.online;
    self.online = online;
    if (online && !wasOnline && self.reconnectURL != nil && ![self socketAlive]) {
        // Failures while offline say nothing about the server.
        self.reconnectFailures = 0;
        [self scheduleConnectAfter: kGleapSocketConnectDebounce];
    }
}

@end
