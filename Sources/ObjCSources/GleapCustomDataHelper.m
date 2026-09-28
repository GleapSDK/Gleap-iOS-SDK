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
        self.ticketAttributeData = [[NSMutableDictionary alloc] init];
    }
    return self;
}

// The app (and the wrappers, often off the main thread) change custom data and ticket
// attributes while a report copies them; every access goes through the shared instance's lock.

/*
 Attaches custom data, which can be viewed in the Gleap dashboard. New data will be merged with existing custom data.
 */
+ (void)attachCustomData: (NSDictionary *)customData {
    GleapCustomDataHelper *helper = [GleapCustomDataHelper sharedInstance];
    @synchronized (helper) {
        [helper.customData addEntriesFromDictionary: customData];
    }
}

/*
 Clears all custom data.
 */
+ (void)clearCustomData {
    GleapCustomDataHelper *helper = [GleapCustomDataHelper sharedInstance];
    @synchronized (helper) {
        [helper.customData removeAllObjects];
    }
}

/**
 * Attach one key value pair to existing custom data.
 */
+ (void)setCustomData: (NSString *)value forKey: (NSString *)key {
    GleapCustomDataHelper *helper = [GleapCustomDataHelper sharedInstance];
    @synchronized (helper) {
        [helper.customData setObject: value forKey: key];
    }
}

+ (void)setTicketAttributeWithKey:(NSString *)key value:(id)value {
    GleapCustomDataHelper *helper = [GleapCustomDataHelper sharedInstance];
    @synchronized (helper) {
        @try {
            [helper.ticketAttributeData setObject: value forKey: key];
        } @catch (id exp) {}
    }
}

+ (void)unsetTicketAttributeWithKey:(NSString *)key {
    GleapCustomDataHelper *helper = [GleapCustomDataHelper sharedInstance];
    @synchronized (helper) {
        @try {
            [helper.ticketAttributeData removeObjectForKey: key];
        } @catch (id exp) {}
    }
}

+ (void)clearTicketAttributes {
    GleapCustomDataHelper *helper = [GleapCustomDataHelper sharedInstance];
    @synchronized (helper) {
        @try {
            [helper.ticketAttributeData removeAllObjects];
        } @catch (NSException *exception) {}
    }
}

/**
 * Removes one key from existing custom data.
 */
+ (void)removeCustomDataForKey: (NSString *)key {
    GleapCustomDataHelper *helper = [GleapCustomDataHelper sharedInstance];
    @synchronized (helper) {
        [helper.customData removeObjectForKey: key];
    }
}

+ (NSDictionary *)getCustomData {
    GleapCustomDataHelper *helper = [GleapCustomDataHelper sharedInstance];
    @synchronized (helper) {
        return [helper.customData copy];
    }
}

+ (NSDictionary *)getTicketAttributes {
    GleapCustomDataHelper *helper = [GleapCustomDataHelper sharedInstance];
    @synchronized (helper) {
        return [helper.ticketAttributeData copy];
    }
}

@end
