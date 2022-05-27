//
//  GleapCustomDataHelper.m
//  
//
//  Created by Lukas Boehler on 27.05.22.
//

#import "GleapCustomDataHelper.h"

@implementation GleapCustomDataHelper

/*
 Returns a shared instance (singleton).
 */
+ (instancetype)sharedInstance
{
    static GleapCustomDataHelper *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GleapCustomDataHelper alloc] init];
    });
    return sharedInstance;
}

- (id)init {
    self = [super init];
    if (self) {
        self.customData = [[NSMutableDictionary alloc] init];
    }
    return self;
}

/*
 Attaches custom data, which can be viewed in the Gleap dashboard. New data will be merged with existing custom data.
 */
+ (void)attachCustomData: (NSDictionary *)customData {
    [[GleapCustomDataHelper sharedInstance].customData addEntriesFromDictionary: customData];
}

/*
 Clears all custom data.
 */
+ (void)clearCustomData {
    [[GleapCustomDataHelper sharedInstance].customData removeAllObjects];
}

/**
 * Attach one key value pair to existing custom data.
 */
+ (void)setCustomData: (NSString *)value forKey: (NSString *)key {
    [[GleapCustomDataHelper sharedInstance].customData setObject: value forKey: key];
}

/**
 * Removes one key from existing custom data.
 */
+ (void)removeCustomDataForKey: (NSString *)key {
    [[GleapCustomDataHelper sharedInstance].customData removeObjectForKey: key];
}

+ (NSDictionary *)getCustomData {
    return [[[GleapCustomDataHelper sharedInstance] customData] copy];
}

@end
