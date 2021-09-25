//
//  BBRecipeViewController.m
//  Gleap_Example
//
//  Created by Lukas Boehler on 28.01.21.
//  Copyright © 2021 Lukas Böhler. All rights reserved.
//

#import "BBRecipeViewController.h"

@interface BBRecipeViewController ()

@end

@implementation BBRecipeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    for (int i = 0; i < 8; i++) {
        NSLog(@"More demo logs %i", i);
    }
    
    NSLog(@"Selected 'Superb Steak'.");
    NSLog(@"Showing details for 'Superb Steak'.");
    
    self.title = @"Recipe Details";
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
