//
//  GleapWebSocketHelper.h
//  
//
//  Created by Lukas Boehler on 29.09.23.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

API_AVAILABLE(ios(13.0))
@interface GleapWebSocketHelper : NSObject
@property (strong, nonatomic, nullable) NSURLSessionWebSocketTask *webSocketTask;

+ (instancetype)sharedInstance API_AVAILABLE(ios(13.0));
- (BOOL)connectToURL:(NSURL *)url API_AVAILABLE(ios(13.0));

@property (nonatomic, retain) NSTimer* pingTimer;
@property (nonatomic, retain) NSURL* reconnectURL;
@property (nonatomic) bool connected;

@end

NS_ASSUME_NONNULL_END
