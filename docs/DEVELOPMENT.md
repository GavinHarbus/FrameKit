# Developing FrameKit

FrameKit uses Swift and SwiftUI, Accessibility for window control, ScreenCaptureKit for capture, and Core Graphics / ImageIO for image processing. It has no third-party runtime dependencies or Apple Events automation.

## Build and run

Use Xcode with the macOS 26 SDK or later. The app runs on macOS 14 or later; newer system appearance APIs are guarded by availability checks.

1. Open `FrameKit.xcodeproj`. The generated project is included, so XcodeGen is not needed for a normal build.
2. Select your own development team in Signing & Capabilities. The checked-in project contains the maintainer's signing settings; its certificates are not included.
3. Select the **FrameKit** scheme and **My Mac**, then run.
4. Grant Screen Recording permission to list and capture windows. Grant Accessibility only for resizing or moving them. Reopen the app if macOS requests it.

For command-line builds, replace `YOUR_TEAM_ID` with your Apple development team ID:

```bash
xcodebuild -project FrameKit.xcodeproj -scheme FrameKit -configuration Debug -destination 'platform=macOS' -derivedDataPath build DEVELOPMENT_TEAM=YOUR_TEAM_ID CODE_SIGN_STYLE=Automatic build
```

The app is written to `build/Build/Products/Debug/FrameKit.app`. Use `-configuration Release` for a Release build.

`project.yml` is the XcodeGen project definition. Keep it in sync when changing project settings. If XcodeGen is installed, regenerate with:

```bash
xcodegen generate
```

Debug and Release share the app name **FrameKit** and bundle identifier `com.framekit.local`. Stable signing and the same application path help keep macOS permission records associated with the intended build.

## Distribution status

The current project builds a **non-sandboxed development app**. App Sandbox is disabled, Hardened Runtime is enabled, and signing is configured for Apple Development. This configuration is not a Mac App Store submission. Store packaging, signing, sandbox compatibility, and review remain separate release work.

## Workflow details

- **Current Size** captures directly and does not require Accessibility permission. **Custom Size** applies the requested dimensions before each capture and checks the actual result.
- Window size is measured in points, including the title bar. Position uses the main display's top-left corner as the origin, with positive coordinates extending right and down.
- **Output Size** changes the preview in pixels. **Export** saves that rendered preview and verifies the saved PNG dimensions, format, and absence of an alpha channel.
- Output is an opaque sRGB PNG. Fit padding and transparent source corners are composited onto white. Increasing pixel dimensions does not add source detail.
- Filenames use `App-WindowTitle-WidthxHeight.png`. The window title is recorded with the capture; an empty title is omitted. The save dialog lets the user edit the name.
- The latest capture stays in memory until a successful retake, an explicit app/window selection change, or quitting. A failed capture or automatic loss of the target preserves the previous image for export.

| Shortcut | Action |
| --- | --- |
| Command-R | Refresh apps and windows |
| Command-K | Capture using the selected size mode |
| Command-E | Export PNG |
| Option-Command-I | Toggle the inspector |

Return or Escape ends field editing; Tab moves between fields. Clicking another control or an empty area also ends editing.

## Localization

English is the source and fallback language. Simplified Chinese (`zh-Hans`) is also supported. FrameKit follows macOS language preferences without maintaining a separate in-app language setting.

To override the language for FrameKit, use **System Settings → General → Language & Region → Applications**, then reopen the app.

- `Resources/Localizable.xcstrings` contains interface text, menus, status messages, and errors.
- `Resources/InfoPlist.xcstrings` contains the screen capture permission description.
- `FrameKitCore` is a static library and resolves localized strings through `AppLocalization.bundle`.
- Add English strings first and supply Simplified Chinese translations. Keep variables inside complete localized sentences. Preserve app names, window titles, paths, and identifiers as supplied.

The existing `Tools/CheckLocalizations.py` is an optional, read-only development check. After a Debug build using `-derivedDataPath build`, it checks extracted strings against the catalogs. It does not edit source files and is not part of the app runtime.

## Tests

Run tests from Xcode's Test navigator or with the same signing overrides used for the build:

```bash
xcodebuild -project FrameKit.xcodeproj -scheme FrameKit -destination 'platform=macOS' -derivedDataPath build DEVELOPMENT_TEAM=YOUR_TEAM_ID CODE_SIGN_STYLE=Automatic test
```

For language-specific runs, add `-testLanguage en -testRegion US` or `-testLanguage zh-Hans -testRegion CN`.

Tests cover size validation, window matching, permission monitoring, image scaling, PNG verification, selection state, preview updates, export behavior, and localization. They cannot grant macOS permissions or replace testing with real target apps.

Before a release, manually check:

- An accepted custom size and a size below the target app's minimum.
- Multiple windows, including a selected window that is not frontmost.
- A target that closes, minimizes, or moves during the workflow.
- Retina and external displays, comparing window points with exported pixels.
- Permission denial, later approval, and revocation.
- Browser tabs and extension side panels using the intended capture layout.

## Permissions troubleshooting

If System Settings shows permission as enabled but FrameKit cannot use it, confirm that the authorized app is the copy being run. A changed signature, bundle identifier, or application path can leave a stale permission entry. Remove the stale entry through System Settings and authorize the current app. Do not modify the macOS permission database.

Permission checks refresh when FrameKit becomes active and during the authorization flow. They do not repeatedly display permission prompts.

## Capture boundaries

- Only available, on-screen, regular windows are listed. FrameKit does not automatically restore minimized windows, exit full screen, or switch Spaces.
- Some apps enforce minimum dimensions or fixed proportions. FrameKit reports the actual result rather than assuming the requested dimensions were applied.
- Accessibility windows are matched conservatively to capture windows by process, geometry, and title. Ambiguous matches are rejected for resizing.
- Captures exclude the pointer and window shadow. On macOS 14.2 and later, child windows are explicitly excluded. Separate popups are not guaranteed to appear in a browser-window capture.
- Protected content may not be capturable. There is no full-page scrolling capture.
- Output is limited to 16,384 pixels per edge and 64 million pixels total.
- Preset persistence, batch export, and freeform cropping are not implemented.

See [artwork preparation](../Design/README.md) for icon assets and their licensing scope.
