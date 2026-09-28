//
//  GleapActivationMethodHelper.h
//  
//
//  Created by Lukas Boehler on 27.05.22.
//
//  Internal to the Gleap SDK. This header is only public because every header in
//  Sources/ObjCSources is; it is not part of the supported API and may change without
//  notice. Use the Gleap class (GleapCore.h) instead.
//

#import <Foundation/Foundation.h>
#import "GleapCore.h"

NS_ASSUME_NONNULL_BEGIN

@interface GleapActivationMethodHelper : NSObject

+ (instancetype)sharedInstance;
+ (void)setActivationMethods: (NSArray *)activationMethods;
+ (BOOL)isActivationMethodActive: (GleapActivationMethod)activationMethod;
+ (NSArray *)getActivationMethods;
+ (void)setAutoActivationMethodsDisabled;
+ (BOOL)useAutoActivationMethods;

@property (nonatomic, retain) NSArray *activationMethods;
@property (nonatomic, assign) bool disableAutoActivationMethods;

@end

NS_ASSUME_NONNULL_END
