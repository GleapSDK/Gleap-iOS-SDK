//
//  BBAppDelegate.m
//  Gleap
//
//  Created by Lukas Böhler on 06/12/2019.
//  Copyright (c) 2019 Lukas Böhler. All rights reserved.
//

#import "BBAppDelegate.h"
#import <Gleap/Gleap.h>

@implementation BBAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // Override point for customization after application launch.
    
    [Gleap setApiUrl: @"https://api.gleap.dev"];
    [Gleap setWidgetUrl: @"https://widget.gleap.dev"];
    
    GleapUserSession *userSession = [[GleapUserSession alloc] init];
    userSession.userId = @"1";
    userSession.userHash = @"db5897fe20d33d8072babc477655eba5240e606cbde86deaa0c17e34eaef6201";
    userSession.name = @"Franz";
    userSession.email = @"lukas@boehlerbrothers.com";
    
    [Gleap initializeWithToken: @"OcLgYN5vWavsjTrv1vjAjGj22INW0Xdz" andUserSession: userSession];
    
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

@end
