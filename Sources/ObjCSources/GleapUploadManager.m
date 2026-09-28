//
//  GleapUploadManager.m
//  
//
//  Created by Lukas Boehler on 27.05.22.
//

#import "GleapUploadManager.h"
#import "GleapSessionHelper.h"
#import "GleapCore.h"
#import "GleapAPIClient.h"

@implementation GleapUploadManager

/*
 Upload file
 */
+ (void)uploadFile: (NSData *)fileData andFileName: (NSString*)filename andContentType: (NSString*)contentType andCompletion: (void (^)(bool success, NSString *fileUrl))completion {
    // A missing name or type is written as "(null)", as the multipart format string always did.
    NSArray *files = fileData != nil ? @[@{ @"data": fileData, @"name": filename ?: @"(null)", @"type": contentType ?: @"(null)" }] : @[];
    NSMutableURLRequest *request = [GleapAPIClient uploadRequestWithPath: @"/uploads/sdk" files: files];
    [GleapAPIClient sendUploadRequest: request completion:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error != NULL || data == nil || ![GleapAPIClient isSuccessResponse: response]) {
            return completion(false, nil);
        }
        
        // The answer has to name the uploaded file.
        id responseDict = [NSJSONSerialization JSONObjectWithData: data options: 0 error: nil];
        id fileUrl = [responseDict isKindOfClass: [NSDictionary class]] ? [responseDict objectForKey: @"fileUrl"] : nil;
        if (![fileUrl isKindOfClass: [NSString class]] || [fileUrl length] == 0) {
            return completion(false, nil);
        }
        return completion(true, fileUrl);
    }];
}

/*
 Upload image
 */
+ (void)uploadImage: (UIImage *)image andCompletion: (void (^)(bool success, NSString *fileUrl))completion {
    NSData *imageData = UIImageJPEGRepresentation(image, 0.8);
    NSString *contentType = @"image/jpeg";
    [self uploadFile: imageData andFileName: @"screenshot.jpeg" andContentType: contentType andCompletion: completion];
}

/*
 Upload SDK steps
 */
+ (void)uploadStepImages: (NSArray *)steps andCompletion: (void (^)(bool success, NSArray *fileUrls))completion {
    // Prepare images for upload.
    NSMutableArray * files = [[NSMutableArray alloc] init];
    for (NSUInteger i = 0; i < steps.count; i++) {
        NSDictionary *currentStep = [steps objectAtIndex: i];
        UIImage *currentImage = [currentStep objectForKey: @"image"];
        
        // Resize screenshot
        CGSize size = CGSizeMake(currentImage.size.width * 0.5, currentImage.size.height * 0.5);
        UIGraphicsBeginImageContext(size);
        [currentImage drawInRect:CGRectMake(0, 0, size.width, size.height)];
        UIImage *destImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        NSData *imageData = UIImageJPEGRepresentation(destImage, 0.9);
        NSString *filename = [NSString stringWithFormat: @"step_%lu", (unsigned long)i];
        
        if (imageData != nil) {
            [files addObject: @{
                @"name": filename,
                @"data": imageData,
                @"type": @"image/jpeg",
            }];
        }
    }
    
    [self uploadFiles: files forEndpoint: @"sdksteps" andCompletion:^(bool success, NSArray *fileUrls) {
        if (success) {
            NSMutableArray *replayArray = [[NSMutableArray alloc] init];
            
            for (NSUInteger i = 0; i < fileUrls.count && i < steps.count; i++) {
                NSMutableDictionary *currentStep = [[steps objectAtIndex: i] mutableCopy];
                NSString *currentImageUrl = [fileUrls objectAtIndex: i];
                [currentStep setObject: currentImageUrl forKey: @"url"];
                [currentStep removeObjectForKey: @"image"];
                [replayArray addObject: currentStep];
            }
            
            return completion(true, replayArray);
        } else {
            return completion(false, nil);
        }
    }];
}

/*
 Upload files
 */
+ (void)uploadFiles: (NSArray *)files forEndpoint:(NSString *)endpoint andCompletion: (void (^)(bool success, NSArray *fileUrls))completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableURLRequest *request = [GleapAPIClient uploadRequestWithPath: [NSString stringWithFormat: @"/uploads/%@", endpoint] files: files];
        [GleapAPIClient sendUploadRequest: request completion:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            if (error != NULL || data == nil || ![GleapAPIClient isSuccessResponse: response]) {
                return completion(false, nil);
            }
            
            // The answer has to name every uploaded file, in the order they were sent: callers
            // match the URLs to their files by position.
            id responseDict = [NSJSONSerialization JSONObjectWithData: data options: 0 error: nil];
            id fileUrls = [responseDict isKindOfClass: [NSDictionary class]] ? [responseDict objectForKey: @"fileUrls"] : nil;
            if (![GleapUploadManager isFileUrlList: fileUrls forFiles: files]) {
                return completion(false, nil);
            }
            return completion(true, fileUrls);
        }];
    });
}

+ (BOOL)isFileUrlList:(id)fileUrls forFiles:(NSArray *)files {
    if (![fileUrls isKindOfClass: [NSArray class]] || [fileUrls count] != files.count) {
        return NO;
    }
    for (id fileUrl in fileUrls) {
        if (![fileUrl isKindOfClass: [NSString class]]) {
            return NO;
        }
    }
    return YES;
}

@end
