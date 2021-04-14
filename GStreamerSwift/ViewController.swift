//
//  ViewController.swift
//  GStreamerSwift
//
//  Created by Dmytro Malakhov on 4/12/21.
//

import UIKit


let uri = "rtsp://wowzaec2demo.streamlock.net/vod/mp4:BigBuckBunny_115k.mov" // Any rtsp stream
//let uri = "rtspu://3.237.48.237:8553/stream1"

class ViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        let videoViewController = GStreamerVideoViewController()
        videoViewController.changeURI(uri)
        
        view.addSubview(videoViewController.view)
        
        videoViewController.view.translatesAutoresizingMaskIntoConstraints = false
        videoViewController.view.topAnchor.constraint(equalTo: view.topAnchor, constant: 0).isActive = true
        videoViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0).isActive = true
        videoViewController.view.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 0).isActive = true
        videoViewController.view.rightAnchor.constraint(equalTo: view.rightAnchor, constant: 0).isActive = true
    }
}

