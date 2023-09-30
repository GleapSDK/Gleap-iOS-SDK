//
//  GleapReplayHelper.h
//  Gleap
//
//  Created by Lukas Boehler on 15.01.21.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "GleapAction.h"

NS_ASSUME_NONNULL_BEGIN

@interface GleapEventLogHelper : NSObject

/**
 * Returns a new shared instance of GleapReplayHelper.
 * @author Gleap
 *
 * @return A new shared instance of GleapReplayHelper.
 */
+ (instancetype)sharedInstance;

- (void)start;
- (void)stop;
- (void)logEvent: (NSString *)name;
- (void)logEvent: (NSString *)name withData: (NSDictionary *)data;
- (void)clear;
- (void)parseUpdate:(NSDictionary *)actionData;
- (void)sendEventStreamToServer;
- (NSArray *)getLogs;

@property (nonatomic, retain) NSMutableArray* log;
@property (nonatomic, assign) bool disableInAppNotifications;
@property (nonatomic, assign) bool webSocketEnabled;
@property (nonatomic, retain) NSMutableArray* streamedLog;
@property (nonatomic, retain) NSString* lastPageName;
@property (nonatomic, retain) NSTimer* pageNameTimer;
@property (nonatomic, retain, nullable) NSTimer* eventStreamTimer;

@end

NS_ASSUME_NONNULL_END
