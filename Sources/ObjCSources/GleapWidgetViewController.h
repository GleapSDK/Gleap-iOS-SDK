//
//  GleapWidgetViewController.h
//  Gleap
//
//  Created by Lukas on 13.01.19.
//  Copyright © 2019 Gleap. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapWidgetViewController : UIViewController <WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate>

- (void)setScreenshot:(UIImage *)image;

@property (nonatomic, retain, nullable) NSTimer* timeoutTimer;

@end

NS_ASSUME_NONNULL_END
