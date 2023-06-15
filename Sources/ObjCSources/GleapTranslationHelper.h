//
//  GleapTranslationHelper.h
//  Gleap
//
//  Created by Lukas Boehler on 17.02.21.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapTranslationHelper : NSObject

+ (instancetype)sharedInstance;
+ (void)setLanguage: (NSString *)language;

@property (nonatomic, retain) NSString* language;

@end

NS_ASSUME_NONNULL_END
