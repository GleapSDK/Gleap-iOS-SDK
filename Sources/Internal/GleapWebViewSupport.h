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
/// `window.webkit.messageHandlers.<name>`. The configuration only keeps a weak reference to
/// `handler`, so a web view does not keep its owner alive.
+ (WKWebViewConfiguration *)configurationWithMessageHandler:(id<WKScriptMessageHandler>)handler
                                                       name:(NSString *)name
                                  allowsInlineMediaPlayback:(BOOL)allowsInlineMediaPlayback;

/// Unregisters the message handler `name` of `webView`; call it when the web view's owner goes away.
+ (void)removeMessageHandlerNamed:(NSString *)name fromWebView:(nullable WKWebView *)webView;

/// YES when `message` may drive the native bridge: it was posted by the main frame of a page on
/// the host of `pageURL` (the configured frame, banner or modal URL). Other frames, such as
/// third-party content embedded in help articles, news or banners, are ignored.
+ (BOOL)isTrustedMessage:(WKScriptMessage *)message forPageURL:(nullable NSString *)pageURL;

/// The rule behind isTrustedMessage:forPageURL:.
+ (BOOL)acceptsMessageFromMainFrame:(BOOL)isMainFrame host:(nullable NSString *)host forPageURL:(nullable NSString *)pageURL;

/// YES when `host` is the host of `pageURL` (case-insensitive).
+ (BOOL)isHost:(nullable NSString *)host ofPageURL:(nullable NSString *)pageURL;

/// Camera and microphone for a page: granted without asking only for the host of `pageURL`,
/// every other origin gets the system prompt.
+ (WKPermissionDecision)mediaCaptureDecisionForHost:(nullable NSString *)host pageURL:(nullable NSString *)pageURL;

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
