//
//  GleapNotificationCardFactory.m
//  Gleap
//

#import "GleapNotificationCardFactory.h"
#import "GleapConfigHelper.h"
#import "GleapSessionHelper.h"
#import "GleapTranslationHelper.h"
#import "GleapUIHelper.h"

@implementation GleapNotificationCardFactory

#pragma mark - Theming

// The widget theme drives the notification look — the same colors the web
// widget derives in injectStyledCSS, so a dark-themed project gets dark cards
// on every platform, independent of the OS appearance.

+ (UIColor *)notificationBackgroundColor {
    NSDictionary *config = GleapConfigHelper.sharedInstance.config;
    NSString *backgroundColor = [config objectForKey: @"backgroundColor"];
    if (backgroundColor == nil || backgroundColor.length == 0) {
        backgroundColor = @"#ffffff";
    }
    return [GleapUIHelper colorFromHexString: backgroundColor];
}

// YIQ >= 160 reads as a light background — the same threshold the web
// widget's calculateContrast uses.
+ (BOOL)notificationUsesDarkTheme {
    UIColor *backgroundColor = [GleapNotificationCardFactory notificationBackgroundColor];
    CGFloat red = 0, green = 0, blue = 0, alpha = 0;
    [backgroundColor getRed: &red green: &green blue: &blue alpha: &alpha];
    CGFloat yiq = ((red * 255.0 * 299.0) + (green * 255.0 * 587.0) + (blue * 255.0 * 114.0)) / 1000.0;
    return yiq < 160.0;
}

+ (UIColor *)notificationContrastColor {
    return [GleapNotificationCardFactory notificationUsesDarkTheme] ? [UIColor whiteColor] : [UIColor blackColor];
}

// Shifts every channel by `amount` (0-255 scale), clamped — mirrors the web
// widget's calculateShadeColor, which derives the muted text color from the
// background.
+ (UIColor *)shadeOfNotificationBackground:(CGFloat)amount {
    UIColor *backgroundColor = [GleapNotificationCardFactory notificationBackgroundColor];
    CGFloat red = 0, green = 0, blue = 0, alpha = 0;
    [backgroundColor getRed: &red green: &green blue: &blue alpha: &alpha];
    CGFloat shift = amount / 255.0;
    return [UIColor colorWithRed: MAX(0.0, MIN(1.0, red + shift))
                           green: MAX(0.0, MIN(1.0, green + shift))
                            blue: MAX(0.0, MIN(1.0, blue + shift))
                           alpha: 1.0];
}

+ (UIColor *)notificationSubTextColor {
    if ([GleapNotificationCardFactory notificationUsesDarkTheme]) {
        return [GleapNotificationCardFactory shadeOfNotificationBackground: 100.0];
    }
    return [GleapNotificationCardFactory shadeOfNotificationBackground: -120.0];
}

// A drop shadow alone cannot separate a dark card from a dark page, so the
// card also carries a hairline in the direction the theme needs.
+ (UIColor *)notificationHairlineColor {
    if ([GleapNotificationCardFactory notificationUsesDarkTheme]) {
        return [UIColor colorWithWhite: 1.0 alpha: 0.1];
    }
    return [UIColor colorWithWhite: 0.0 alpha: 0.04];
}

+ (CGFloat)notificationConfiguredBorderRadius {
    NSDictionary *config = GleapConfigHelper.sharedInstance.config;
    if (config != nil && [config objectForKey: @"borderRadius"] != nil) {
        return [[config objectForKey: @"borderRadius"] floatValue];
    }
    return 20.0;
}

// The card corner radius, derived from the project's border radius setting
// exactly like the web widget's containerRadius.
+ (CGFloat)notificationContainerRadius {
    return round([GleapNotificationCardFactory notificationConfiguredBorderRadius] * 0.8);
}

// The bot's avatar is a rounded rectangle rather than a circle — the same
// shape the dashboard and the messenger give it. Derived from the project's
// radius so a squared-off widget theme keeps squared-off marks; 7pt at the
// default 20 on the 32pt notification avatar.
+ (CGFloat)notificationBotAvatarRadiusForSize:(CGFloat)size {
    CGFloat formItemRadius = round([GleapNotificationCardFactory notificationConfiguredBorderRadius] * 0.4);
    return MAX(2.0, round((formItemRadius * size) / 36.0));
}

#pragma mark - Relative time

/**
 * "now" / "5 minutes ago" label for a notification's age, localized by the
 * system through NSRelativeDateTimeFormatter. Returns nil whenever a truthful
 * label can't be produced (no timestamp, an unparsable one, or an OS without
 * the formatter), so callers drop the label instead of printing a placeholder.
 *
 * The age is taken from sendAt rather than createdAt: a scheduled outbound is
 * written to the database long before it is delivered, and its creation time
 * would surface as an hours-old message the user just received.
 */
+ (NSString *)relativeTimeLabelForNotification:(NSDictionary *)notification {
    @try {
        id timestamp = [notification objectForKey: @"sendAt"];
        if (timestamp == nil || ![timestamp isKindOfClass: [NSString class]] || [timestamp length] == 0) {
            timestamp = [notification objectForKey: @"createdAt"];
        }
        if (timestamp == nil || ![timestamp isKindOfClass: [NSString class]] || [timestamp length] == 0) {
            return nil;
        }

        NSISO8601DateFormatter *isoFormatter = [[NSISO8601DateFormatter alloc] init];
        isoFormatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
        NSDate *date = [isoFormatter dateFromString: timestamp];
        if (date == nil) {
            isoFormatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
            date = [isoFormatter dateFromString: timestamp];
        }
        if (date == nil) {
            return nil;
        }

        NSRelativeDateTimeFormatter *formatter = [[NSRelativeDateTimeFormatter alloc] init];
        formatter.dateTimeStyle = NSRelativeDateTimeFormatterStyleNamed;

        // The widget's language override, falling back to the device locale.
        NSString *language = GleapTranslationHelper.sharedInstance.language;
        if (language != nil && language.length > 0) {
            NSLocale *locale = [NSLocale localeWithLocaleIdentifier: language];
            if (locale != nil) {
                formatter.locale = locale;
            }
        }

        // Clamped at 0: a notification scheduled a few seconds ahead (or a
        // client clock running behind the server's) must never read as
        // "in 1 minute". Under a minute collapses to "now" rather than
        // ticking "9 seconds ago".
        NSTimeInterval seconds = MIN(0.0, [date timeIntervalSinceNow]);
        if (seconds > -60.0) {
            seconds = 0.0;
        }
        return [formatter localizedStringFromTimeInterval: seconds];
    } @catch (id exp) {}

    return nil;
}

+ (UIView *)closeButtonWithTarget:(id)target action:(SEL)action {
    UIColor *backgroundColor = [GleapNotificationCardFactory notificationBackgroundColor];
    UIColor *crossColor = [GleapNotificationCardFactory notificationContrastColor];

    UIView *closeButton = [[UIView alloc] initWithFrame: CGRectMake(0, 0, 26, 26)];
    closeButton.layer.cornerRadius = 13.0;
    closeButton.layer.shadowRadius  = 4.0;
    closeButton.layer.shadowColor   = [UIColor blackColor].CGColor;
    closeButton.layer.shadowOffset  = CGSizeMake(0.0f, 2.0f);
    closeButton.layer.shadowOpacity = 0.18;
    closeButton.autoresizesSubviews = NO;
    closeButton.backgroundColor = backgroundColor;

    UITapGestureRecognizer *clearNotificationsGesture =
      [[UITapGestureRecognizer alloc] initWithTarget:target
                                              action:action];
    [closeButton addGestureRecognizer: clearNotificationsGesture];

    UIView * crossLeft = [[UIView alloc] initWithFrame: CGRectMake(0, 0, 11.0, 1.5)];
    crossLeft.backgroundColor = crossColor;
    crossLeft.center = CGPointMake(13.0, 13.0);
    crossLeft.autoresizingMask = UIViewAutoresizingNone;
    crossLeft.layer.cornerRadius = 0.75;
    crossLeft.transform = CGAffineTransformMakeRotation(45 * -1 * M_PI/180);
    [closeButton addSubview: crossLeft];

    UIView * crossRight = [[UIView alloc] initWithFrame: CGRectMake(0, 0, 11.0, 1.5)];
    crossRight.backgroundColor = crossColor;
    crossRight.center = CGPointMake(13.0, 13.0);
    crossRight.autoresizingMask = UIViewAutoresizingNone;
    crossRight.layer.cornerRadius = 0.75;
    crossRight.transform = CGAffineTransformMakeRotation(45 * M_PI/180);
    [closeButton addSubview: crossRight];

    return closeButton;
}

// Every notification card shares one chrome: full container width, the
// project's container radius, a hairline border and a soft two-layer shadow.
// The wrapper carries the large ambient throw (it needs an explicit shadow
// path, being transparent), the card itself the contact shadow.
+ (UIView *)styledCardWrapperWithCard:(UIView *)cardView {
    CGFloat containerRadius = [GleapNotificationCardFactory notificationContainerRadius];

    cardView.backgroundColor = [GleapNotificationCardFactory notificationBackgroundColor];
    cardView.layer.cornerRadius = containerRadius;
    cardView.layer.borderWidth = 1.0;
    cardView.layer.borderColor = [GleapNotificationCardFactory notificationHairlineColor].CGColor;
    cardView.layer.shadowRadius = 3.0;
    cardView.layer.shadowColor = [UIColor blackColor].CGColor;
    cardView.layer.shadowOffset = CGSizeMake(0.0, 2.0);
    cardView.layer.shadowOpacity = 0.04;
    cardView.layer.masksToBounds = NO;
    cardView.clipsToBounds = NO;

    UIView *wrapperView = [[UIView alloc] initWithFrame: cardView.frame];
    wrapperView.backgroundColor = [UIColor clearColor];
    wrapperView.layer.shadowRadius = 15.0;
    wrapperView.layer.shadowColor = [UIColor blackColor].CGColor;
    wrapperView.layer.shadowOffset = CGSizeMake(0.0, 10.0);
    wrapperView.layer.shadowOpacity = 0.10;
    wrapperView.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect: cardView.bounds cornerRadius: containerRadius].CGPath;
    wrapperView.layer.masksToBounds = NO;
    wrapperView.clipsToBounds = NO;

    CGRect cardFrame = cardView.frame;
    cardFrame.origin = CGPointZero;
    cardView.frame = cardFrame;
    [wrapperView addSubview: cardView];

    return wrapperView;
}

// Sender avatar, or nil when there is no image to show. Teammates stay
// circular and the bot gets a rounded square — the same split the messenger
// makes. `isBot` is absent on payloads from servers that don't send it yet,
// which falls through to the teammate shape.
+ (UIImageView *)avatarViewForSender:(NSDictionary *)sender withFrame:(CGRect)frame {
    NSString *profileImageUrl = [sender objectForKey: @"profileImageUrl"];
    if (sender == nil || profileImageUrl == nil || ![profileImageUrl isKindOfClass: [NSString class]] || profileImageUrl.length == 0) {
        return nil;
    }

    BOOL isBot = [sender objectForKey: @"isBot"] != nil && [[sender objectForKey: @"isBot"] boolValue];

    UIImageView *avatarView = [[UIImageView alloc] initWithFrame: frame];
    avatarView.backgroundColor = [[GleapNotificationCardFactory notificationSubTextColor] colorWithAlphaComponent: 0.2];
    if (isBot) {
        avatarView.layer.cornerRadius = [GleapNotificationCardFactory notificationBotAvatarRadiusForSize: frame.size.width];
    } else {
        avatarView.layer.cornerRadius = frame.size.width / 2.0;
    }
    avatarView.contentMode = UIViewContentModeScaleAspectFill;
    avatarView.clipsToBounds = YES;

    dispatch_async(dispatch_get_global_queue(0,0), ^{
        NSData * data = [[NSData alloc] initWithContentsOfURL: [NSURL URLWithString: profileImageUrl]];
        if (data == nil) {
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (avatarView != nil) {
                avatarView.image = [UIImage imageWithData: data];
            }
        });
    });

    return avatarView;
}

+ (UIView *)createNotificationViewFor:(NSDictionary *)notification andWith:(int)width {
    NSDictionary *config = GleapConfigHelper.sharedInstance.config;
    if (config == nil) {
        return nil;
    }

    NSDictionary *notificationData = [notification objectForKey: @"data"];
    NSDictionary * sender = [notificationData objectForKey: @"sender"];

    UIColor *contrastColor = [GleapNotificationCardFactory notificationContrastColor];
    UIColor *subTextColor = [GleapNotificationCardFactory notificationSubTextColor];
    CGFloat containerRadius = [GleapNotificationCardFactory notificationContainerRadius];

    NSString *userName = [[GleapSessionHelper sharedInstance] getSessionName];
    NSString *textContent = [notificationData objectForKey: @"text"];
    textContent = [textContent stringByReplacingOccurrencesOfString:@"{{name}}" withString: userName];

    if ([[notificationData objectForKey: @"type"] isEqualToString: @"news"]) {
        CGFloat contentPadding = 16.0;
        CGFloat titleHeight = 21.0;
        CGFloat senderRowHeight = 20.0;
        BOOL hasSender = sender != nil && [sender objectForKey: @"name"] != nil;

        CGFloat cardHeight = 155.0 + contentPadding + titleHeight + contentPadding;
        if (hasSender) {
            cardHeight += 6.0 + senderRowHeight;
        }

        UIView * cardView = [[UIView alloc] initWithFrame: CGRectMake(0.0, 0.0, width, cardHeight)];

        // The cover image squares off against the card's rounded top corners.
        UIImageView * newsImageView = [[UIImageView alloc] initWithFrame: CGRectMake(0.0, 0.0, width, 155.0)];
        newsImageView.backgroundColor = [[GleapNotificationCardFactory notificationSubTextColor] colorWithAlphaComponent: 0.2];
        newsImageView.layer.cornerRadius = containerRadius;
        newsImageView.layer.maskedCorners = kCALayerMaxXMinYCorner | kCALayerMinXMinYCorner;
        newsImageView.contentMode = UIViewContentModeScaleAspectFill;
        newsImageView.clipsToBounds = YES;
        [cardView addSubview: newsImageView];

        dispatch_async(dispatch_get_global_queue(0,0), ^{
            NSData * data = [[NSData alloc] initWithContentsOfURL: [NSURL URLWithString: [notificationData objectForKey: @"coverImageUrl"]]];
            if (data == nil) {
                return;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if (newsImageView != nil) {
                    newsImageView.image = [UIImage imageWithData: data];
                }
            });
        });

        UIFont *contentFont = [UIFont systemFontOfSize: 15 weight: UIFontWeightSemibold];
        UILabel *contentLabel = [[UILabel alloc] initWithFrame: CGRectMake(contentPadding, 155.0 + contentPadding, width - (contentPadding * 2.0), titleHeight)];
        contentLabel.text = textContent;
        contentLabel.font = contentFont;
        contentLabel.adjustsFontSizeToFitWidth = NO;
        contentLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        contentLabel.numberOfLines = 1;
        contentLabel.textColor = contrastColor;
        [cardView addSubview: contentLabel];

        if (hasSender) {
            CGFloat senderRowY = 155.0 + contentPadding + titleHeight + 6.0;
            UIImageView *senderImageView = [self avatarViewForSender: sender withFrame: CGRectMake(contentPadding, senderRowY, 20.0, 20.0)];
            CGFloat senderLabelX = contentPadding;
            if (senderImageView != nil) {
                [cardView addSubview: senderImageView];
                senderLabelX += 20.0 + 8.0;
            }

            UILabel *senderLabel = [[UILabel alloc] initWithFrame: CGRectMake(senderLabelX, senderRowY, width - senderLabelX - contentPadding, senderRowHeight)];
            senderLabel.text = [sender objectForKey: @"name"];
            senderLabel.font = [UIFont systemFontOfSize: 14];
            senderLabel.textColor = subTextColor;
            senderLabel.lineBreakMode = NSLineBreakByTruncatingTail;
            [cardView addSubview: senderLabel];
        }

        return [self styledCardWrapperWithCard: cardView];
    } else if ([[notificationData objectForKey: @"type"] isEqualToString: @"checklist"]) {
        CGFloat contentPadding = 16.0;

        UIView * cardView = [[UIView alloc] initWithFrame: CGRectMake(0.0, 0.0, width, 100.0)];

        UIFont *contentFont = [UIFont systemFontOfSize: 16 weight: UIFontWeightSemibold];
        UILabel *contentLabel = [[UILabel alloc] initWithFrame: CGRectMake(contentPadding, contentPadding, width - (contentPadding * 2.0), 18.0)];
        contentLabel.text = textContent;
        contentLabel.font = contentFont;
        contentLabel.adjustsFontSizeToFitWidth = NO;
        contentLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        contentLabel.numberOfLines = 1;
        contentLabel.textColor = contrastColor;
        [cardView addSubview: contentLabel];

        UILabel *nextStepLabel = [[UILabel alloc] initWithFrame: CGRectMake(contentPadding, 66.0, width - (contentPadding * 2.0), 18.0)];
        nextStepLabel.text = [notificationData objectForKey: @"nextStepTitle"];
        nextStepLabel.adjustsFontSizeToFitWidth = NO;
        nextStepLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        nextStepLabel.numberOfLines = 1;
        nextStepLabel.font = [UIFont systemFontOfSize: 14];
        nextStepLabel.textColor = subTextColor;
        [cardView addSubview: nextStepLabel];

        UIView *progressBarViewBG = [[UIView alloc] initWithFrame: CGRectMake(contentPadding, 46.0, width - (contentPadding * 2.0), 8.0)];
        progressBarViewBG.layer.cornerRadius = 4.0;
        progressBarViewBG.layer.masksToBounds = YES;
        progressBarViewBG.clipsToBounds = YES;
        progressBarViewBG.alpha = 0.15;
        progressBarViewBG.backgroundColor = contrastColor;
        [cardView addSubview: progressBarViewBG];

        int maxWidth = width - (contentPadding * 2.0);
        @try {
            NSNumber *currentStepNumber = [notificationData objectForKey:@"currentStep"];
            NSNumber *totalStepsNumber = [notificationData objectForKey:@"totalSteps"];

            if (currentStepNumber && totalStepsNumber) {
                double currentStep = [currentStepNumber doubleValue];
                double totalSteps = [totalStepsNumber doubleValue];

                double progress = currentStep / totalSteps;
                if (progress < 1.0) {
                    progress += 0.04;
                }
                maxWidth = maxWidth * progress;
            } else {
                maxWidth = maxWidth * 0.04;
            }

        } @catch (id exp) {
            maxWidth = maxWidth * 0.04;
        }

        UIView *progressBarView = [[UIView alloc] initWithFrame: CGRectMake(contentPadding, 46.0, maxWidth, 8.0)];
        progressBarView.layer.cornerRadius = 4.0;
        progressBarView.layer.masksToBounds = YES;
        progressBarView.clipsToBounds = YES;
        progressBarView.alpha = 1;
        NSString *mainColor = [config objectForKey: @"color"];
        if (mainColor != nil && mainColor.length > 0) {
            progressBarView.backgroundColor = [GleapUIHelper colorFromHexString: mainColor];
        } else {
            progressBarView.backgroundColor = contrastColor;
        }
        [cardView addSubview: progressBarView];

        return [self styledCardWrapperWithCard: cardView];
    } else {
        // Standard non-news notification. Avatar and text live inside one card
        // (no speech-bubble tail), with the sender + time as a meta line below
        // the message.
        CGFloat contentPadding = 16.0;
        CGFloat avatarSize = 32.0;

        UIImageView *avatarView = [self avatarViewForSender: sender withFrame: CGRectMake(contentPadding, contentPadding, avatarSize, avatarSize)];

        CGFloat bodyX = contentPadding + (avatarView != nil ? avatarSize + 10.0 : 0.0);
        CGFloat bodyWidth = width - bodyX - contentPadding;

        UIFont *contentFont = [UIFont systemFontOfSize: 15];
        UILabel *contentLabel = [[UILabel alloc] init];
        contentLabel.text = textContent;
        contentLabel.font = contentFont;
        contentLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        contentLabel.numberOfLines = 2;
        contentLabel.textColor = contrastColor;
        CGSize contentSize = [contentLabel sizeThatFits: CGSizeMake(bodyWidth, CGFLOAT_MAX)];
        CGFloat contentHeight = MIN(contentSize.height, contentFont.lineHeight * 2.0 + 2.0);
        contentLabel.frame = CGRectMake(bodyX, contentPadding, bodyWidth, contentHeight);

        // The "Sender · 5 minutes ago" line under the message. Either half may
        // be missing, so the separator only appears when both are present.
        NSString *senderName = sender != nil ? [sender objectForKey: @"name"] : nil;
        NSString *timeLabelText = [GleapNotificationCardFactory relativeTimeLabelForNotification: notification];
        BOOL hasMeta = (senderName != nil && senderName.length > 0) || (timeLabelText != nil && timeLabelText.length > 0);

        CGFloat metaHeight = hasMeta ? 18.0 : 0.0;
        CGFloat metaSpacing = hasMeta ? 5.0 : 0.0;
        CGFloat bodyHeight = contentHeight + metaSpacing + metaHeight;
        CGFloat innerHeight = MAX(avatarView != nil ? avatarSize : 0.0, bodyHeight);
        CGFloat cardHeight = contentPadding + innerHeight + contentPadding;

        UIView * cardView = [[UIView alloc] initWithFrame: CGRectMake(0.0, 0.0, width, cardHeight)];

        if (avatarView != nil) {
            [cardView addSubview: avatarView];
        }
        [cardView addSubview: contentLabel];

        if (hasMeta) {
            CGFloat metaY = contentPadding + contentHeight + metaSpacing;
            CGFloat metaX = bodyX;
            UIFont *metaFont = [UIFont systemFontOfSize: 13];
            UIFont *senderFont = [UIFont systemFontOfSize: 13 weight: UIFontWeightMedium];

            UILabel *timeLabel = nil;
            CGFloat timeWidth = 0;
            if (timeLabelText != nil && timeLabelText.length > 0) {
                timeLabel = [[UILabel alloc] init];
                timeLabel.text = timeLabelText;
                timeLabel.font = metaFont;
                timeLabel.textColor = subTextColor;
                timeWidth = ceil([timeLabel sizeThatFits: CGSizeMake(CGFLOAT_MAX, metaHeight)].width);
            }

            if (senderName != nil && senderName.length > 0) {
                UILabel *senderLabel = [[UILabel alloc] init];
                senderLabel.text = senderName;
                senderLabel.font = senderFont;
                senderLabel.textColor = subTextColor;
                senderLabel.lineBreakMode = NSLineBreakByTruncatingTail;

                // The sender may truncate; the timestamp never does.
                CGFloat dotWidth = timeLabel != nil ? 13.0 : 0.0;
                CGFloat senderMaxWidth = bodyWidth - timeWidth - dotWidth;
                CGFloat senderWidth = MIN(ceil([senderLabel sizeThatFits: CGSizeMake(CGFLOAT_MAX, metaHeight)].width), senderMaxWidth);
                senderLabel.frame = CGRectMake(metaX, metaY, MAX(senderWidth, 0), metaHeight);
                [cardView addSubview: senderLabel];
                metaX += MAX(senderWidth, 0);

                if (timeLabel != nil) {
                    UILabel *dotLabel = [[UILabel alloc] initWithFrame: CGRectMake(metaX, metaY, dotWidth, metaHeight)];
                    dotLabel.text = @"•";
                    dotLabel.font = metaFont;
                    dotLabel.textColor = [subTextColor colorWithAlphaComponent: 0.6];
                    dotLabel.textAlignment = NSTextAlignmentCenter;
                    [cardView addSubview: dotLabel];
                    metaX += dotWidth;
                }
            }

            if (timeLabel != nil) {
                timeLabel.frame = CGRectMake(metaX, metaY, MIN(timeWidth, width - metaX - contentPadding), metaHeight);
                [cardView addSubview: timeLabel];
            }
        }

        return [self styledCardWrapperWithCard: cardView];
    }
}

@end
