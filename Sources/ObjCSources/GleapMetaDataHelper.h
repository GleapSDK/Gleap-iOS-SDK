//
//  GleapMetaDataHelper.h
//  
//
//  Created by Lukas Boehler on 25.05.22.
//
//  Internal to the Gleap SDK. This header is only public because every header in
//  Sources/ObjCSources is; it is not part of the supported API and may change without
//  notice. Use the Gleap class (GleapCore.h) instead.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#define SDK_VERSION @"19.2.0"

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
