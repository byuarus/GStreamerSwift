# GStreamerSwift
Example of adding GStreamer into existing Swift project

## Initial setup

1. Install GStreamer framework system wide
GStreamer binary installer can be found at:
https://gstreamer.freedesktop.org/data/pkg/ios/

The GStreamer SDK installs itself in your home directory, so it is available only to the user that installed it. The SDK library is installed to ~/Library/Developer/GStreamer/iPhone.sdk. Inside this directory there is the GStreamer.framework that contains the libs, headers and resources.

2. Add `gst_ios_init.h` and `gst_ios_init.m` files from this project. 

3. enable/disable plugins for your project in  `gst_ios_init.h` file.

4. Create a bridging header file and add code (if you have existing bridging header file then just add this line of code to it):
`#import "gst_ios_init.h"`

5. In the project's target setting 
- add the bridging header file in Obective-C Bridging Header setting.
- In Header Search Path add 
`"$(HOME)/Library/Developer/GStreamer/iPhone.sdk/GStreamer.framework/Headers"`
- In Framework search path add
`"$(HOME)/Library/Developer/GStreamer/iPhone.sdk"`
- In Other Linker Flags add `-lresolv` and `-lc++`

6. In General settings of the target use "+" button in Frameworks, Libraries, and Embedded Content to add libraries:
- AssetsLibrary, AudioToolbox, AVFoundation, CoreAudio, CoreMedia, CoreVideo, VideoToolbox, libiconv.tbd
- GStreamer.framework. You can find it in "$(HOME)/Library/Developer/GStreamer/iPhone.sdk/"
- make sure all frameworks have settings "do not embed" selected

7. Select libiconv.tbd in the Frameworks group in the Xcode project navigator and select all targets for that file in the File Inspector (menu on the right) in Target Membership section. 
8. In `application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions)` call `gst_ios_init()`

Great! Now you can use GStreamer in your project

## Sample app
1. Add files from this project:
- GStreamerBackend.h
- GStreamerBackend.m
- GStreamerBackendDelegate.h
- GStreamerVideoViewController.swift

More info on GStreamerBackend* files here: https://gstreamer.freedesktop.org/documentation/tutorials/ios/link-against-gstreamer.html?gi-language=c

2. Add `#include "GStreamerBackend.h"` in the bridging header file

3. To create a UIView with RTSP stream add these lines of code (e.g in `viewDidLoad` of your ViewController):
```
let videoViewController = GStreamerVideoViewController()
videoViewController.changeURI(uri)
view.addSubview(videoViewController.view)

videoViewController.view.translatesAutoresizingMaskIntoConstraints = false
videoViewController.view.topAnchor.constraint(equalTo: view.topAnchor, constant: 0).isActive = true
videoViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0).isActive = true
videoViewController.view.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 0).isActive = true
videoViewController.view.rightAnchor.constraint(equalTo: view.rightAnchor, constant: 0).isActive = true
```
4. Change the `uri` to any RTSP stream (for e.g. free stream rtsp://wowzaec2demo.streamlock.net/vod/mp4:BigBuckBunny_115k.mov)
