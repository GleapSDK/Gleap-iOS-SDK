//
//  GleapSession.h
//  Gleap
//
//  Created by Lukas Boehler on 23.09.21.
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
@property (nonatomic, retain, nullable) NSDictionary* customData;
@property (nonatomic, retain, nullable) NSNumber* value;

@end

NS_ASSUME_NONNULL_END
