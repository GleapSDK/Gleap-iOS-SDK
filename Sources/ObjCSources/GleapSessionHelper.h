//
//  GleapSessionHelper.h
//  Gleap
//
//  Created by Lukas Boehler on 23.09.21.
//
//  Internal to the Gleap SDK. This header is only public because every header in
//  Sources/ObjCSources is; it is not part of the supported API and may change without
//  notice. Use the Gleap class (GleapCore.h) instead.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "GleapSession.h"
#import "GleapUserProperty.h"

NS_ASSUME_NONNULL_BEGIN

@interface GleapSessionHelper : NSObject

/**
 * Returns the shared instance of GleapSessionHelper.
 * @author Gleap
 *
 * @return The shared instance of GleapSessionHelper.
 */
+ (instancetype)sharedInstance;
+ (NSString *)getDeviceType;
+ (void)injectSessionInRequest:(NSMutableURLRequest *)request;
+ (void)handlePushNotification:(NSDictionary *)notificationData;

- (void)startSessionWith:(void (^)(bool success))completion;
- (void)identifySessionWith:(NSString *)userId andData:(nullable GleapUserProperty *)data andUserHash:(NSString * _Nullable)userHash;
- (void)updateContact:(nullable GleapUserProperty *)data;
- (void)processOpenPushAction;
- (void)clearSession;
- (BOOL)openProtectedFileFromURL:(NSURL *)url;
- (BOOL)refreshFileAccessIfNeeded;
// Runs `block` (main queue) once the identify and contact updates on their way are answered; NO when none is.
- (BOOL)runWhenContactSettled:(dispatch_block_t)block;
- (NSString *)getSessionName;

@property (nonatomic, retain, nullable) GleapSession* currentSession;
@property (nonatomic, retain, nullable) NSDictionary* openPushAction;
@property (nonatomic, retain, nullable) NSDictionary* openIdentityAction;
@property (nonatomic, retain, nullable) NSDictionary* openUpdateAction;
@property (nonatomic, retain, nullable) NSString* lastRegisterGleapHash;
// The app's latest identify (userId, userHash, data), in memory only: replayed to renew the file access token.
@property (nonatomic, retain, nullable) NSDictionary* lastIdentifyAction;
// A protected file from an emailed link, opened once the session has file access.
@property (nonatomic, retain, nullable) NSString* pendingProtectedFileId;

@end

NS_ASSUME_NONNULL_END
