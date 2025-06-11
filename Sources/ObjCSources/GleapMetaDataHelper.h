//
//  GleapMetaDataHelper.h
//  
//
//  Created by Lukas Boehler on 25.05.22.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#define SDK_VERSION @"14.6.4"

NS_ASSUME_NONNULL_BEGIN

@interface GleapMetaDataHelper : NSObject

+ (instancetype)sharedInstance;

- (void)startSession;
- (double)sessionDuration;
- (void)updateLastScreenName;
- (NSDictionary *)getMetaData;

@property (retain, nonatomic) NSDate *sessionStart;
@property (retain, nonatomic) NSString *lastScreenName;

@end

NS_ASSUME_NONNULL_END
