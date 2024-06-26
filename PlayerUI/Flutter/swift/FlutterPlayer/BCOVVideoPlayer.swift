//
//  BCOVVideoPlayer.swift
//  FlutterPlayer
//
//  Copyright © 2024 Brightcove, Inc. All rights reserved.
//

import AVFoundation
import AVKit
import Foundation
import Flutter
import BrightcovePlayerSDK


// Customize these values with your own account information
// Add your Brightcove account and video information here.
let kAccountId = "5434391461001"
let kPolicyKey = "BCpkADawqM0T8lW3nMChuAbrcunBBHmh4YkNl5e6ZrKQwPiK_Y83RAOF4DP5tyBF_ONBVgrEjqW6fbV0nKRuHvjRU3E8jdT9WMTOXfJODoPML6NUDCYTwTHxtNlr5YdyGYaCPLhMUZ3Xu61L"
let kVideoId = "6140448705001"


final class BCOVVideoPlayer: NSObject {

    fileprivate lazy var playbackService: BCOVPlaybackService = {
        let factory = BCOVPlaybackServiceRequestFactory(accountId: kAccountId,
                                                        policyKey: kPolicyKey)
        return .init(requestFactory: factory)
    }()

    fileprivate lazy var playbackController: BCOVPlaybackController? = {
        guard let sdkManager = BCOVPlayerSDKManager.sharedManager(),
              let authProxy = BCOVFPSBrightcoveAuthProxy(publisherId: nil,
                                                         applicationId: nil) else {
            return nil
        }

        let fps = sdkManager.createFairPlaySessionProvider(withApplicationCertificate: nil,
                                                           authorizationProxy: authProxy,
                                                           upstreamSessionProvider: nil)

        guard let playbackController = sdkManager.createPlaybackController(with: fps,
                                                                           viewStrategy: nil) else {
            return nil
        }

        playbackController.options = [kBCOVAVPlayerViewControllerCompatibilityKey: true]

        playbackController.delegate = self
        playbackController.isAutoAdvance = true
        playbackController.isAutoPlay = true

        return playbackController
    }()

    fileprivate lazy var avpvc: AVPlayerViewController = {
        let avpvc = AVPlayerViewController()
        avpvc.showsPlaybackControls = false
        return avpvc
    }()

    fileprivate lazy var appDelegate: AppDelegate? = UIApplication.shared.delegate as? AppDelegate

    fileprivate lazy var methodChannel: FlutterMethodChannel? = {
        guard let flutterEngine = appDelegate?.flutterEngine else { return nil }

        return .init(name: "bcov.flutter/method_channel",
                     binaryMessenger: flutterEngine.binaryMessenger)
    }()

    fileprivate lazy var eventChannel: FlutterEventChannel? = {
        guard let flutterEngine = appDelegate?.flutterEngine else { return nil }

        return .init(name: "bcov.flutter/event_channel",
                     binaryMessenger: flutterEngine.binaryMessenger,
                     codec: FlutterJSONMethodCodec.sharedInstance())
    }()

    fileprivate var eventSink: FlutterEventSink?

    init(frame: CGRect,
         viewId: Int64,
         args: Any?) {
        super.init()

        guard let eventChannel,
              let methodChannel else {
            return
        }

        eventChannel.setStreamHandler(self)

        methodChannel.setMethodCallHandler {
            [self] (call: FlutterMethodCall,
                    result: @escaping FlutterResult) -> Void in
            handle(call, result: result)
        }

        requestContentFromPlaybackService()
    }

    fileprivate func requestContentFromPlaybackService() {
        let configuration = [kBCOVPlaybackServiceConfigurationKeyAssetID: kVideoId]
        playbackService.findVideo(withConfiguration: configuration,
                                  queryParameters: nil) {
            [self] (video: BCOVVideo?,
                    jsonResponse: [AnyHashable: Any]?,
                    error: Error?) in
            guard let playbackController,
                  let video else {
                if let error {
                    print("ViewController - Error retrieving video: \(error.localizedDescription)")
                }

                return
            }

#if targetEnvironment(simulator)
            if video.usesFairPlay,
               let appDelegate,
               let window = appDelegate.window,
               let rootViewController = window.rootViewController {
                // FairPlay doesn't work when we're running in a simulator,
                // so put up an alert.
                let alert = UIAlertController(title: "FairPlay Warning",
                                              message: """
                                                           FairPlay only works on actual \
                                                           iOS or tvOS devices.\n
                                                           You will not be able to view \
                                                           any FairPlay content in the \
                                                           iOS or tvOS simulator.
                                                           """,
                                              preferredStyle: .alert)

                alert.addAction(.init(title: "OK", style: .default))

                DispatchQueue.main.async {
                    rootViewController.present(alert, animated: true)
                }

                return
            }
#endif

            playbackController.setVideos([video] as NSFastEnumeration)
        }
    }

    fileprivate func handle(_ call: FlutterMethodCall,
                            result: @escaping FlutterResult) {

        guard let playbackController else {
            result(FlutterMethodNotImplemented)
            return
        }
        switch (call.method) {
            case "playPause":
                if let isPlaying = call.arguments as? Bool {
                    if isPlaying {
                        playbackController.pause()
                    } else {
                        playbackController.play()
                    }
                }
                break

            case "seek":
                if let seconds = call.arguments as? TimeInterval {
                    let seekTo = CMTimeMakeWithSeconds(seconds, preferredTimescale: 600)
                    playbackController.seek(to: seekTo, completionHandler: nil)
                }
                break

            default:
                result(FlutterMethodNotImplemented)
        }
    }
}


// MARK: - BCOVPlaybackControllerDelegate

extension BCOVVideoPlayer: BCOVPlaybackControllerDelegate {

    func playbackController(_ controller: BCOVPlaybackController!,
                            didAdvanceTo session: BCOVPlaybackSession!) {
        print("ViewController - Advanced to new session.")

        avpvc.player = session.player

        guard let eventSink,
              let duration = session.video.properties[kBCOVVideoPropertyKeyDuration] as? TimeInterval else {
            return
        }

        eventSink([ "name": "didAdvanceToPlaybackSession",
                    "duration": duration,
                    "isAutoPlay": controller.isAutoPlay ])
    }

    func playbackController(_ controller: BCOVPlaybackController!,
                            playbackSession session: BCOVPlaybackSession,
                            didReceive lifecycleEvent: BCOVPlaybackSessionLifecycleEvent!) {

        if kBCOVPlaybackSessionLifecycleEventFail == lifecycleEvent.eventType,
           let error = lifecycleEvent.properties["error"] as? NSError {
            // Report any errors that may have occurred with playback.
            print("ViewController - Playback error: \(error.localizedDescription)")
        }

        if kBCOVPlaybackSessionLifecycleEventEnd == lifecycleEvent.eventType,
           let eventSink {
            eventSink([ "name": "eventEnd" ])
        }
    }

    func playbackController(_ controller: BCOVPlaybackController!,
                            playbackSession session: BCOVPlaybackSession!,
                            didProgressTo progress: TimeInterval) {
        guard let eventSink,
              progress.isFinite else { return }

        eventSink([ "name": "didProgressTo",
                    "progress": progress ])
    }
}


// MARK: - FlutterPlatformView

extension BCOVVideoPlayer: FlutterPlatformView {

    func view() -> UIView {
        return avpvc.view
    }
}


// MARK: - FlutterStreamHandler

extension BCOVVideoPlayer: FlutterStreamHandler {

    func onListen(withArguments arguments: Any?,
                  eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
