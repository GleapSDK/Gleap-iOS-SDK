//
//  GleapAttachmentHelper.m
//  
//
//  Created by Lukas Boehler on 27.05.22.
//

#import "GleapAttachmentHelper.h"

@implementation GleapAttachmentHelper

/*
 Returns a shared instance (singleton).
 */
+ (instancetype)sharedInstance
{
    static GleapAttachmentHelper *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GleapAttachmentHelper alloc] init];
    });
    return sharedInstance;
}

- (id)init {
    self = [super init];
    if (self) {
        self.customAttachments = [[NSMutableArray alloc] init];
    }
    return self;
}

/**
 * Attaches a file to the bug report
 */
+ (bool)addAttachmentWithPath: (NSString *)filePath {
    if (![[NSFileManager defaultManager] fileExistsAtPath: filePath]) {
        return false;
    }
    
    NSError* error = nil;
    NSData* data = [NSData dataWithContentsOfFile: filePath options:0 error: &error];
    if (error == nil && data != nil) {
        return [self addAttachmentWithData: data andName: filePath];
    } else {
        return false;
    }
}

+ (bool)addAttachmentWithData:(NSData *)data andName:(NSString *)name {
    if ([GleapAttachmentHelper sharedInstance].customAttachments.count > 6) {
        NSLog(@"[GLEAP_SDK] Attachment limit of 6 files reached.");
        return false;
    }
    
    NSString * mimeType = @"text/plain";
    NSString *pathExtension = [name pathExtension];
    
    if ([pathExtension isEqualToString: @"json"]) {
        mimeType = @"application/json";
    }
    if ([pathExtension isEqualToString: @"xml"]) {
        mimeType = @"application/xml";
    }
    if ([pathExtension isEqualToString: @"svg"]) {
        mimeType = @"image/svg+xml";
    }
    if ([pathExtension isEqualToString: @"jpg"] || [pathExtension isEqualToString: @"jpeg"]) {
        mimeType = @"image/jpeg";
    }
    if ([pathExtension isEqualToString: @"png"]) {
        mimeType = @"image/png";
    }
    if ([pathExtension isEqualToString: @"mp4"]) {
        mimeType = @"video/mp4";
    }
    
    [[GleapAttachmentHelper sharedInstance].customAttachments addObject: @{
        @"name": [name lastPathComponent],
        @"data": data,
        @"type": mimeType,
    }];
    
    return true;
}

/**
 * Removes all attachments
 */
+ (void)removeAllAttachments {
    [[GleapAttachmentHelper sharedInstance].customAttachments removeAllObjects];
}

@end
