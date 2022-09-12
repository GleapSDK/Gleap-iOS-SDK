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
        // Gleap.setApiUrl("http://192.168.200.16:9000")
        // Gleap.setFrameUrl("http://192.168.200.16:3001/app.html")
        Gleap.initialize(withToken: "KProDXhMS0V3UUku2iNnrZ4XsBnAYzxt")
        
        Gleap.sharedInstance().delegate = self
        
        // Attach custom data sample.
        Gleap.attachCustomData(["value": "Unicorn", "type": "Demo", "ExtraInfo": ["Age": "28", "City": "San Francisco"]])
        
        // Gleap.clearIdentity()
        let userProps = GleapUserProperty()
        userProps.email = "lukas3+test@gleap.io"
        userProps.name = "Franz A"
        userProps.value = 344
        Gleap.identifyUser(with: "user_132933", andData: userProps)
        
        // Testing file attachments.
        if let data = "Dies ist ein test.".data(using: String.Encoding.utf8) {
            Gleap.addAttachment(with: data, andName: "text.txt")
        }
        
        // Some demo logs.
        print("App started.")
        print("User logged in.")
        
        return true
    }
    
    func widgetClosed() {
        NSLog("Closed widget.")
    }
    
    func widgetOpened() {
        NSLog("Opened widget.")
    }
    
    func feedbackFlowStarted(_ feedbackAction: [AnyHashable : Any]) {
        NSLog("Started feedback flow", feedbackAction)
    }
    
    func feedbackSendingFailed() {
        NSLog("Sending feedback failed")
    }
    
    func feedbackSent(_ data: [AnyHashable : Any]) {
        NSLog("Feedback sent", data)
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

