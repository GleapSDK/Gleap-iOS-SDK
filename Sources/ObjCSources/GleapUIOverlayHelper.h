//
//  GleapUIOverlayHelper.h
//  
//
//  Created by Lukas Boehler on 29.08.22.
//
//  Internal to the Gleap SDK. This header is only public because every header in
//  Sources/ObjCSources is; it is not part of the supported API and may change without
//  notice. Use the Gleap class (GleapCore.h) instead.
//

#import <Foundation/Foundation.h>
#import "GleapFeedbackButton.h"
#import "GleapUIOverlayViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface GleapUIOverlayHelper : NSObject

+ (instancetype)sharedInstance;
+ (void)showNotification:(NSDictionary *)notification;
+ (void)updateNotificationCount:(int)notificationCount;
+ (void)showFeedbackButton:(bool)show;
+ (void)showBanner:(NSDictionary *)bannerData;
+ (void)showModal:(NSDictionary *)modalData;
+ (void)clear;
+ (void)updateUI;

@property (nonatomic, assign) bool showButton;
@property (nonatomic, assign) bool showButtonExternalOverwrite;
@property (nonatomic, assign) int notificationCount;
@property (nonatomic, retain) GleapUIOverlayViewController *uiOverlayViewController;
@property (nonatomic, retain) NSMutableArray *notifications;

@end

NS_ASSUME_NONNULL_END
