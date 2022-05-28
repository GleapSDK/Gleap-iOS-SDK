//
//  GleapUploadManager.h
//  
//
//  Created by Lukas Boehler on 27.05.22.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapUploadManager : NSObject

+ (void)uploadFile: (NSData *)fileData andFileName: (NSString*)filename andContentType: (NSString*)contentType andCompletion: (void (^)(bool success, NSString *fileUrl))completion;
+ (void)uploadImage: (UIImage *)image andCompletion: (void (^)(bool success, NSString *fileUrl))completion;
+ (void)uploadStepImages: (NSArray *)steps andCompletion: (void (^)(bool success, NSArray *fileUrls))completion;
+ (void)uploadFiles: (NSArray *)files forEndpoint:(NSString *)endpoint andCompletion: (void (^)(bool success, NSArray *fileUrls))completion;

@end

NS_ASSUME_NONNULL_END
