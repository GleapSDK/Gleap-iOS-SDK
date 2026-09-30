//
//  GleapWidgetLoadingView.h
//  Gleap
//
//  The widget's loading screen: mirrors the messenger's home background (colour
//  header, classic diagonal, gradient blobs or image) so the hand-off to the web
//  view reads as continuous.
//

#import <UIKit/UIKit.h>
#import "GleapInternal.h"

NS_ASSUME_NONNULL_BEGIN

GLEAP_INTERNAL
@interface GleapWidgetLoadingView : UIView

/// Captures the background from the widget config and builds it. Call it once the
/// view is in the hierarchy; the bounds-dependent layers follow in layoutSubviews.
- (void)setUpFromConfig:(nullable NSDictionary *)config;

/// Re-reads the background and header colors and the background image (e.g. after
/// a color scheme change) and redraws. No-op before setUpFromConfig:.
- (void)updateThemeFromConfig:(nullable NSDictionary *)config;

@end

NS_ASSUME_NONNULL_END
