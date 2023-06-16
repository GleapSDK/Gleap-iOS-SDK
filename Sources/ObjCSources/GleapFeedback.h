//
//  GleapFeedback.h
//  
//
//  Created by Lukas Boehler on 25.05.22.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "GleapAction.h"

NS_ASSUME_NONNULL_BEGIN

@interface GleapFeedback : NSObject

- (void)send: (void (^)(bool success, NSDictionary *data))completion;
- (NSDictionary *)getFormData;
- (void)appendData:(NSDictionary *)data;
- (void)prepareData;

@property (nonatomic, retain) NSDictionary* excludeData;
@property (nonatomic, retain) NSMutableDictionary* data;
@property (nonatomic, retain) UIImage *screenshot;
@property (nonatomic, retain, nullable) NSString *outboundId;
@property (nonatomic, retain, nullable) NSString *feedbackType;

@end

NS_ASSUME_NONNULL_END
