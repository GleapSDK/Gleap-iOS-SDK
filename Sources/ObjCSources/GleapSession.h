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
@property (nonatomic, retain) NSString* userId;
@property (nonatomic, retain) NSString* name;
@property (nonatomic, retain) NSString* email;

@end

NS_ASSUME_NONNULL_END
