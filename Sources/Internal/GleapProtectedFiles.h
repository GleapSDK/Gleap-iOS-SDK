//
//  GleapProtectedFiles.h
//  Gleap
//
//  Opens the project's protected conversation files (https://files.gleap.io/af/<id>) in the
//  app. Their bytes can only be read with the session's file session (X-File-Session), which a
//  browser does not have, so the SDK downloads the file itself and shows it with QuickLook,
//  where the share button saves it (Files, AirDrop, …).
//

#import <UIKit/UIKit.h>
#import "GleapInternal.h"

NS_ASSUME_NONNULL_BEGIN

GLEAP_INTERNAL
@interface GleapProtectedFiles : NSObject

/// The file id when `url` is a protected file of the configured API region: https on
/// files.gleap.io (files.us.gleap.ai for the US API) without port or user info, path
/// /af/<id> or /files/af/<id>; or the API's own origin when the API runs on localhost. nil for
/// any other URL: the file session is never sent anywhere else.
+ (nullable NSString *)fileIdOfURL:(nullable NSString *)url;

/// Deletes the files downloaded so far (logout).
+ (void)removeDownloadedFiles;

/// `presenter` shows the file; it is held weakly.
- (instancetype)initWithPresenter:(UIViewController *)presenter;

/// Downloads `url` with the file session and shows it. Without a valid file session the file
/// waits (the file session is renewed) and opens with the next sessionDidChange. A later call
/// replaces a file that is still loading or waiting. NO, and nothing is requested, when `url`
/// is not a protected file.
- (BOOL)openFileAtURL:(nullable NSString *)url name:(nullable NSString *)name;

/// The session changed: a file waiting for a file session opens now.
- (void)sessionDidChange;

/// Tests only: replaces the QuickLook presentation of a downloaded file.
@property (nonatomic, copy, nullable) void (^presentFile)(NSURL *fileURL);

@end

NS_ASSUME_NONNULL_END
