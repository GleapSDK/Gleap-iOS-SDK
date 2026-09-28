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
        if (error != NULL) {
            return completion(false, nil);
        }
        
        NSError *parseError = nil;
        NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData: data options: 0 error:&parseError];
        if (!parseError) {
            NSString* fileUrl = [responseDict objectForKey: @"fileUrl"];
            return completion(true, fileUrl);
        } else {
            return completion(false, nil);
        }
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
    for (int i = 0; i < steps.count; i++) {
        NSDictionary *currentStep = [steps objectAtIndex: i];
        UIImage *currentImage = [currentStep objectForKey: @"image"];
        
        // Resize screenshot
        CGSize size = CGSizeMake(currentImage.size.width * 0.5, currentImage.size.height * 0.5);
        UIGraphicsBeginImageContext(size);
        [currentImage drawInRect:CGRectMake(0, 0, size.width, size.height)];
        UIImage *destImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        NSData *imageData = UIImageJPEGRepresentation(destImage, 0.9);
        NSString *filename = [NSString stringWithFormat: @"step_%i", i];
        
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
            
            for (int i = 0; i < fileUrls.count; i++) {
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
            if (error != NULL) {
                return completion(false, nil);
            }
            
            NSError *parseError = nil;
            NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData: data options: 0 error:&parseError];
            if (!parseError) {
                NSArray* fileUrls = [responseDict objectForKey: @"fileUrls"];
                return completion(true, fileUrls);
            } else {
                return completion(false, nil);
            }
        }];
    });
}

@end
