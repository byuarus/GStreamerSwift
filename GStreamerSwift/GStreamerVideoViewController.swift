//
//  GStreamerVideoViewController.swift
//  GStreamerSwift
//
//  Created by Dmytro Malakhov on 4/13/21.
//

import Foundation
import UIKit

class GStreamerVideoViewController: UIViewController {
    
    private var backend: GStreamerBackend?
    private var videoView = UIView()
    var uri: String?
    
    deinit {
        let notificationCenter = NotificationCenter.default
        notificationCenter.removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self,
                                       selector: #selector(appMovedToBackground),
                                       name: UIApplication.willResignActiveNotification,
                                       object: nil)
        
        notificationCenter.addObserver(self,
                                       selector: #selector(appWillMoveToForeground),
                                       name: UIApplication.willEnterForegroundNotification,
                                       object: nil)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        backend?.deinit()
    }
    
    @objc func appMovedToBackground() {
        print("App moved to background!")
        pause()
    }
    
    @objc func appWillMoveToForeground() {
        print("App will move to Foreground!")
        
        if let uri = uri {
            changeURI(uri)
        }
    }
    
    func play() {
        backend?.play()
    }
    
    func pause() {
        backend?.pause()
    }
    
    func changeURI(_ newURI: String) {
        
        uri = newURI
        backend?.deinit()
        
        // Replace view
        videoView.removeFromSuperview()
        videoView = UIView()
        view.addSubview(videoView)
        
        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.topAnchor.constraint(equalTo: view.topAnchor, constant: 0).isActive = true
        videoView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0).isActive = true
        videoView.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 0).isActive = true
        videoView.rightAnchor.constraint(equalTo: view.rightAnchor, constant: 0).isActive = true
        
        backend = GStreamerBackend(self, videoView: videoView)
    }
}

extension GStreamerVideoViewController: GStreamerBackendDelegate {
    func gstreamerInitialized() {
        print("gstreamerInitialized")
        
        if let uri = uri {
            backend?.setUri(uri)
            play()
        }
    }
    
    func gstreamerSetUIMessage(_ message: String) {
        print("gstreamerSetUIMessage: \(message)")
    }
}
