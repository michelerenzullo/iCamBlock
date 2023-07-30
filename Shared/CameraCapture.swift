import AVFoundation
import Foundation
import struct os.Logger
import SwiftUI

private let logger = Logger(subsystem: "com.j1b.ios", category: "blocker")

private let captureSession = AVCaptureSession()
private let photoOutput = AVCapturePhotoOutput()
private var captureDelegates: [Int64: RAWCaptureDelegate] = [:]
private let camera : AVCaptureDevice! = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)

public func setupSession() -> Bool {
  guard !captureSession.outputs.contains(photoOutput) else {
    // Issue #2 (Tested on SE 22 and 11 )
    // Even if the session is not running, but the output, added previously,
    // hasn't been detached yet, we are able to capturePhoto()
    // Steps to reproduce: "Block" the camera, leave this app, return from
    // background fastly and tap "Un-block".
    // It wouldn't be possible in the normal behaviour.
    logger.debug("The session isn't running but already contains the output. We can capture the photo even if it shouldn't be possible")
    return true
  }
  captureSession.beginConfiguration()
  let device = try! AVCaptureDeviceInput(device: camera)
  guard
    captureSession.canAddInput(device) &&
    captureSession.canAddOutput(photoOutput) &&
    captureSession.canSetSessionPreset(.photo)
  else {return false}
  captureSession.sessionPreset = .photo
  captureSession.addInput(device)
  captureSession.addOutput(photoOutput)
  photoOutput.isAppleProRAWEnabled = false
  captureSession.commitConfiguration()
  logger.debug("Capture session configured.")
  captureSession.startRunning()
  logger.debug("Capture session started running.")
  return true
}

public func requestPermission() async -> Bool {
  let authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
  switch authorizationStatus {
  case .restricted, .denied:
    return false
  case .authorized:
    return true
  case .notDetermined:
    return await AVCaptureDevice.requestAccess(for: .video)
  @unknown default:
    return await AVCaptureDevice.requestAccess(for: .video)
  }
}


public func capturePhoto(_ printMessage: @escaping ((String) -> Void), block: Bool = false) async {
  
  guard await requestPermission() else {return}
  
  guard block || (!block && camera.lensPosition == 1.0) else {printMessage("Already not-blocked"); return}
  
  if (!captureSession.isRunning) {
    printMessage("Initializing, might take till 9 sec if resuming when blocked")
    guard setupSession() else {printMessage("Initialization failed. Close and open again"); return}
  }
  printMessage("Executing...")
  
  if (captureSession.sessionPreset != .photo && captureSession.canSetSessionPreset(.photo)) {
    captureSession.beginConfiguration()
    captureSession.sessionPreset = .photo
    captureSession.commitConfiguration()
    logger.debug("switched sessionPreset to .photo")
  }
  
  let formatQuery = { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }
  let rawFormat = photoOutput.availableRawPhotoPixelFormatTypes.first(where: formatQuery)
  let photoSettings = block ? AVCapturePhotoSettings(rawPixelFormatType: rawFormat!) : AVCapturePhotoSettings()
  photoSettings.flashMode = block ? .on : .off
  let delegate = RAWCaptureDelegate(
    printMessage: printMessage,
    didFinish: {captureDelegates[photoSettings.uniqueID] = nil}
  )
  captureDelegates[photoSettings.uniqueID] = delegate
  
  photoOutput.capturePhoto(with: photoSettings, delegate: delegate)
  logger.debug("Photo capture requested.")
}

class RAWCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
  private let didFinish: (() -> Void)?
  private let printMessage: (String) -> Void
  
  init(printMessage: @escaping (String) -> Void, didFinish: (() -> Void)?) {
    self.printMessage = printMessage
    self.didFinish = didFinish
  }
  
  func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
    defer { didFinish?() }
    logger.debug("Photo captured. isRaw: \(photo.isRawPhoto)")
    DispatchQueue.global(qos: .userInitiated).async{
      // Issue #1 (Tested on SE 22, 11, XS )
      // Bug in RAW mode + Flash + the lensPosition is stuck to default 1.0
      // after capturing if during the acquisition the camera didn't complete with
      // success the focus. This bug mixed with a fast change of preset cause the camera block.
      // When succeeded, committing the configuration will take 9 seconds.
      // Might be related to a bad sync of the events and changes in states that should be lock or unlocked later...
      if (photo.isRawPhoto && photo.resolvedSettings.isFlashEnabled) {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high
        self.printMessage("Triggers executed, checking the outcome, wait...")
        let oldLensPosition = camera.lensPosition
        logger.debug("bug triggers act now")
        captureSession.commitConfiguration()
        logger.debug("bug triggers end now")
        // It's enough also to just check just the time between the beginConfiguration()
        // and commitConfiguration() , it's around 8 ~ 9 seconds when the bug occurs
        if (camera.lensPosition != 1.0) {
          self.printMessage("Error: Block failed. The lens position is not 'frozen' to default, so the bug didn't occur. Try moving the phone. It was \(oldLensPosition) before the triggers and is now \(camera.lensPosition)")
        }
        else {self.printMessage("Blocked")}
        return;
      }
      self.printMessage("Un-blocked")
    }
  }
}
