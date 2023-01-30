//
//  GleapTagHelper.m
//  
//
//  Created by Lukas Boehler on 30.01.23.
//

#import "GleapTagHelper.h"

@implementation GleapTagHelper

/*
 Returns a shared instance (singleton).
 */
+ (instancetype)sharedInstance
{
    static GleapTagHelper *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GleapTagHelper alloc] init];
    });
    return sharedInstance;
}

- (id)init {
    self = [super init];
    if (self) {
        self.tags = [[NSArray alloc] init];
    }
    return self;
}

+ (NSArray *)getTags {
    return [GleapTagHelper sharedInstance].tags;
}

/*
 Attaches custom data, which can be viewed in the Gleap dashboard. New data will be merged with existing custom data.
 */
+ (void)setTags: (NSArray *)tags {
    [GleapTagHelper sharedInstance].tags = tags;
}

@end
