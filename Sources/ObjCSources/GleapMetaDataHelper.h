//
//  GleapMetaDataHelper.h
//  
//
//  Created by Lukas Boehler on 25.05.22.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#define SDK_VERSION @"18.2.0"

NS_ASSUME_NONNULL_BEGIN

@interface GleapMetaDataHelper : NSObject

+ (instancetype)sharedInstance;

- (void)startSession;
- (double)sessionDuration;
- (void)updateLastScreenName;
- (NSDictionary *)getMetaData;

@property (retain, nonatomic) NSDate *sessionStart;
@property (retain, nonatomic) NSString *lastScreenName;
@property (copy, nonatomic, nullable) NSArray *envDataPropsToIgnore;
@property (assign, nonatomic) BOOL envDataDisabled;

@end

NS_ASSUME_NONNULL_END
