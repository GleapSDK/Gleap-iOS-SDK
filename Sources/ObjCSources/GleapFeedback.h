//
//  GleapFeedback.h
//  
//
//  Created by Lukas Boehler on 25.05.22.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapFeedback : NSObject

- (void)send: (void (^)(bool success))completion;
- (NSDictionary *)getFormData;

@property (nonatomic, retain) NSDictionary* excludeData;
@property (nonatomic, retain) NSMutableDictionary* data;

@end

NS_ASSUME_NONNULL_END
