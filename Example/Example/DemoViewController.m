//
//  DemoViewController.m
//  Example
//
//  Created by Lukas Boehler on 15.12.21.
//

#import "DemoViewController.h"
#import <Foundation/Foundation.h>

@import Gleap;

@interface DemoViewController () <NSURLSessionDelegate>
@property (weak, nonatomic) IBOutlet UIButton *button;

@end

@implementation DemoViewController

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    [self makeSecureRequest];
    
    self.button.layer.cornerRadius = 25;
}

- (IBAction)demo:(id)sender {
}

- (IBAction)sendData:(id)sender {
    [Gleap showFeedbackButton: YES];
    [Gleap trackEvent: @"test"];
}

- (void)makeSecureRequest {
    NSURL *url = [NSURL URLWithString:@"https://www.gleap.io"];
    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];

    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig
                                                          delegate:self
                                                     delegateQueue:nil];

    NSURLSessionDataTask *task = [session dataTaskWithURL:url
                                        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"Request failed: %@", error.localizedDescription);
            return;
        }
        
        NSLog(@"Response: %@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
    }];

    [task resume];
}

- (NSData *)certificateDataFromString:(NSString *)base64String {
    NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:base64String options:0];
    return decodedData;
}

#pragma mark - NSURLSessionDelegate

// SSL Pinning
- (void)URLSession:(NSURLSession *)session
        didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
        completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {
    
    // Convert Base64 certificate string to NSData
    NSData *certData = [self certificateDataFromString: @"MIIE4DCCA8igAwIBAgISBOc9a3nzEi0vsZ1e/6uCVuK3MA0GCSqGSIb3DQEBCwUAMDMxCzAJBgNVBAYTAlVTMRYwFAYDVQQKEw1MZXQncyBFbmNyeXB0MQwwCgYDVQQDEwNSMTAwHhcNMjUwMzAzMjMxNzMwWhcNMjUwNjAxMjMxNzI5WjATMREwDwYDVQQDEwhnbGVhcC5pbzCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKNtrKd0ukZc1dw26iIqZ5JnwvBdQRqBda+Hesa6/kSa8pEfVxnIIRSGsnO2Qj4xAWgSh7PQFnxQ5dXI47Q7EIRq36/updK5Id4bFQp+JDhgtfVw3uxqG9C2jbjhQy7lSxuJ6EsyLRBCFB+Gq+l43rN2xopRX4Wd7Za8YfVRLW3L7wIU0Y2MXUplOKzux6NTwRBp3r5EQEAOno86SkG1mnxYLOCwVfXb7mvhVOk2XekMmpJFAVWtGAmDimESsnToi9UNdgpeDV7d8pM8HhiKVEqIqDsI4tgvzTw3EHUckcVJ85pXBsoRoqSLYVuMcw3Q0MxI0FMDDBexi8QcRG0BIgMCAwEAAaOCAgwwggIIMA4GA1UdDwEB/wQEAwIFoDAdBgNVHSUEFjAUBggrBgEFBQcDAQYIKwYBBQUHAwIwDAYDVR0TAQH/BAIwADAdBgNVHQ4EFgQUCDSmIh94SM8NMfDndGLSsnVXr/EwHwYDVR0jBBgwFoAUu7zDR6XkvKnGw6RyDBCNojXhyOgwVwYIKwYBBQUHAQEESzBJMCIGCCsGAQUFBzABhhZodHRwOi8vcjEwLm8ubGVuY3Iub3JnMCMGCCsGAQUFBzAChhdodHRwOi8vcjEwLmkubGVuY3Iub3JnLzATBgNVHREEDDAKgghnbGVhcC5pbzATBgNVHSAEDDAKMAgGBmeBDAECATCCAQQGCisGAQQB1nkCBAIEgfUEgfIA8AB3AHMgIg8IFor588SmiwqyappKAO71d4WKCE0FANSlQkRZAAABlV6CbskAAAQDAEgwRgIhAMXoIeQq85QYaisu0H8winY2rndCTmZ11ozyqVPAVv4LAiEA7bjkU774BheKIy7OnSlGO2TvM2xCZEOFTCpfH7RxCwcAdQATSt8atZhCCXgMb+9MepGkFrcjSc5YV2rfrtqnwqvgIgAAAZVegm+gAAAEAwBGMEQCIFiHe5clhrIyvfzmpNxRMUXrwkwP4g9zSUKSu6c4GMcqAiACLuYi9B32R8jeFa1NV+j7hIFuHKg0Ap3e1H/qartoqjANBgkqhkiG9w0BAQsFAAOCAQEATAr3VHWjBSHx42LCVappV2J/sfnD5cvLP58PKeKWTOY4EnU0TncobYM+/j+kfmyFWqa2FT2f7xDzC2E3bfRdoIX9RG2AVVotDkl79k5Vxb6RFNM495vS0UFejYeImT8mEqpXUuk19BS4KYxM26vQsWiNL/6kfk7YiZCvuEoHU7TI6RMtO3raBLPbxOAi8jV1mTzcY9Vy3Ho37oWlU3AxlFcu5FgOpHlcNjXiPW/89nIR6ik1Uo/jI81IRr2iNhMoLYY4DeG3AN2+U7xjKbIt+qvNTurFrVB8vqwS9t33KlQBDzelTWgZ/rN/ZQb++BIEoi+zbyX7u6Dfl1vM7y9VPA=="];
    if (!certData) {
        NSLog(@"Failed to decode certificate from string");
        completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
        return;
    }

    // Get the server's trust object
    SecTrustRef serverTrust = challenge.protectionSpace.serverTrust;
    SecCertificateRef serverCertificate = SecTrustGetCertificateAtIndex(serverTrust, 0);
    NSData *serverCertData = (__bridge_transfer NSData *)SecCertificateCopyData(serverCertificate);

    // Compare server certificate with the pinned one
    if ([serverCertData isEqualToData:certData]) {
        NSURLCredential *credential = [NSURLCredential credentialForTrust:serverTrust];
        completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
    } else {
        completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
        NSLog(@"SSL Pinning failed: certificate mismatch.");
    }
}

@end
