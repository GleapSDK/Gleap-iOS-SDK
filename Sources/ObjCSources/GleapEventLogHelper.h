//
//  GleapEventLogHelper.h
//  Gleap
//
//  Created by Lukas Boehler on 15.01.21.
//
//  Internal to the Gleap SDK. This header is only public because every header in
//  Sources/ObjCSources is; it is not part of the supported API and may change without
//  notice. Use the Gleap class (GleapCore.h) instead.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "GleapAction.h"

NS_ASSUME_NONNULL_BEGIN

@interface GleapEventLogHelper : NSObject

/**
 * Returns the shared instance of GleapEventLogHelper.
 * @author Gleap
 *
 * @return The shared instance of GleapEventLogHelper.
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
