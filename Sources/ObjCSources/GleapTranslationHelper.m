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
    NSString *previousLanguage = [GleapTranslationHelper sharedInstance].language;
    [GleapTranslationHelper sharedInstance].language = language;

    BOOL languageChanged = language != nil && [language caseInsensitiveCompare: previousLanguage ?: @""] != NSOrderedSame;

    // The config is fetched once during initialize() and carries all copy already
    // translated by the server (reply times, out-of-office notice, ...). Pushing
    // the cached config to the widget would therefore keep the previous language
    // forever — fetch it again instead. `reload` sends the config update itself
    // once the fresh copy arrives. Before initialize() there is nothing to
    // reload: the regular config load picks the language up on its own.
    if (languageChanged && [GleapConfigHelper sharedInstance].config != nil) {
        [[GleapConfigHelper sharedInstance] reload];
        return;
    }

    // Update widget config
    [[GleapWidgetManager sharedInstance] sendConfigUpdate];
}

@end
