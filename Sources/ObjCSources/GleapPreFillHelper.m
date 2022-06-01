//
//  GleapPreFillHelper.m
//  
//
//  Created by Lukas Boehler on 01.06.22.
//

#import "GleapPreFillHelper.h"

@implementation GleapPreFillHelper

/*
 Returns a shared instance (singleton).
 */
+ (instancetype)sharedInstance
{
    static GleapPreFillHelper *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GleapPreFillHelper alloc] init];
    });
    return sharedInstance;
}

- (id)init {
    self = [super init];
    if (self) {
        self.preFillData = [[NSMutableDictionary alloc] init];
    }
    return self;
}

@end
