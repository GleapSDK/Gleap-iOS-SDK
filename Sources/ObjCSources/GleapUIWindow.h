//
//  GleapUIWindow.h
//  
//
//  Created by Lukas Boehler on 09.09.22.
//

#import <UIKit/UIKit.h>

@protocol GleapUIWindowDelegate <NSObject>
@optional
- (void)pressedView:(UIView * _Nonnull)view;
@end

NS_ASSUME_NONNULL_BEGIN

@interface GleapUIWindow : UIWindow

@property (nonatomic, weak) id <GleapUIWindowDelegate> delegate;

@end

NS_ASSUME_NONNULL_END
