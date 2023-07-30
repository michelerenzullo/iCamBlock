# Block Camera system - iOS

Firmware verified 16.5.1 and 16.6, devices that I tested:  
- Affected: XS, SE 2022, 11
- Seems not affected: 13, 13 pro, 8, 7 plus, 12 mini

<img width="180" src="https://github.com/michelerenzullo/iCamBlock/assets/76132686/6f507a3e-b42a-4741-b8fe-d09be1d87a65">  

## Intro
During the development of a RAW Camera project I encountered a couple of bugs that result in a black screen when using any Camera app on Apple devices. I submitted a detailed report to Apple, but unfortunately, it didn't qualify for a reward. However, I strongly believe that these issues might have lower-level explanations and could potentially be eligible for a reward. I suspect they are related to how the kernel manages camera drivers during the synchronization of different events, i.e. potential race conditions.  

Any assistance or contribution to this research is highly appreciated.  
I developed a simple app, proof-of-concept, to demonstrate the issues and execute their triggers, see the xcodeproj for technical details, video:  

https://github.com/michelerenzullo/iCamBlock/assets/76132686/43da987b-7c89-47fd-a58b-f538bcbe48e7

## Description
With the exception of the `PHOTO` mode in the Camera app, it is possible to block the main back camera anywhere in the system by executing certain triggers. The only way to unlock it is by rebooting or by capturing one photo in the aforementioned mode.

## Main issue
The issue is caused by a bug in the focus, specifically in the `lensPosition`. When shooting in `bayerRaw` mode with the flash on, if the focus is not completed correctly before the photo acquisition (e.g., when switching from a near object to a far object), the `lensPosition` can become stuck and won't change anymore, resetted to default 1.0. 
Querying `.isAdjustingFocus` will always return true, and setting `.continuousAutoFocus` or a custom `lensPosition` won't change anything, leaving it locked.

The expected behavior is that the focus and `lensPosition` shouldn't get stuck after capturing, whether we're in `.continuousAutoFocus` or if we're requesting a different `lensPosition` through `.setFocusModeLocked`.


This was the source of the issue, now how to black out the camera: 
After capturing the photo, in its delegate handler, the combination of the above bug with a "fast" switch to a different `.sessionPreset` from the current `.photo` (needed by bayerRAW), will make the camera full black and unavailable anywhere in the system, even uninstalling the app.

To unblock it, force a new capture without doing the session preset switch.

There may be an issue with the synchronization of events and how the code handles the camera driver when focusing, particularly when the flash is on, as it may be interrupted before it finishes and is not re-initialized.

### Steps to reproduce:
1. Write a basic camera app: set `.photo` preset, `bayerRAW` format, and turn the flash on.
2. Execute `.capturePhoto`.
3. In the **delegate** of `.capturePhoto`, just after `defer { didFinish?() }`, begin a session configuration, setting up a different preset from `.photo`, like `.high`.
4. Call `.commitConfiguration()`.
5. Do not put the camera on a black surface, and move the phone during the capturing process if possible.

#### Expected results:
1. The time between point .3 and .4 to commit the session configuration should be a few ms.
2. The `lensPosition` shouldn't be reset to the default 1.0, or if it is, it should be possible to unlock it.

#### Actual results:
1. If the bug succeeds, the time between point .3 and .4 to commit the session configuration will be around 9 seconds.
2. The `lensPosition` is 1.0 and is stuck/locked.

## Issue #2
It's still possible to `.capturePhoto` even if the session is not running, but the output, added previously before going in background, hasn't been detached yet by the system (a possible race condition).

### Steps to reproduce:
1. Configure a capture session correctly and run it.
2. Leave the app, going in background and return quickly (so that the system won't have enough time to detach the previously added output).
3. Execute `.capturePhoto` even if the session is not running.

#### Expected results:
An error message that the session is not running and it's not possible to capture.

#### Actual results:
It's capturing the photo

## Credit
Michele Renzullo (@michelerenzullo)
