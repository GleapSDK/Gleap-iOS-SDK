//
//  BBAFURLSessionManager.m
//  Gleap_Example
//
//  Created by Lukas Boehler on 29.03.21.
//  Copyright © 2021 Lukas Böhler. All rights reserved.
//

#import "BBAFURLSessionManager.h"
#import <Gleap/Gleap.h>

@implementation BBAFURLSessionManager

- (instancetype)initWithSessionConfiguration:(nullable NSURLSessionConfiguration *)configuration {
    [Gleap startNetworkRecordingForSessionConfiguration: configuration];
    
    return [super initWithSessionConfiguration:configuration];
}

@end
