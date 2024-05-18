//
//  GleapAiTool.h
//  
//
//  Created by Lukas Boehler on 08.03.24.
//

#import <Foundation/Foundation.h>
#import "GleapAiToolParameter.h"

NS_ASSUME_NONNULL_BEGIN

@interface GleapAiTool : NSObject

@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *toolDescription; // Renamed to avoid conflict
@property (nonatomic, strong) NSString *response;
@property (nonatomic, strong) NSString *executionType; // button or auto.
@property (nonatomic, strong) NSArray<GleapAiToolParameter *> *parameters;

- (instancetype)initWithName:(NSString *)name
              toolDescription:(NSString *)description
                     response:(NSString *)response
                executionType:(NSString *)executionType
                   parameters:(NSArray<GleapAiToolParameter *> *)parameters;

- (NSDictionary *)toDictionary;

@end

NS_ASSUME_NONNULL_END
