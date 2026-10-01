//
//  GleapWebSocketHelper.m
//
//
//  Created by Lukas Boehler on 29.09.23.
//

#import "GleapWebSocketHelper.h"
#import "GleapEventLogHelper.h"
#import "GleapCaptureManager.h"

@interface GleapWebSocketHelper ()
// One session for all connections; a session per connection was never invalidated. Messages
// arrive on the main queue, like the answers to the HTTP event stream.
@property (nonatomic, strong) NSURLSession *urlSession;
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
    self.pingTimer = [NSTimer scheduledTimerWithTimeInterval: 40.0
                                         target: self
                                       selector: @selector(sendPingPong)
                                       userInfo: nil
                                        repeats: YES];
}

- (void)sendPingPong {
    if (self.webSocketTask != nil && self.webSocketTask.state == NSURLSessionTaskStateRunning) {
        [self.webSocketTask sendPingWithPongReceiveHandler:^(NSError * _Nullable error) {
            if (error != nil) {
                self.connected = NO;
            } else {
                if (self.connected == NO) {
                    self.connected = YES;
                    
                    // We got connected, send events.
                    [[GleapEventLogHelper sharedInstance] sendEventStreamToServer];
                }
            }
        }];
    }
}

- (BOOL)connectToURL:(NSURL *)url {
    [self disconnect];
    
    NSURLSessionWebSocketTask *task = [self.urlSession webSocketTaskWithURL:url];
    self.webSocketTask = task;
    self.reconnectURL = url;
    [task resume];
    [self sendPingPong];
    [self receiveMessageFromTask: task];
    return YES;
}

- (void)disconnect {
    if (self.webSocketTask != nil) {
        [self.webSocketTask cancel];
        self.webSocketTask = nil;
    }
    
    self.connected = NO;
}

- (void)receiveMessageFromTask:(NSURLSessionWebSocketTask *)task {
    [task receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage * _Nullable message, NSError * _Nullable error) {
        // A connection that was replaced or closed in the meantime is done. Its cancellation used
        // to count as a failure and reconnect, which replaced the current connection in turn and
        // kept the SDK reconnecting every 5 seconds.
        if (task != self.webSocketTask) {
            return;
        }
        
        if (error) {
            [self reconnectTask: task];
            return;
        }
        
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
    }];
}

- (void)reconnectTask:(NSURLSessionWebSocketTask *)task {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // Unless something connected (or disconnected) in the meantime.
        if (task != self.webSocketTask || self.reconnectURL == nil) {
            return;
        }
        [self connectToURL: self.reconnectURL];
    });
}

@end
