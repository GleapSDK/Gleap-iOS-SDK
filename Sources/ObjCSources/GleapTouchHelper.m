//
//  GleapTouchHelper.m
//  Gleap
//
//  Created by Lukas Boehler on 15.01.21.
//

#import "GleapTouchHelper.h"
#import "GleapCore.h"
#import "GleapUIHelper.h"

#define MAX_INTERACTIONS 10

@implementation GleapTouchHelper

/*
 Returns a shared instance (singleton).
 */
+ (instancetype)sharedInstance
{
    static GleapTouchHelper *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GleapTouchHelper alloc] init];
    });
    return sharedInstance;
}

- (id)init {
    self = [super init];
    if (self) {
        self.touchEvents = [[NSMutableArray alloc] init];
    }
    return self;
}

+ (void)addX:(float)x andY:(float)y andType:(NSString *)type {
    [[self sharedInstance] addX: x andY: y andType: type];
}

+ (NSArray *)getAndClearTouchEvents {
    NSArray *touchEventsCopy = [[[self sharedInstance] touchEvents] copy];
    [[[self sharedInstance] touchEvents] removeAllObjects];
    return touchEventsCopy;
}

- (void)addX:(float)x andY:(float)y andType:(NSString *)type {
    if (self.touchEvents.count >= MAX_INTERACTIONS) {
        return;
    }
    
    NSDictionary *point = @{
        @"x": @(x),
        @"y": @(y),
        @"date": [GleapUIHelper getJSStringForNSDate: [[NSDate alloc] init]],
        @"type": type
    };
    [self.touchEvents addObject: point];
}

@end

