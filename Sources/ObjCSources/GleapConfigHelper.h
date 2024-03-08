//
//  GleapConfigHelper.h
//  
//
//  Created by Lukas Boehler on 25.05.22.
//

#import <Foundation/Foundation.h>
#import "GleapAiTool.h"

NS_ASSUME_NONNULL_BEGIN

@interface GleapConfigHelper : NSObject

+ (instancetype)sharedInstance;
- (void)run;
- (int)getButtonX;
- (int)getButtonY;
- (void)setAiTools:(NSArray<GleapAiTool *> *)aiTools;

@property (nonatomic, retain) NSDictionary* config;
@property (nonatomic, retain) NSDictionary* projectActions;
@property (nonatomic, retain) NSArray* internalAiTools;

@end

NS_ASSUME_NONNULL_END
