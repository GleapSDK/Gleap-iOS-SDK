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
    
    self.button.layer.cornerRadius = 25;
    
    [Gleap setTags: @[@"Test", @"GleapSDK"]];
    
    [Gleap log: @"This is a test log."];
    [Gleap log: @"This is a test error." withLogLevel: ERROR];
    [Gleap log: @"This is a test info." withLogLevel: INFO];
    [Gleap log: @"This is a test warning." withLogLevel: WARNING];
    
}

- (IBAction)sendData:(id)sender {
    // [Gleap openHelpCenter: NO];
    // [Gleap showSurvey: @"1g9pym"];
    
    /*GleapUserProperty * user = [[GleapUserProperty alloc] init];
    user.name = @"Luko";
    user.email = @"lukas@gleap.io";
    user.customData = @{
        @"testaaa3": @"gg222gg",
        @"test": @"gggg",
    };
    
    [Gleap identifyUserWith: @"23939233334" andData: user];*/
    
    [Gleap startBot: @"64350c6b39c89ea4650c36ae" showBackButton: YES];
}

@end
