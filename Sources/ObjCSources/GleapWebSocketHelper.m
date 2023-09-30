//
//  GleapWebSocketHelper.m
//
//
//  Created by Lukas Boehler on 29.09.23.
//

#import "GleapWebSocketHelper.h"
#import "GleapEventLogHelper.h"

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
    if (@available(iOS 13.0, *)) {
        [self disconnect];
        
        NSURLSession *urlSession = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration];
        self.webSocketTask = [urlSession webSocketTaskWithURL:url];
        self.reconnectURL = url;
        [self.webSocketTask resume];
        [self sendPingPong];
        [self receiveMessage];
        return YES;
    } else {
        return NO;
    }
}

- (void)disconnect {
    if (self.webSocketTask != nil) {
        [self.webSocketTask cancel];
        self.webSocketTask = nil;
    }
    
    self.connected = NO;
}

- (void)receiveMessage API_AVAILABLE(ios(13.0)) {
    [self.webSocketTask receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage * _Nullable message, NSError * _Nullable error) {
        if (error) {
            [self handleReconnect: error];
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
                        }
                    }
                }
                @catch (NSException *exception) {}
            }
        }
        
        // Recieve next message.
        [self receiveMessage];
    }];
}

- (void)handleReconnect:(NSError *)error API_AVAILABLE(ios(13.0)) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self connectToURL: self.reconnectURL];
    });
}

@end
