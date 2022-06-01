//
//  GleapExternalDataHelper.m
//  
//
//  Created by Lukas Boehler on 31.05.22.
//

#import "GleapExternalDataHelper.h"

@implementation GleapExternalDataHelper

/*
 Returns a shared instance (singleton).
 */
+ (instancetype)sharedInstance
{
    static GleapExternalDataHelper *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GleapExternalDataHelper alloc] init];
    });
    return sharedInstance;
}

- (id)init {
    self = [super init];
    if (self) {
        self.data = [[NSMutableDictionary alloc] init];
    }
    return self;
}

@end
