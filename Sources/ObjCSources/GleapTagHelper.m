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

// The property is nonatomic; reading it while another thread replaces it can use a released array.
+ (NSArray *)getTags {
    GleapTagHelper *helper = [GleapTagHelper sharedInstance];
    @synchronized (helper) {
        return helper.tags;
    }
}

/*
 Replaces the tags that are attached to new tickets.
 */
+ (void)setTags: (NSArray *)tags {
    GleapTagHelper *helper = [GleapTagHelper sharedInstance];
    @synchronized (helper) {
        helper.tags = [tags copy];
    }
}

@end
