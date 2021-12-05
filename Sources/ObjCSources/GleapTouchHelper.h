//
//  GleapTouchHelper.h
//  Gleap
//
//  Created by Lukas Boehler on 15.01.21.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapTouchHelper : NSObject

/**
 * Returns a new shared instance of GleapTouchHelper.
 * @author Gleap
 *
 * @return A new shared instance of GleapTouchHelper.
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
