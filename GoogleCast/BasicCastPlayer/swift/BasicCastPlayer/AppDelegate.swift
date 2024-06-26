//
//  AppDelegate.swift
//  BasicCastPlayer
//
//  Copyright © 2024 Brightcove, Inc. All rights reserved.
//

import AVFoundation
import UIKit
import GoogleCast


@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    var castContainerViewController: GCKUICastContainerViewController?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        /*
         Set the AVAudioSession category to allow audio playback when:

         1: Silent Mode is enabled, or
         2: When the app is in the background, and
         2a:`allowsBackgroundAudioPlayback` is enabled on the playback controller, and/or
         2b:`allowsExternalPlayback` is enabled on the playback controller, and
         2c: "Audio, AirPlay, and Picture in Picture" is enabled as a Background Mode capability.

         Refer to the AVAudioSession Class Reference:
         https://developer.apple.com/documentation/avfoundation/avaudiosession
         */

        do {
            // see https://developer.apple.com/documentation/avfoundation/avaudiosessioncategoryplayback
            // and https://developer.apple.com/documentation/avfoundation/avaudiosessionmodemovieplayback
            try AVAudioSession.sharedInstance().setCategory(.playback,
                                                            mode: .moviePlayback,
                                                            options: .duckOthers)
        } catch {
            print("AppDelegate - Error setting AVAudioSession category. Because of this, there may be no sound. \(error)")
        }

        // More Info @ https://developers.google.com/cast/docs/ios_sender/integrate#initialize_the_cast_context
        let discoveryCriteria = GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID)
        let options = GCKCastOptions(discoveryCriteria: discoveryCriteria)
        options.physicalVolumeButtonsWillControlDeviceVolume = true
        GCKCastContext.setSharedInstanceWith(options)

        // More Info @ https://developers.google.com/cast/docs/ios_sender/integrate#add_expanded_controller
        GCKCastContext.sharedInstance().useDefaultExpandedMediaControls = true

        // More Info @ https://developers.google.com/cast/docs/ios_sender/integrate#add_mini_controllers
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let navigationController = storyboard.instantiateViewController(withIdentifier: "NavController")
        castContainerViewController = GCKCastContext.sharedInstance().createCastContainerController(for: navigationController)
        castContainerViewController?.miniMediaControlsItemEnabled = true

        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = castContainerViewController
        window?.makeKeyAndVisible()

        return true
    }

}
