//
//  GleapConfigHelper.h
//  
//
//  Created by Lukas Boehler on 25.05.22.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapConfigHelper : NSObject

+ (instancetype)sharedInstance;
- (void)run;

/**
 * Fetches the widget config again for an already running SDK — used when the
 * language changes after initialization, since all copy in the config is
 * translated server-side at load time. Applies the config and pushes it to an
 * open widget, but skips the one-time initialized / configLoaded delegate calls.
 */
- (void)reload;
- (int)getButtonX;
- (int)getButtonY;

@property (nonatomic, retain) NSDictionary* config;
@property (nonatomic, retain) NSDictionary* projectActions;

@end

NS_ASSUME_NONNULL_END
