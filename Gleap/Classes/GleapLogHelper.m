//
//  GleapReplayHelper.m
//  Gleap
//
//  Created by Lukas Boehler on 15.01.21.
//

#import "GleapLogHelper.h"
#import "GleapCore.h"

@implementation GleapLogHelper

/*
 Returns a shared instance (singleton).
 */
+ (instancetype)sharedInstance
{
    static GleapLogHelper *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GleapLogHelper alloc] init];
    });
    return sharedInstance;
}

- (id)init {
    self = [super init];
    if (self) {
        [self initHelper];
    }
    return self;
}

- (void)initHelper {
    self.log = [[NSMutableArray alloc] init];
}

- (NSArray *)getLogs {
    return self.log;
}

- (void)checkLogSize {
    if (self.log.count >= 1000) {
        [self.log removeObjectAtIndex: 0];
    }
}

- (void)logEvent: (NSString *)name {
    [self checkLogSize];
    [self.log addObject: @{
        @"name": name,
        @"date": [self getCurrentJSDate]
    }];
}

- (void)logEvent: (NSString *)name withData: (NSDictionary *)data {
    [self checkLogSize];
    [self.log addObject: @{
        @"name": name,
        @"data": data,
        @"date": [self getCurrentJSDate]
    }];
}

- (NSString *)getCurrentJSDate {
    return [[Gleap sharedInstance] getJSStringForNSDate: [[NSDate alloc] init]];
}


- (void)clear {
    self.log = [[NSMutableArray alloc] init];
}

@end
