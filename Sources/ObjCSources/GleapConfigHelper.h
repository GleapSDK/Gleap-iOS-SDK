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
/**
 * Re-applies the active color scheme to the raw config. When the resulting
 * background changes, pushes the config to an open widget and refreshes the
 * native UI (notifications, widget background). Call on the main thread.
 */
- (void)refreshColorScheme;
- (int)getButtonX;
- (int)getButtonY;

/**
 * The flow config with the active color scheme applied (see GleapThemeHelper).
 */
@property (nonatomic, retain) NSDictionary* config;

/**
 * The flow config as delivered by the server.
 */
@property (nonatomic, retain, nullable) NSDictionary* rawConfig;
@property (nonatomic, retain) NSDictionary* projectActions;

@end

NS_ASSUME_NONNULL_END
