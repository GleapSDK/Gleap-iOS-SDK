//
//  DemoViewController.m
//  Example
//
//  Created by Lukas Boehler on 15.12.21.
//

#import "DemoViewController.h"
@import Gleap;

@interface DemoViewController ()
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
    
    [Gleap startNetworkRecording];
    
    self.button.layer.cornerRadius = 25;
}

- (IBAction)demo:(id)sender {
}

- (IBAction)sendData:(id)sender {
    [Gleap showFeedbackButton: YES];
    [Gleap trackEvent: @"test"];
}

@end
