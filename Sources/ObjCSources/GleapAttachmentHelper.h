//
//  GleapAttachmentHelper.h
//  
//
//  Created by Lukas Boehler on 27.05.22.
//
//  Internal to the Gleap SDK. This header is only public because every header in
//  Sources/ObjCSources is; it is not part of the supported API and may change without
//  notice. Use the Gleap class (GleapCore.h) instead.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GleapAttachmentHelper : NSObject

+ (instancetype)sharedInstance;

/**
 * Attaches a file to the bug report
 * @author Gleap
 *
 * @param filePath The file to attach to the bug report
 */
+ (bool)addAttachmentWithPath: (NSString *)filePath;

/**
 * Attaches a file to the bug report
 * @author Gleap
 *
 * @param data The data to attach to the bug report
 * @param name The filename including the file extension
 */
+ (bool)addAttachmentWithData: (NSData *)data andName: (NSString *)name;

/**
 * Removes all attachments
 * @author Gleap
 */
+ (void)removeAllAttachments;

@property (retain, nonatomic) NSMutableArray *customAttachments;

@end

NS_ASSUME_NONNULL_END
