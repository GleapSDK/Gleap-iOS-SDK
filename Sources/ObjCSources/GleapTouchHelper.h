//
//  GleapTouchHelper.h
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

@interface GleapTouchHelper : NSObject

/**
 * Returns the shared instance of GleapTouchHelper.
 * @author Gleap
 *
 * @return The shared instance of GleapTouchHelper.
 */
+ (instancetype)sharedInstance;

/**
 * Starts the touch helper.
 */
+ (void)addX:(float)x andY:(float)y andType:(NSString *)type;

/**
 * Returns all touch events and clears the touch events array.
 */
+ (NSArray *)getAndClearTouchEvents;

@property (nonatomic, retain) NSMutableArray* touchEvents;

@end

NS_ASSUME_NONNULL_END
