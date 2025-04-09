//
//  GleapUserSession.h
//  Gleap
//
//  Created by Lukas Boehler on 23.09.21.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapUserProperty : NSObject

@property (nonatomic, retain) NSString* name;
@property (nonatomic, retain) NSString* email;
@property (nonatomic, retain) NSString* phone;
@property (nonatomic, retain) NSNumber* value;
@property (nonatomic, retain) NSNumber* sla;
@property (nonatomic, retain) NSString* plan;
@property (nonatomic, retain) NSString* companyName;
@property (nonatomic, retain) NSString* companyId;
@property (nonatomic, retain) NSString* avatar;
@property (nonatomic, retain) NSDictionary* customData;

- (NSDictionary *)dataDictToSendWith:(NSString * _Nullable)userId and:(NSString * _Nullable)userHash;

@end

NS_ASSUME_NONNULL_END
