//
//  GleapSessionHelper.h
//  Gleap
//
//  Created by Lukas Boehler on 23.09.21.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "GleapSession.h"
#import "GleapUserProperty.h"

NS_ASSUME_NONNULL_BEGIN

@interface GleapSessionHelper : NSObject

/**
 * Returns a new shared instance of GleapSessionHelper.
 * @author Gleap
 *
 * @return A new shared instance of GleapSessionHelper.
 */
+ (instancetype)sharedInstance;
+ (void)injectSessionInRequest:(NSMutableURLRequest *)request;
+ (void)handlePushNotification:(NSDictionary *)notificationData;

- (void)startSessionWith:(void (^)(bool success))completion;
- (void)identifySessionWith:(NSString *)userId andData:(nullable GleapUserProperty *)data andUserHash:(NSString * _Nullable)userHash;
- (void)updateContact:(nullable GleapUserProperty *)data;
- (void)processOpenPushAction;
- (void)clearSession;
- (NSString *)getSessionName;

@property (nonatomic, retain, nullable) GleapSession* currentSession;
@property (nonatomic, retain, nullable) NSDictionary* openPushAction;
@property (nonatomic, retain, nullable) NSDictionary* openIdentityAction;
@property (nonatomic, retain, nullable) NSDictionary* openUpdateAction;
@property (nonatomic, retain, nullable) NSString* lastRegisterGleapHash;

@end

NS_ASSUME_NONNULL_END
