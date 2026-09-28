//
//  GleapReplayHelper.h
//  Gleap
//
//  Created by Lukas Boehler on 15.01.21.
//
//  Internal to the Gleap SDK. This header is only public because every header in
//  Sources/ObjCSources is; it is not part of the supported API and may change without
//  notice. Use the Gleap class (GleapCore.h) instead.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapReplayHelper : NSObject

/**
 * Returns the shared instance of GleapReplayHelper.
 * @author Gleap
 *
 * @return The shared instance of GleapReplayHelper.
 */
+ (instancetype)sharedInstance;

- (void)start;
- (void)stop;
- (void)clear;

@property (nonatomic, retain) NSMutableArray* replaySteps;
@property (nonatomic, retain) NSTimer* replayTimer;
@property (nonatomic, retain) NSString* lastPageName;
@property (nonatomic, assign) bool running;
@property (nonatomic, assign) int timerInterval;

@end

NS_ASSUME_NONNULL_END
