//
//  GleapFeedbackButton.h
//  
//
//  Created by Lukas Boehler on 29.04.25.
//

@class GleapUIOverlayViewController;

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapModal : UIView <WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate>

/// Configure the modal with given data
- (void)setupWithData:(NSDictionary *)modalData;

/// Sends the modal data (incl. the widget colors) to the loaded modal. A resend
/// only recolors, the current step is kept.
- (void)sendModalData;

@property (nonatomic, strong) UIView *backdropView;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) NSDictionary *modalData;
@property (nonatomic, weak) GleapUIOverlayViewController *uiOverlayViewController;

@end

NS_ASSUME_NONNULL_END
