//
//  GleapTranslationHelper.h
//  Gleap
//
//  Created by Lukas Boehler on 17.02.21.
//
//  Internal to the Gleap SDK. This header is only public because every header in
//  Sources/ObjCSources is; it is not part of the supported API and may change without
//  notice. Use the Gleap class (GleapCore.h) instead.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapTranslationHelper : NSObject

+ (instancetype)sharedInstance;
+ (void)setLanguage: (NSString *)language;

@property (nonatomic, retain) NSString* language;

@end

NS_ASSUME_NONNULL_END
