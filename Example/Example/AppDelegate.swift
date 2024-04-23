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
        
        //Gleap.setApiUrl("http://0.0.0.0:9000")
        //Gleap.setFrameUrl("http://0.0.0.0:3001/appnew.html")
        Gleap.initialize(withToken: "Vx0SXWPHGU7Af54CabNL07k6HRELKTxu")
        
        Gleap.sharedInstance().delegate = self
        
        // Attach custom data sample.
        Gleap.attachCustomData(["value": "Unicorn", "type": "Demo", "ExtraInfo": ["Age": "28", "City": "San Francisco"]])
        
        Gleap.showFeedbackButton(true)
        
        let userProp = GleapUserProperty()
        userProp.name = "TEST1"
        userProp.email = "lukas@gleap.io"
        userProp.customData = ["test": "asdfasdf", "asdfasdfasdf": 123]
        
        Gleap.identifyContact("testuser2", andData: userProp)
        
        // Testing file attachments.
        if let data = "Dies ist ein test.".data(using: String.Encoding.utf8) {
            Gleap.addAttachment(with: data, andName: "text.txt")
        }
        
        let userProperty = GleapUserProperty()
        userProperty.name = "Franz"
        userProperty.email = "franz@gleap.io"
        userProperty.phone = "+1 (902) 123123"
        userProperty.value = 199.95
        userProperty.plan = "Pro plan";
        userProperty.companyId = "29883";
        userProperty.companyName = "ACME inc.";
        userProperty.customData = ["key1": "Custom data"];

        Gleap.identifyContact("user_1234", andData: userProperty)
        
        Gleap.setNetworkLogsBlacklist(["https://api.gleap.io", "..."])
        
        let aiTool = GleapAiTool(
            name: "send-money",
            toolDescription: "Send money to contacts.",
            response: "Money transfere is initiaed and requires pin entry of user.",
            parameters: [
                GleapAiToolParameter(
                    name: "amount",
                    parameterDescription: "The amount to transfere.",
                    type: "string",
                    required: true
                )
            ])
        
        Gleap.setAiTools([aiTool])
        
        Gleap.setTicketAttributeWithKey("testattr", value: "Some demo :)")
        Gleap.setTicketAttributeWithKey("test2", value: "Some 1234 :)")
        
        // Some demo logs.
        print("App started.")
        print("User logged in.")
        
        return true
    }
    
    func onToolExecution(_ toolExecution: [AnyHashable : Any]) {
        guard let name = toolExecution["name"] as? String else {
            return
        }
        
        print("Tool: " + name)
        print(toolExecution["params"] ?? "No params.")
    }
    
    func registerPushMessageGroup(_ pushMessageGroup: String) {
        NSLog("Register: " + pushMessageGroup)
    }
    
    func unregisterPushMessageGroup(_ pushMessageGroup: String) {
        NSLog("Unregister: " + pushMessageGroup)
    }
    
    func initialized() {
        
    }
    
    func notificationCountUpdated(_ count: Int32) {
        NSLog("Count updated. %i", count);
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

