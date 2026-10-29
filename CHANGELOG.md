# Changelog

## v0.1.3 - 2026-10-29

This release fixes a problem where the camera stayed in use after you closed the menu bar panel.

### Fixes

- The camera now stops when you close the menu bar panel. Before, the capture session kept running and the camera light stayed on.

## v0.1.2 - 2026-10-23

This release adds a screenshot of the menu bar panel to the documentation. It has no change to the behavior of the app.

### Other changes

- The documentation now shows a screenshot of the menu bar panel. This helps you see how the panel looks before you use it.
- The release build now attaches to an existing release. The release process no longer fails when the release already exists.

## v0.1.1 - 2026-10-23

This release has no change to the behavior of facecam. It only changes the tests.

### Other changes

- The project has updated tests. This helps keep facecam reliable, and you do not need to do anything.

## v0.1.0 - 2026-10-23

This first release of facecam gives you a macOS menu bar app and a CLI to control your Elgato Facecam camera.

### New features

- Add a native macOS menu bar app and CLI that control the camera directly over UVC. You can change the standard controls and the Elgato extension unit controls: HDR, vibrancy, tint, noise reduction, metering, and digital pan and tilt.
- Add a live preview, so you can see each change on the camera image at once.
- Add profiles that apply automatically when the camera connects. You can also save settings to the camera.
- Add universal DMG and CLI packages that run on both Apple silicon and Intel Macs.

### Other changes

- Add a size comparison to the README.
