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
    }
    return self;
}

+ (void)setLanguage: (NSString *)language {
    [GleapTranslationHelper sharedInstance].language = language;
    
    // Update widget config
    [[GleapWidgetManager sharedInstance] sendConfigUpdate];
}

+ (NSString *)localizedString:(NSString *)string {
    NSMutableDictionary *translation = [[NSMutableDictionary alloc] init];
    
    NSDictionary *config = GleapConfigHelper.sharedInstance.config;
    if (config != nil) {
        NSDictionary *configCustomTranslations = [config objectForKey: @"customTranslations"];
        if (configCustomTranslations != nil) {
            NSString *lang = [[GleapTranslationHelper sharedInstance].language lowercaseString];
            NSDictionary *customTranslationTable = [configCustomTranslations objectForKey: lang];
            if (customTranslationTable != nil) {
                [translation addEntriesFromDictionary: customTranslationTable];
            }
            
            // Try extended search.
            if (lang.length > 2 && customTranslationTable == nil) {
                lang = [lang substringToIndex: 2];
                NSDictionary *extendedCustomTranslationTable = [configCustomTranslations objectForKey: lang];
                if (extendedCustomTranslationTable != nil) {
                    [translation addEntriesFromDictionary: extendedCustomTranslationTable];
                }
            }
        }
    }
    
    NSString *translatedString = [translation objectForKey: string];
    if (translatedString != nil) {
        return translatedString;
    }
    
    return string;
}

@end
