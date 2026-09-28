//
//  GleapModal.h
//  
//
//  Created by Lukas Boehler on 29.04.25.
//
//  Internal to the Gleap SDK. This header is only public because every header in
//  Sources/ObjCSources is; it is not part of the supported API and may change without
//  notice. Use the Gleap class (GleapCore.h) instead.
//

@class GleapUIOverlayViewController;

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapModal : UIView <WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate>

/// Configure the modal with given data
- (void)setupWithData:(NSDictionary *)modalData;

@property (nonatomic, strong) UIView *backdropView;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) NSDictionary *modalData;
@property (nonatomic, weak) GleapUIOverlayViewController *uiOverlayViewController;

@end

NS_ASSUME_NONNULL_END
