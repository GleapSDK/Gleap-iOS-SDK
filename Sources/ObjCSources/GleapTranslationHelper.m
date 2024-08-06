//
//  GleapTranslationHelper.m
//  Gleap
//
//  Created by Lukas Boehler on 17.02.21.
//

#import "GleapTranslationHelper.h"
#import "GleapWidgetManager.h"
#import "GleapConfigHelper.h"

@implementation GleapTranslationHelper

/*
 Returns a shared instance (singleton).
 */
+ (instancetype)sharedInstance
{
    static GleapTranslationHelper *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GleapTranslationHelper alloc] init];
    });
    return sharedInstance;
}

- (id)init {
    self = [super init];
    if (self) {
        self.language = [[NSLocale preferredLanguages] firstObject];
        if (self.language != nil) {
            self.language = [self.language lowercaseString];
        }
    }
    return self;
}

+ (void)setLanguage: (NSString *)language {
    [GleapTranslationHelper sharedInstance].language = language;
    
    // Update widget config
    [[GleapWidgetManager sharedInstance] sendConfigUpdate];
}

@end
