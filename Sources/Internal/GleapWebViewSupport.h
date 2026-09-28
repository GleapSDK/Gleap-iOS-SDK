//
//  GleapWebViewSupport.h
//  Gleap
//
//  What the widget, banner and modal web views have in common: their configuration, the
//  JavaScript bridge towards the page and how tapped links open.
//

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import "GleapInternal.h"

NS_ASSUME_NONNULL_BEGIN

GLEAP_INTERNAL
@interface GleapWebViewSupport : NSObject

/// A private (non-persistent) website data store and `handler` registered as
/// `window.webkit.messageHandlers.<name>`.
+ (WKWebViewConfiguration *)configurationWithMessageHandler:(id<WKScriptMessageHandler>)handler
                                                       name:(NSString *)name
                                  allowsInlineMediaPlayback:(BOOL)allowsInlineMediaPlayback;

/// The page lays itself out: no scrolling, bouncing or automatic content insets.
+ (void)disableScrollingInWebView:(WKWebView *)webView;

/// Lets the view behind the web view show through until the page draws.
+ (void)makeWebViewTransparent:(WKWebView *)webView;

/// Serializes `data` and calls `function(<json>)` in the page, on the main queue.
+ (void)sendMessage:(NSDictionary *)data toFunction:(NSString *)function inWebView:(nullable WKWebView *)webView;

/// Presents `url` in an SFSafariViewController from `presenter`.
+ (void)presentURLInSafari:(nullable NSURL *)url from:(nullable UIViewController *)presenter;

/// A tapped link: mailto: links go to the mail app, everything else is presented in Safari.
+ (void)openTappedLink:(nullable NSURL *)url from:(nullable UIViewController *)presenter;

@end

NS_ASSUME_NONNULL_END
