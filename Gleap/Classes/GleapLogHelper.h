//
//  GleapReplayHelper.h
//  Gleap
//
//  Created by Lukas Boehler on 15.01.21.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapLogHelper : NSObject

/**
 * Returns a new shared instance of GleapReplayHelper.
 * @author Gleap
 *
 * @return A new shared instance of GleapReplayHelper.
 */
+ (instancetype)sharedInstance;

- (void)logEvent: (NSString *)name;
- (void)logEvent: (NSString *)name withData: (NSDictionary *)data;
- (void)clear;
- (NSArray *)getLogs;

@property (nonatomic, retain) NSMutableArray* log;

@end

NS_ASSUME_NONNULL_END
