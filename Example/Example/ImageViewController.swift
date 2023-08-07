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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.navigationController?.delegate = self
        self.tabBarController?.delegate = self

        // Do any additional setup after loading the view.
        
        self.button.layer.cornerRadius = 25
        
        if #available(iOS 16.0, *) {
            self.setNeedsUpdateOfSupportedInterfaceOrientations()
        } else {
            // Fallback on earlier versions
        }
    }
    
    @IBAction func buttonClicked(_ sender: Any) {
        NSLog("Demo button clicked :)")
        
        Gleap.openFeatureRequests(false)
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
