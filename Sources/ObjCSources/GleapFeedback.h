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
- (void)prepareMainThreadData;
- (void)prepareBackgroundData;

/**
 Collects the report and calls `completion` on the main thread as soon as it is
 ready, or after `deadline` seconds — whichever comes first. Must be called from
 the main thread.

 Console logs are the only slow part (OSLogStore can block for well over a
 second on a real device); everything else is in-memory and is always present by
 the time `completion` runs. When the logs miss the deadline they are simply left
 out. Use this whenever a late reply costs more than missing console logs — the
 widget, for one, discards the entire payload if the reply arrives too late.
 */
- (void)prepareDataWithDeadline:(NSTimeInterval)deadline completion:(void (^)(void))completion;

@property (nonatomic, retain) NSDictionary* excludeData;
@property (nonatomic, retain) NSMutableDictionary* data;
@property (nonatomic, retain) UIImage *screenshot;
@property (nonatomic, retain, nullable) NSString *outboundId;
@property (nonatomic, retain, nullable) NSString *feedbackType;

@end

NS_ASSUME_NONNULL_END
