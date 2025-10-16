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
    
    self.button.layer.cornerRadius = 25;
}

- (IBAction)demo:(id)sender {
    [Gleap askAI: @"What is Gleap?"];
}

- (IBAction)sendData:(id)sender {
    [Gleap askAI: @"What is Gleap?"];
}

- (NSData *)certificateDataFromString:(NSString *)base64String {
    NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:base64String options:0];
    return decodedData;
}

@end
