//
//  AppDelegate.swift
//  Example
//
//  Created by Lukas Boehler on 05.12.21.
//

import UIKit
import Gleap

@main
class AppDelegate: UIResponder, UIApplicationDelegate, GleapDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        Gleap.enableDebugConsoleLog()
        Gleap.initialize(withToken: "HgJqsnj9cdCBP8u8YSWD8wL9MYWjb5CD")
        Gleap.sharedInstance().delegate = self
        let userData = GleapUserProperty()
        userData.email = "max@gleap.io"
        userData.name = "Max"
        Gleap.identifyUser(with: "1928382", andData: userData)
        
        Gleap.attachCustomData(["value": "Unicorn", "type": "Demo", "ExtraInfo": ["Age": "28", "City": "San Francisco"]])
        
        print("App started.")
        print("User logged in.")
        
        return true
    }
    
    func feedbackSent(_ data: [AnyHashable : Any]) {
        dump(data)
    }
    
    func customActionCalled(_ customAction: String) {
        NSLog(customAction)
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }


}

