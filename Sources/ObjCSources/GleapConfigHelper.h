//
//  GleapConfigHelper.h
//  
//
//  Created by Lukas Boehler on 25.05.22.
//
//  Internal to the Gleap SDK. This header is only public because every header in
//  Sources/ObjCSources is; it is not part of the supported API and may change without
//  notice. Use the Gleap class (GleapCore.h) instead.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapConfigHelper : NSObject

+ (instancetype)sharedInstance;
- (void)run;

/**
 * Fetches the widget config again for an already running SDK — used when the
 * language changes after initialization, since all copy in the config is
 * translated server-side at load time, and when a session is recovered. Applies
 * the config and pushes it to an open widget. The initialized / configLoaded
 * delegate calls happen once per initialize; a reload only makes them when the
 * config has not loaded since (for example after an offline start).
 */
- (void)reload;
/**
 * Re-applies the active color scheme to the raw config. When the resulting
 * config changes (palette, logo, header image, composer glow), pushes it to an
 * open widget and refreshes the native UI (widget background and loading view,
 * notifications, a showing modal). Call on the main thread.
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
