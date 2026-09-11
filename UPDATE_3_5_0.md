# Book and Quill 3.5.0

Extract this update into the existing project folder and replace matching files.
Keep the existing assets, workflow, tests, Windows scaffold and signing files.
This archive is an update, not a standalone project or a compiled installer.

Run in PowerShell from the project folder:

```powershell
Unblock-File -LiteralPath .\tools\publish_android_github.ps1
Unblock-File -LiteralPath .\tools\prepare_android_github.ps1
.\tools\publish_android_github.ps1
```

The existing GitHub workflow will run the tests and produce the profile APK.
The Windows build uses the same updated Dart page widget.

## Changes

- Pages allow 18 writing lines on Android and Windows, with the same text size,
  line spacing and wrapping width. The editable date and page arrows sit below
  those lines. Page overflow uses the shared 18-line limit automatically.
- Fresh Android settings and Reset Settings use Music Frequency OFF and Music
  Island OFF. Missing fields in older settings use those defaults. Explicitly
  saved choices are preserved. Desktop defaults remain unchanged.
- Android publishes a native MediaSession and MediaStyle notification with
  title, artist, album, supplied album artwork, duration and playback position.
  Play, pause, previous, next, seek and stop control the existing SoLoud player.
- Music does not require the app island to be visible. Enable Music Frequency
  in Sounds to play music while leaving Music Island OFF.
- An active media session uses a mediaPlayback foreground service to continue
  playing when the app is backgrounded or the screen locks. A new playlist is
  not automatically started from a backgrounded app without an active session.
  Force-closing the app, removing its task, or Android killing its engine ends
  playback; this is not a persistent media library or restart/resumption service.
- Audio focus is requested before playback. Another player taking focus or
  disconnecting headphones pauses the music. Resume manually using media controls.
- Turning Music Frequency OFF removes the media session and notification.

Xiaomi/HyperOS controls its own island eligibility and presentation. Standard
Android media integration is provided; appearance in Xiaomi's island depends
on the phone's firmware and settings. Lock-screen/notification controls are the
standard Android surfaces to check first.

## Verification and limits

The uploaded 3.4.8 source is the baseline. The patch retains the existing
Android profile-build script and Kotlin cross-drive cache fix. No new Pub or
Gradle dependency is required. The publish manifest includes the new native
service, notification icon, Dart bridge and regression test file.

New tests cover Android defaults and preserving saved choices, media metadata
and failure handling through a mocked native channel, and 18-line page/footer
bounds for all page sides on both platforms. Existing tests remain in place.
Flutter, the Android SDK and a phone are unavailable in this workspace, so
these tests and native compilation must run on GitHub. Source structure,
manifest wiring and the archive round trip are checked locally; physical-phone
media behavior and Xiaomi integration remain to be confirmed.

References:
- https://developer.android.com/media/implement/surfaces/mobile
- https://developer.android.com/media/optimize/audio-focus
- https://developer.android.com/develop/background-work/services/fgs/service-types
