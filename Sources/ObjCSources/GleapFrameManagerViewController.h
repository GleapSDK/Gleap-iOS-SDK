//
//  GleapFrameManagerViewController.h
//  Gleap
//
//  Created by Lukas on 13.01.19.
//  Copyright © 2019 Gleap. All rights reserved.
//
//  Internal to the Gleap SDK. This header is only public because every header in
//  Sources/ObjCSources is; it is not part of the supported API and may change without
//  notice. Use the Gleap class (GleapCore.h) instead.
//

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol GleapFrameManagerDelegate <NSObject>
@optional
- (void) connected;
- (void) failedToConnect;
// A survey's page has something to show: a card its first height-update, a full screen survey survey-shown,
// survey-legacy or height-update.
- (void) surveyContentShown;
@required
@end

@interface GleapFrameManagerViewController : UIViewController <WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate>

- (void)sendMessageWithData:(NSDictionary *)data;
- (void)sendSessionUpdate;
- (void)sendConfigUpdate;
- (void)updateThemeColors;
- (id)initWithFormat:(NSString *)format;

@property (nonatomic, retain, nullable) NSTimer* timeoutTimer;
@property (nonatomic, assign) bool isCardSurvey;
// A survey (card or full screen), not the messenger.
@property (nonatomic, assign) bool isSurvey;
@property (nonatomic, assign) bool connected;
@property (nonatomic, weak) id <GleapFrameManagerDelegate> delegate;

@end

NS_ASSUME_NONNULL_END
