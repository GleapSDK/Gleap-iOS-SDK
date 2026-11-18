//
//  GleapProtectedFiles.m
//  Gleap
//

#import "GleapProtectedFiles.h"
#import "GleapAPIClient.h"
#import "GleapCore.h"
#import "GleapSession.h"
#import "GleapSessionHelper.h"
#import <QuickLook/QuickLook.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString * const kGleapProtectedFilesFolder = @"gleap-files";

/// Never follows a redirect: the file session stays with the files host.
GLEAP_INTERNAL
@interface GleapProtectedFilesNoRedirect : NSObject <NSURLSessionTaskDelegate>
@end

@implementation GleapProtectedFilesNoRedirect

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    completionHandler(nil);
}

@end

@interface GleapProtectedFiles () <QLPreviewControllerDataSource, QLPreviewControllerDelegate>

@property (nonatomic, weak) UIViewController *presenter;
// The file to open next: waits here for a file session.
@property (nonatomic, copy, nullable) NSString *pendingURL;
@property (nonatomic, copy, nullable) NSString *pendingName;
@property (nonatomic, strong, nullable) NSURLSessionDownloadTask *task;
// Bumped by every download: only the latest one is shown.
@property (nonatomic, assign) NSUInteger download;
@property (nonatomic, strong, nullable) NSURL *shownFile;

@end

@implementation GleapProtectedFiles

#pragma mark - Protected file URLs

+ (nullable NSString *)fileIdOfURL:(nullable NSString *)value {
    if (![value isKindOfClass: [NSString class]]) {
        return nil;
    }
    NSURLComponents *file = [NSURLComponents componentsWithString: value];
    NSURLComponents *api = [NSURLComponents componentsWithString: Gleap.sharedInstance.apiUrl ?: @""];
    if (file == nil || file.user != nil || file.password != nil || file.host.length == 0) {
        return nil;
    }
    NSString *scheme = [file.scheme lowercaseString];
    NSString *host = [file.host lowercaseString];
    NSString *apiHost = [api.host lowercaseString] ?: @"";
    BOOL trusted;
    if ([apiHost isEqualToString: @"localhost"] || [apiHost isEqualToString: @"127.0.0.1"]) {
        // Development: the local API serves the files itself.
        trusted = [scheme isEqualToString: [api.scheme lowercaseString]] && [host isEqualToString: apiHost] &&
            (file.port == api.port || [file.port isEqual: api.port]);
    } else {
        NSString *filesHost = [apiHost hasSuffix: @".us.gleap.ai"] ? @"files.us.gleap.ai" : @"files.gleap.io";
        trusted = [scheme isEqualToString: @"https"] && file.port == nil && [host isEqualToString: filesHost];
    }
    if (!trusted) {
        return nil;
    }
    NSString *path = file.percentEncodedPath ?: @"";
    NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern: @"^(?:/files)?/af/([a-f0-9]{24})$" options: 0 error: nil];
    NSTextCheckingResult *match = [pattern firstMatchInString: path options: 0 range: NSMakeRange(0, path.length)];
    return match != nil ? [path substringWithRange: [match rangeAtIndex: 1]] : nil;
}

#pragma mark - Opening

- (instancetype)initWithPresenter:(UIViewController *)presenter {
    self = [super init];
    if (self) {
        _presenter = presenter;
    }
    return self;
}

- (BOOL)openFileAtURL:(nullable NSString *)url name:(nullable NSString *)name {
    if ([GleapProtectedFiles fileIdOfURL: url] == nil) {
        return NO;
    }
    // The latest tap wins.
    [self.task cancel];
    self.task = nil;
    self.download++;
    self.pendingURL = url;
    self.pendingName = [name isKindOfClass: [NSString class]] ? name : nil;
    [self openPendingFile];
    return YES;
}

- (void)sessionDidChange {
    [self openPendingFile];
}

- (void)openPendingFile {
    GleapSession *session = GleapSessionHelper.sharedInstance.currentSession;
    if (self.pendingURL == nil || self.task != nil) {
        return;
    }
    if (![session hasFileAccess]) {
        // Expired while the app was in the background: renewed with the app's last identify,
        // whose answer brings the next sessionDidChange.
        [GleapSessionHelper.sharedInstance refreshFileAccessIfNeeded];
        return;
    }
    NSURL *url = [NSURL URLWithString: self.pendingURL];
    NSString *name = self.pendingName;
    self.pendingURL = nil;
    self.pendingName = nil;
    NSString *owner = session.gleapId;
    NSUInteger download = ++self.download;

    // Only the file session: the files host is not the API and gets no other credential.
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL: url cachePolicy: NSURLRequestReloadIgnoringLocalCacheData timeoutInterval: 60];
    [request setValue: session.fileAccessToken forHTTPHeaderField: @"X-File-Session"];
    __weak GleapProtectedFiles *weakSelf = self;
    self.task = [[GleapProtectedFiles session] downloadTaskWithRequest: request completionHandler:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        // The file at `location` is deleted once this block returns.
        NSURL *file = nil;
        if (error == nil && location != nil && [GleapAPIClient isSuccessResponse: response]) {
            file = [GleapProtectedFiles keepDownloadAt: location name: name response: response];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf finishDownload: download file: file owner: owner];
        });
    }];
    [self.task resume];
}

- (void)finishDownload:(NSUInteger)download file:(nullable NSURL *)file owner:(NSString *)owner {
    if (download != self.download) {
        // Replaced by a later file meanwhile.
        [GleapProtectedFiles removeFolderOf: file];
        return;
    }
    self.task = nil;
    // A logout or another user meanwhile: the file is not theirs.
    GleapSession *session = GleapSessionHelper.sharedInstance.currentSession;
    if (file == nil || ![session hasFileAccess] || ![session.gleapId isEqualToString: owner]) {
        if (file == nil) {
            NSLog(@"[GLEAP_SDK] The file could not be downloaded.");
        }
        [GleapProtectedFiles removeFolderOf: file];
        return;
    }
    [self showFile: file];
}

- (void)showFile:(NSURL *)file {
    if (self.presentFile != nil) {
        self.presentFile(file);
        return;
    }
    UIViewController *presenter = self.presenter;
    if (presenter == nil || presenter.view.window == nil || presenter.presentedViewController != nil) {
        // The widget closed or shows something else meanwhile.
        [GleapProtectedFiles removeFolderOf: file];
        return;
    }
    self.shownFile = file;
    QLPreviewController *preview = [[QLPreviewController alloc] init];
    preview.dataSource = self;
    preview.delegate = self;
    [presenter presentViewController: preview animated: YES completion: nil];
}

#pragma mark - QuickLook

- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller {
    return self.shownFile != nil ? 1 : 0;
}

- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index {
    return self.shownFile;
}

- (void)previewControllerDidDismiss:(QLPreviewController *)controller {
    [GleapProtectedFiles removeFolderOf: self.shownFile];
    self.shownFile = nil;
}

#pragma mark - Files

+ (NSURLSession *)session {
    static NSURLSession *session = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        // Nothing of a protected file is kept outside the SDK's own folder.
        configuration.URLCache = nil;
        configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        configuration.HTTPShouldSetCookies = NO;
        configuration.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyNever;
        session = [NSURLSession sessionWithConfiguration: configuration delegate: [GleapProtectedFilesNoRedirect new] delegateQueue: nil];
    });
    return session;
}

+ (NSURL *)folder {
    NSURL *caches = [[[NSFileManager defaultManager] URLsForDirectory: NSCachesDirectory inDomains: NSUserDomainMask] firstObject];
    return [caches URLByAppendingPathComponent: kGleapProtectedFilesFolder isDirectory: YES];
}

+ (void)removeDownloadedFiles {
    [[NSFileManager defaultManager] removeItemAtURL: [self folder] error: nil];
}

+ (void)removeFolderOf:(nullable NSURL *)file {
    if (file != nil) {
        [[NSFileManager defaultManager] removeItemAtURL: [file URLByDeletingLastPathComponent] error: nil];
    }
}

/// Moves a finished download to its own folder under its file name. Nothing is shown while a
/// file downloads, so earlier files (from an app that ended while one was shown) go first.
+ (nullable NSURL *)keepDownloadAt:(NSURL *)location name:(nullable NSString *)name response:(NSURLResponse *)response {
    NSFileManager *files = [NSFileManager defaultManager];
    [self removeDownloadedFiles];
    NSURL *folder = [[self folder] URLByAppendingPathComponent: [[NSUUID UUID] UUIDString] isDirectory: YES];
    NSURL *file = [folder URLByAppendingPathComponent: [self fileNameFor: name response: response] isDirectory: NO];
    if (![files createDirectoryAtURL: folder withIntermediateDirectories: YES attributes: nil error: nil] ||
        ![files moveItemAtURL: location toURL: file error: nil]) {
        [files removeItemAtURL: folder error: nil];
        return nil;
    }
    return file;
}

/// The name the file is shown and saved under: the attachment's name, else the server's; with
/// the extension of its type when it has none, so QuickLook knows how to show it.
+ (NSString *)fileNameFor:(nullable NSString *)name response:(NSURLResponse *)response {
    NSString *base = [self cleanFileName: name];
    if (base.length == 0) {
        base = [self cleanFileName: response.suggestedFilename];
    }
    if (base.length == 0) {
        base = @"file";
    }
    BOOL hasExtension = [base rangeOfString: @"\\.[A-Za-z0-9]{1,8}$" options: NSRegularExpressionSearch].location != NSNotFound;
    NSString *extension = response.MIMEType.length > 0 ? [UTType typeWithMIMEType: response.MIMEType].preferredFilenameExtension : nil;
    return hasExtension || extension.length == 0 ? base : [base stringByAppendingPathExtension: extension];
}

/// The last part of `name` (a link's text can be a URL), without characters a file name cannot hold.
+ (NSString *)cleanFileName:(nullable NSString *)name {
    if (![name isKindOfClass: [NSString class]]) {
        return @"";
    }
    NSString *trimmed = [name stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSRange separator = [trimmed rangeOfCharacterFromSet: [NSCharacterSet characterSetWithCharactersInString: @"/\\:"] options: NSBackwardsSearch];
    NSString *last = separator.location == NSNotFound ? trimmed : [trimmed substringFromIndex: NSMaxRange(separator)];
    last = [[last componentsSeparatedByCharactersInSet: [NSCharacterSet controlCharacterSet]] componentsJoinedByString: @""];
    if ([last isEqualToString: @"."] || [last isEqualToString: @".."]) {
        return @"";
    }
    return last.length > 120 ? [last substringFromIndex: last.length - 120] : last;
}

@end
