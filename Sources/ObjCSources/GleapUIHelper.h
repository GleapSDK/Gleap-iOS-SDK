//
//  GleapUIHelper.h
//  
//
//  Created by Lukas Boehler on 27.05.22.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapUIHelper : NSObject

+ (NSString *)getTopMostViewControllerName;
+ (UIViewController *)getTopMostViewController;
+ (UIViewController *)topViewControllerWith:(UIViewController *)rootViewController;
+ (UIColor *)colorFromHexString:(NSString *)hexString;
+ (NSString *)getJSStringForNSDate:(NSDate *)date;
+ (UIColor *)contrastColorFrom:(UIColor *)color;

@end

NS_ASSUME_NONNULL_END
