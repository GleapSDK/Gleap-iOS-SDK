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
        
        Gleap.setDisableInAppNotifications(false);
        
        Gleap.setLanguage("de")
        
        //Gleap.setApiUrl("http://localhost:9000")
        //Gleap.setFrameUrl("http://localhost:3001/appnew.html")
        Gleap.initialize(withToken: "hciNpT8z64tsHATINYZjWBvbirVWCKWt")
        
        Gleap.sharedInstance().delegate = self
        
        Gleap.trackEvent("asfasdfasdf")
        
        // Attach custom data sample.
        Gleap.attachCustomData(["value": "Unicorn", "type": "Demo", "ExtraInfo": ["Age": "28", "City": "San Francisco"]])
        
        Gleap.showFeedbackButton(true)
        
        /*Gleap.handlePushNotification([
            "type": "news",
            "id": "12"
        ])*/
        //Gleap.clearIdentity()
        
        // Testing file attachments.
        if let data = "Dies ist ein test.".data(using: String.Encoding.utf8) {
            Gleap.addAttachment(with: data, andName: "text.txt")
        }
        
        // Some demo logs.
        print("App started.")
        print("User logged in.")
        
        return true
    }
    
    func registerPushMessageGroup(_ pushMessageGroup: String) {
        NSLog("Register: " + pushMessageGroup)
    }
    
    func unregisterPushMessageGroup(_ pushMessageGroup: String) {
        NSLog("Unregister: " + pushMessageGroup)
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

