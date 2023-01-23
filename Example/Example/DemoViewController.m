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
    return UIInterfaceOrientationMaskPortrait;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    self.button.layer.cornerRadius = 25;
    
    [Gleap log: @"This is a test log."];
    [Gleap log: @"This is a test error." withLogLevel: ERROR];
    [Gleap log: @"This is a test info." withLogLevel: INFO];
    [Gleap log: @"This is a test warning." withLogLevel: WARNING];
}

- (IBAction)sendData:(id)sender {
    // [Gleap openHelpCenter: NO];
    // [Gleap showSurvey: @"1g9pym"];
}

@end
