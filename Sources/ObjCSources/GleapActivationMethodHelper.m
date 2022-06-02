//
//  GleapActivationMethodHelper.m
//  
//
//  Created by Lukas Boehler on 27.05.22.
//

#import "GleapActivationMethodHelper.h"

@implementation GleapActivationMethodHelper

/*
 Returns a shared instance (singleton).
 */
+ (instancetype)sharedInstance
{
    static GleapActivationMethodHelper *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GleapActivationMethodHelper alloc] init];
    });
    return sharedInstance;
}

- (id)init {
    self = [super init];
    if (self) {
        self.activationMethods = [[NSMutableArray alloc] init];
        self.disableAutoActivationMethods = NO;
    }
    return self;
}

+ (BOOL)useAutoActivationMethods {
    return ![GleapActivationMethodHelper sharedInstance].disableAutoActivationMethods && [GleapActivationMethodHelper sharedInstance].activationMethods.count == 0;
}

/**
 Check if activation method exists
 */
+ (BOOL)isActivationMethodActive: (GleapActivationMethod)activationMethod {
    for (int i = 0; i < [GleapActivationMethodHelper sharedInstance].activationMethods.count; i++) {
        GleapActivationMethod currentActivationMethod = [[[GleapActivationMethodHelper sharedInstance].activationMethods objectAtIndex: i] intValue];
        if (currentActivationMethod == activationMethod) {
            return true;
        }
    }
    return false;
}

+ (NSArray *)getActivationMethods {
    return [GleapActivationMethodHelper sharedInstance].activationMethods;
}

+ (void)setActivationMethods: (NSArray *)activationMethods {
    [GleapActivationMethodHelper sharedInstance].activationMethods = activationMethods;
}

+ (void)setAutoActivationMethodsDisabled {
    [GleapActivationMethodHelper sharedInstance].disableAutoActivationMethods = YES;
}

@end
