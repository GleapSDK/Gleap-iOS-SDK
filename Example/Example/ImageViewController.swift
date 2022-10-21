//
//  ImageViewController.swift
//  Example
//
//  Created by Lukas Boehler on 08.07.22.
//

import UIKit
import Gleap

class ImageViewController: UIViewController, UINavigationControllerDelegate, UITabBarControllerDelegate {
    @IBOutlet weak var button: UIButton!
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .landscape
    }
    
    override var shouldAutorotate: Bool {
        return true
    }
    
    func tabBarControllerSupportedInterfaceOrientations(_ tabBarController: UITabBarController) -> UIInterfaceOrientationMask {
        return .portrait
    }
    
    func navigationControllerSupportedInterfaceOrientations(_ navigationController: UINavigationController) -> UIInterfaceOrientationMask {
        return .portrait
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.navigationController?.delegate = self
        self.tabBarController?.delegate = self

        // Do any additional setup after loading the view.
        
        self.button.layer.cornerRadius = 25
        
        NSLog("Test log :)")
        
        if #available(iOS 16.0, *) {
            self.setNeedsUpdateOfSupportedInterfaceOrientations()
        } else {
            // Fallback on earlier versions
        }
    }
    
    @IBAction func buttonClicked(_ sender: Any) {
        NSLog("Demo button clicked :)")
        
        Gleap.openFeatureRequests()
    }
    
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
