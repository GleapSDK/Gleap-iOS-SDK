//
//  ImageViewController.swift
//  Example
//
//  Created by Lukas Boehler on 08.07.22.
//

import UIKit

class ImageViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        
        NSLog("Test log :)")
    }
    
    @IBAction func buttonClicked(_ sender: Any) {
        NSLog("Demo button clicked :)")
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
