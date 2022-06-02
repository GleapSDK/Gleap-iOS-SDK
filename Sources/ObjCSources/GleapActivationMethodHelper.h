//
//  GleapActivationMethodHelper.h
//  
//
//  Created by Lukas Boehler on 27.05.22.
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
