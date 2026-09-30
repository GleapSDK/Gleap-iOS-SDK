//
//  GleapTagHelper.h
//  
//
//  Created by Lukas Boehler on 30.01.23.
//
//  Internal to the Gleap SDK. This header is only public because every header in
//  Sources/ObjCSources is; it is not part of the supported API and may change without
//  notice. Use the Gleap class (GleapCore.h) instead.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapTagHelper : NSObject

+ (instancetype)sharedInstance;

+ (NSArray *)getTags;
+ (void)setTags: (NSArray *)tags;

@property (retain, nonatomic) NSArray *tags;

@end

NS_ASSUME_NONNULL_END
