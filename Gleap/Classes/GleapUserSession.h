//
//  GleapUserSession.h
//  Gleap
//
//  Created by Lukas Boehler on 23.09.21.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapUserSession : NSObject

@property (nonatomic, retain) NSString* userId;
@property (nonatomic, retain) NSString* userHash;
@property (nonatomic, retain) NSString* name;
@property (nonatomic, retain) NSString* email;

@end

NS_ASSUME_NONNULL_END
