//
//  GleapTagHelper.h
//  
//
//  Created by Lukas Boehler on 30.01.23.
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
