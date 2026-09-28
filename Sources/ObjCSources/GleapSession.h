//
//  GleapSession.h
//  Gleap
//
//  Created by Lukas Boehler on 23.09.21.
//
//  Internal to the Gleap SDK. This header is only public because every header in
//  Sources/ObjCSources is; it is not part of the supported API and may change without
//  notice. Use the Gleap class (GleapCore.h) instead.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapSession : NSObject

- (NSDictionary *)toDictionary;

@property (nonatomic, retain) NSString* gleapId;
@property (nonatomic, retain) NSString* gleapHash;
@property (nonatomic, retain, nullable) NSString* userId;
@property (nonatomic, retain, nullable) NSString* name;
@property (nonatomic, retain, nullable) NSString* email;
@property (nonatomic, retain, nullable) NSString* phone;
@property (nonatomic, retain, nullable) NSString* lang;
@property (nonatomic, retain, nullable) NSString* plan;
@property (nonatomic, retain, nullable) NSString* companyId;
@property (nonatomic, retain, nullable) NSString* companyName;
@property (nonatomic, retain, nullable) NSString* avatar;
@property (nonatomic, retain, nullable) NSDictionary* customData;
@property (nonatomic, retain, nullable) NSNumber* value;
@property (nonatomic, retain, nullable) NSNumber* sla;

@end

NS_ASSUME_NONNULL_END
