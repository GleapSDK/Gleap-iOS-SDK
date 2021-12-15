//
//  DemoViewController.m
//  Example
//
//  Created by Lukas Boehler on 15.12.21.
//

#import "DemoViewController.h"

@interface DemoViewController ()

@end

@implementation DemoViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

- (IBAction)doIt:(id)sender {
    NSError *error;
    NSString *urlString = @"https://run.mocky.io/v3/9290950e-5219-4cec-ab01-4b15dfbad6fe";
    NSURL *url = [NSURL URLWithString:urlString];

    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];

    [request setHTTPMethod:@"POST"];

    [request setURL:url];

    [request addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSData *postData = [@"{ \"secure\": \"asdf\", \"secure2\": \"xoxo\" }" dataUsingEncoding:NSUTF8StringEncoding];

    [request setValue: @"asdf" forHTTPHeaderField: @"secure"];
    
    [request setHTTPBody:postData];

    NSData *finalDataToDisplay = [NSURLConnection sendSynchronousRequest:request returningResponse:nil error:&error];

    NSMutableDictionary *abc = [NSJSONSerialization JSONObjectWithData: finalDataToDisplay
                                                               options: NSJSONReadingMutableContainers

                                                                error: &error];
    NSLog(@"%@",abc);
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
