#ifdef __OBJC__
#import <UIKit/UIKit.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import "Gleap.h"
#import "GleapCore.h"
#import "GleapHttpTrafficRecorder.h"
#import "GleapLogHelper.h"
#import "GleapReplayHelper.h"
#import "GleapUserSession.h"
#import "GleapSession.h"
#import "GleapSessionHelper.h"
#import "GleapTouchHelper.h"
#import "GleapTranslationHelper.h"
#import "GleapWidgetViewController.h"
#import "UIWindow+GleapShakeRecognizer.h"
#import "UIWindow+GleapTouchRecognizer.h"

FOUNDATION_EXPORT double GleapVersionNumber;
FOUNDATION_EXPORT const unsigned char GleapVersionString[];

