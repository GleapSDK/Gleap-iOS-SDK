//
//  GleapNotificationHelper.m
//  
//
//  Created by Lukas Boehler on 29.08.22.
//

#import "GleapNotificationHelper.h"
#import "Gleap.h"
#import "GleapSessionHelper.h"
#import <UIKit/UIKit.h>

@implementation GleapNotificationHelper

/*
 Returns a shared instance (singleton).
 */
+ (instancetype)sharedInstance
{
    static GleapNotificationHelper *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GleapNotificationHelper alloc] init];
        sharedInstance.notifications = [[NSMutableArray alloc] init];
        sharedInstance.notificationViews = [[NSMutableArray alloc] init];
        sharedInstance.notificationCount = 0;
    });
    return sharedInstance;
}

+ (void)setNotificationCount:(int)notificationCount {
    [GleapNotificationHelper sharedInstance].notificationCount = notificationCount;
}

+ (void)showNotification:(NSDictionary *)notification {
    if ([[GleapNotificationHelper sharedInstance].notifications count] >= 2) {
        [[GleapNotificationHelper sharedInstance].notifications removeObjectAtIndex: 0];
    }
    [[GleapNotificationHelper sharedInstance].notifications addObject: notification];
    [[GleapNotificationHelper sharedInstance] renderNotifications];
}

- (void)renderNotifications {
    UIWindow *keyWindow = [UIApplication.sharedApplication keyWindow];
    
    // Cleanup existing notifications.
    for (int i = 0; i < self.notificationViews.count; i++) {
        [[self.notificationViews objectAtIndex: i] removeFromSuperview];
    }
    
    // Create new notifications.
    CGFloat currentNotificationHeight = 0.0;
    for (int i = 0; i < self.notifications.count; i++) {
        NSDictionary * notification = [self.notifications objectAtIndex: i];
        UIView *notificationView = [self createNotificationViewFor: notification onWindow: keyWindow];
        notificationView.tag = i;
        
        UITapGestureRecognizer *singleFingerTap =
          [[UITapGestureRecognizer alloc] initWithTarget:self
                                                  action:@selector(notificationTaped:)];
        [notificationView addGestureRecognizer: singleFingerTap];
        
        CGFloat bottomPadding = 0.0;
        if (@available(iOS 11.0, *)) {
            UIWindow *window = UIApplication.sharedApplication.windows.firstObject;
            bottomPadding = window.safeAreaInsets.bottom;
        }
        
        notificationView.frame = CGRectMake(0.0, keyWindow.frame.size.height - notificationView.frame.size.height - 20 - bottomPadding - currentNotificationHeight, notificationView.frame.size.width, notificationView.frame.size.height);
        
        [keyWindow addSubview: notificationView];
        [self.notificationViews addObject: notificationView];
        
        currentNotificationHeight += notificationView.frame.size.height + 20.0;
    }
}

- (void)notificationTaped:(UITapGestureRecognizer *)recognizer
{
    @try {
        NSDictionary *notification = [self.notifications objectAtIndex: recognizer.view.tag];
        [Gleap open];
    } @catch(id exception) {}
}

- (void)clearNotifications {
    self.notifications = [[NSMutableArray alloc] init];
    [self renderNotifications];
}

- (UIView *)createNotificationViewFor:(NSDictionary *)notification onWindow:(UIWindow *)window {
    NSDictionary *notificationData = [notification objectForKey: @"data"];
    NSDictionary * sender = [notificationData objectForKey: @"sender"];
    
    CGFloat width = window.frame.size.width;
    
    UIImageView * senderImageView = [[UIImageView alloc] initWithFrame: CGRectMake(20.0, 0.0, 40.0, 40.0)];
    senderImageView.backgroundColor = [UIColor grayColor];
    senderImageView.layer.cornerRadius = 20.0;
    senderImageView.clipsToBounds = YES;
    
    dispatch_async(dispatch_get_global_queue(0,0), ^{
        NSData * data = [[NSData alloc] initWithContentsOfURL: [NSURL URLWithString: [sender objectForKey: @"profileImageUrl"]]];
        if ( data == nil )
            return;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (senderImageView != nil) {
                senderImageView.image = [UIImage imageWithData: data];
            }
        });
    });
    
    UIView * chatBubbleView = [[UIView alloc] initWithFrame: CGRectMake(68.0, 0.0, width - 88.0, 80.0)];
    chatBubbleView.layer.cornerRadius = 8.0;
    chatBubbleView.layer.shadowRadius  = 8.0;
    chatBubbleView.layer.shadowColor   = [UIColor blackColor].CGColor;
    chatBubbleView.layer.shadowOffset  = CGSizeMake(0.0f, 0.0f);
    chatBubbleView.layer.shadowOpacity = 0.2;
    chatBubbleView.layer.masksToBounds = NO;
    chatBubbleView.clipsToBounds = NO;
    if (@available(iOS 13.0, *)) {
        chatBubbleView.backgroundColor = [UIColor systemBackgroundColor];
    } else {
        chatBubbleView.backgroundColor = [UIColor whiteColor];
    }
    
    UILabel *senderLabel = [[UILabel alloc] initWithFrame: CGRectMake(8, 8, chatBubbleView.frame.size.width - 16, 14)];
    senderLabel.text = [sender objectForKey: @"name"];
    senderLabel.font = [UIFont systemFontOfSize: 14];
    senderLabel.textColor = [UIColor darkGrayColor];
    [chatBubbleView addSubview: senderLabel];
    
    NSString *userName = [[GleapSessionHelper sharedInstance] getSessionName];
    NSString *textContent = [notificationData objectForKey: @"text"];
    textContent = [textContent stringByReplacingOccurrencesOfString:@"{{name}}" withString: userName];
    
    UILabel *contentLabel = [[UILabel alloc] initWithFrame: CGRectMake(8, 28, chatBubbleView.frame.size.width - 16, 40)];
    contentLabel.text = textContent;
    contentLabel.font = [UIFont systemFontOfSize: 16];
    contentLabel.lineBreakMode = NSLineBreakByWordWrapping;
    contentLabel.numberOfLines = 2;
    contentLabel.textColor = [UIColor blackColor];
    
    [chatBubbleView addSubview: contentLabel];
    
    UIView * containerView = [[UIView alloc] initWithFrame: CGRectMake(0.0, 0, width, chatBubbleView.frame.size.height)];
    
    [containerView addSubview: chatBubbleView];
    [containerView addSubview: senderImageView];
    
    return containerView;
}

-(void)calculateHeightForLabel:(UILabel *)label {
    CGSize constraint = CGSizeMake(label.frame.size.width, CGFLOAT_MAX);
    CGSize size;
    NSStringDrawingContext *context = [[NSStringDrawingContext alloc] init];
    CGSize boundingBox = [label.text boundingRectWithSize:constraint    options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName: label.font}
                                            context:context].size;
    size = CGSizeMake(ceil(boundingBox.width), ceil(boundingBox.height));
    label.frame = CGRectMake(label.frame.origin.x, label.frame.origin.y, label.frame.size.width, size.height);
}

@end
