# Book and Quill 3.4.8 — Android

This update adds Android to the existing Flutter project. Extract the update
into your current project folder and replace matching files. Keep your existing
assets, Windows files, Git repository, and README. The ZIP is a source update,
not a compiled APK or a replacement for the entire project.

## Build on GitHub without installing an SDK on your PC

This route uses GitHub's Android SDK. A native Flutter Android app still needs
Android build tools on the build machine. The uploaded SDK Tools 26.1.1 package
contains neither the platform android.jar nor the modern compiler toolchain;
it cannot build this app by itself and is not used by this workflow.

1. Extract this update into your existing Book and Quill project and replace
   matching files. It includes the earlier Android source update as well.
   Keep the full existing project, assets, and Git repository.
2. In PowerShell in that project folder, run:

   ```powershell
   .\tools\publish_android_github.ps1
   ```

   This command requires only Git. It stages the update and the PNG, OGG
   and TTF assets from assets/imported (including previously ignored assets),
   commits them, pulls and merges origin/main, then pushes main. It stops
   immediately if preparation, commit, merge or push fails. It does not
   force-push, reset either branch, or automatically resolve merge conflicts.
   Existing staged changes are included in the commit. Your already-created
   local commits are preserved and merged with GitHub's commits.

   If it reports a merge conflict, run `git status` and send that output with
   the error. Do not force-push. If you prefer manual steps, run the preparation
   script, commit, then `git pull --no-rebase --no-edit origin main` and finally
   `git push origin main`, stopping at any error.

   Version 3.4.2 fixed Windows PowerShell 5.1 treating the JSON manifest array
   as a single nested pipeline object. Manifest entries are now enumerated
   explicitly and checked as individual path strings before any staging.

3. Open https://github.com/shantiashams/book-and-quill/actions and select the
   latest **Android APK** run. The first push of the workflow on main starts
   the build automatically. You can also select Android APK > Run workflow.
4. Wait for a successful run, then download
   **Book-and-Quill-Android-test-N** from **Artifacts** at the bottom of the
   run page. Sign into GitHub to download. Extract the ZIP and copy its APK
   to your phone. Allow installation from the app you use to open it.

The job uses a GitHub-hosted Windows 2025 machine, Flutter 3.44.0 and Java 17.
It uses the hosted Android SDK and accepts SDK licenses on the build machine.
Flutter/Gradle downloads any additional needed packages on GitHub. Your own
computer only needs to reach GitHub. There is no local SDK or Android Studio
requirement for this route. Textures, fonts and music must be in GitHub too;
the preparation script handles your existing assets rather than downloading
Minecraft on the runner. Assets retain their respective rights.

Tests must pass before an APK is uploaded. If the run fails, open the failed
step and send its first error. No APK is uploaded for a failed build.
Artifacts expire after 14 days; rerun the workflow to create another.
The workflow does not publish a GitHub Release or upload to Google Play.

This produces an **optimized profile APK for testing on a physical phone**. Hosted machines can generate a
new debug signing key on each run, so a later test APK may require uninstalling
the earlier copy. Export any writing first; uninstalling deletes app data.
Use your own consistent release key before distributing updatable releases.
Release signing instructions are below; the cloud job deliberately only builds
profile APKs and does not request your release credentials.

The workflow and update archive were checked locally. A GitHub Actions run,
Flutter tests and APK compilation could not be executed in the preparation
environment. The first pushed run supplies those results.

## 3.4.3 build-test fix

The first GitHub build completed SDK setup and dependency resolution, then
reported 13 passing tests and 8 failing widget tests. The supplied log exposed
an incorrectly scoped platform override and a page fixture missing a Material
ancestor. Widget tests now use Flutter's TargetPlatformVariant lifecycle;
Android service tests keep their overrides in a separate unit-test group.
The page and dialog fixtures use Scaffold as they do in the application.
All existing behavioral assertions and the build's test gate remain enabled.
Test output now uses the expanded reporter to show each failure in full.
The preparation file list prints without Git's interactive pager.

These corrections were inspected locally. Flutter is unavailable in the
preparation environment, so the next GitHub run must confirm the tests and
perform APK compilation; this source update does not contain an APK.

## 3.4.4 remaining test fixes

The next GitHub run passed 19 tests and failed two. The lifecycle test now
simulates inactive -> hidden -> paused -> hidden -> inactive -> resumed,
restoring the active state in a finally block. The music-island test explicitly
checks MUSIC IS OFF for the silent fixture before enabling its control notifier
and checking NO MUSIC PLAYING, collapse, and always-expanded behavior.
Application lifecycle/audio behavior is unchanged. All 21 tests remain enabled.
The fixes and archive were checked locally; the next GitHub run must execute
the tests and compile the APK because Flutter is unavailable locally.

## 3.4.5 Windows Android build fix

The supplied 3.4.4 GitHub log confirms all 21 tests passed. APK compilation
then failed in file_selector_android because Kotlin's incremental cache tried
to calculate relative paths between dependencies on C: and the checkout on D:.

The workflow now sets PUB_CACHE beside the checkout, on the same drive, before
package resolution and compilation. Setup also merges kotlin.incremental=false
into android/gradle.properties on Windows, including existing Android scaffolds.
Other Gradle settings are preserved. This can make repeated Kotlin compilations
slower, but avoids the failing incremental path cache. Tests and app behavior
are unchanged. GitHub must run the updated build to confirm APK compilation;
this patch contains source and tools, not a compiled APK.

References: [Dart PUB_CACHE](https://dart.dev/tools/pub/environment-variables)
and [Kotlin incremental compilation](https://kotlinlang.org/docs/gradle-compilation-and-caches.html).

## 3.4.6 phone interface and performance

The music island now owns an Overlay above Navigator, so its tooltips have
an Overlay ancestor in the actual app layout. The regression fixture now uses
MaterialApp.builder, checks the collapsed size and status-bar offset, and
checks that taps outside the island still reach the page below it.

On Android the collapsed island is a centered 220 x 44 pill (narrower if needed),
with a vertically centered progress strip and a 120 ms expansion animation.
Shelf changes take 180 ms on Android. Separate repaint boundaries isolate the
music controller and book from surrounding repaint work.

The book fits its measured visible wooden frame with four logical pixels of
space on each side. It is about 3% larger on a typical phone; larger tablet
pages can grow beyond the previous 700-unit cap. Text, line limits, date
placement and aspect ratio are preserved. The page still scrolls above the
keyboard. Substantially larger phone pages would require horizontal scrolling
or cropping the visible book.

GitHub now builds profile mode, because debug-mode animation speed is not
representative of optimized Flutter performance. The artifact contains
Book-and-Quill-3.4.6-android-profile.apk. The normal Flutter widget tests still
run with assertions before packaging. Local builds can select -Mode debug,
-Mode profile, or a properly signed -Mode release. Profile builds are test
builds and still use a temporary debug signing key on the hosted runner.

All changes were inspected and the archive verified locally. Flutter and an
Android device are unavailable here, so the next Actions run and phone test
must confirm the regression checks and animation performance.
See [Flutter build modes](https://docs.flutter.dev/testing/build-modes).

## 3.4.7 animation test timing

The 3.4.6 log passed 20 tests. The music test's Close tap missed because the
first pump started AnimatedSize at its new timestamp without advancing the
animation. The test now pumps the changed layout first, then advances 200 ms
past the 120 ms animation before interacting. Opening, closing and always-big
use this sequence. It checks that Close and the restored Open button are hit
testable, and that collapse restores the 220 x 44 size.

App behavior and all 21 tests remain intact. The existing overlay fix, larger
book and optimized profile APK workflow are unchanged. The next artifact is
Book-and-Quill-3.4.7-android-profile.apk. Source and archive checks ran locally;
Flutter tests and APK compilation must run on GitHub.

## 3.4.8 single progress bar and full-screen background

The Android island shows its compact progress strip only when collapsed.
Expanded and always-big modes use the single seek bar under the track controls.
The existing widget test checks that exactly one progress bar exists in each
state, keeping the animation timing and hit-target checks from 3.4.7.

The app now draws behind transparent Android status/navigation bars. Island
clearance is added to route SafeArea padding rather than padding the entire
Navigator, so the chosen background extends to the top edge instead of leaving
a black strip. The clock, battery icons and gesture navigation remain visible;
interactive controls still respect the system safe areas. Background selection
and opacity continue to apply normally.

The next optimized test artifact is Book-and-Quill-3.4.8-android-profile.apk.
Source and archive checks ran locally. Flutter tests and APK compilation must
run on GitHub; appearance under system bars must be checked on the phone.

## First local build on Windows (optional)

1. Install Android Studio and its Android SDK, SDK command-line tools, build
   tools, platform tools, NDK (Side by side), and CMake. Keep using your Flutter
   SDK; this project requires Flutter 3.44 or newer and Dart 3.12 or newer.
2. Open PowerShell in the project folder and run:

   ```powershell
   flutter doctor --android-licenses
   flutter doctor -v
   .\tools\build_android.ps1
   ```

   Review the license prompts yourself. Resolve any Android toolchain errors
   from `flutter doctor` before building. Android Studio's bundled Java runtime
   is suitable when configured by Flutter.

3. The test APK is written to:

   ```text
   dist\3.4.8\android\Book-and-Quill-3.4.8-android-debug.apk
   ```

   Copy it to your Android device to install, or enable USB debugging and run:

   ```powershell
   flutter devices
   .\tools\build_android.ps1 -Install -DeviceId YOUR_ANDROID_DEVICE_ID
   ```

The setup script generates the missing Android Gradle files using the installed
Flutter SDK's official template, then merges them without overwriting the custom
Android activity or changing Windows files. It sets the application ID to
`com.shantiashams.book_and_quill` through the generated organization/project name.
The minimum Android API is at least 23 (Android 6), or the SDK template's higher
minimum. Do not run `flutter create . --overwrite` over this project.

The existing imported textures, music, sounds and fonts are bundled by Flutter
into the APK. The launcher uses `book_and_quil.png`. Keep your existing
`assets/imported` folder; importing Minecraft assets still happens on your PC,
not on the Android device. Setup reports missing required icons/fonts.

## Touch controls

- Tap a book or an empty slot to open it. Swipe horizontally to change shelves.
- Long-press a book for Rename, Customize, Move, Export, and Remove.
- Tap the shelf title to rename it; hold it or tap the three-dot button for the
  shelf menu. Shelf deletion keeps its confirmation.
- Phones use one page. Wide screens can use two pages through Tools; rotating
  a spread into a narrow window returns it to one page without dropping text.
- Tap Tools for formatting, colors, alignment, date, undo, export and signing.
  Select text before opening Tools to format a selection. Tap the page again to
  resume typing. Pages scroll vertically above the software keyboard.
- Use the large bottom arrows to turn pages. Android Back hides the keyboard
  first, then saves and closes the book. The top back arrow and Done also save.
- Tap the music island arrow to open/close it; drag its progress bar to seek.
  The island moves out of the way while the software keyboard is open.

## Storage and platform behavior

Android stores books, settings, shelf names and statistics in the application's
private files directory. Updates installed with the same application ID and
signing key retain that data. Uninstalling or clearing app storage removes it;
export important books as `.qbook` files first. Android automatic cloud backup
is disabled; this app does not sync your writing to an account.

Import (Settings) and Export use Android's document picker. You can select a
local or cloud document provider without granting access to all device storage.
`.qbook` files transfer between Windows and Android with formatting, appearance,
dates and signed status intact. An individual import is capped at 32 MB to
avoid exhausting a phone's memory; page creation remains unlimited.

Music and sound effects play inside the app. Music pauses when the app is
backgrounded or a document picker opens, and resumes on return if it was playing.
A manually paused track stays paused. This first Android version does not run a
background playback service, expose lock-screen media controls, or inspect other
apps' media. Windows media integration remains available on Windows. F1's
transparent desktop window and mouse-edge resizing are also Windows features.

## Signed release APK or Play Store bundle

Use a debug APK for the first device test. For a distributable release, create
your own upload key outside the repository (with `keytool` from your Java SDK):

```powershell
keytool -genkeypair -v -keystore "$env:USERPROFILE\book-and-quill-upload.jks" -keyalg RSA -keysize 2048 -validity 10000 -alias upload
Copy-Item .\android\key.properties.example .\android\key.properties
```

Edit `android/key.properties` with your actual file path, alias and passwords.
Use forward slashes in the file path. Keep this key and passwords backed up;
future APK updates need the same signing identity. The Android ignore file
excludes `key.properties` and keystores. Never commit them to GitHub.

```powershell
.\tools\build_android.ps1 -Mode release
# Or create an Android App Bundle for Play Console:
.\tools\build_android.ps1 -Mode release -Bundle
```

The script refuses to package a release without signing configuration. It never
falls back to a debug signing key. A bundle is uploaded to Play Console, not
installed directly. A debug APK and a release APK use different signing keys;
export test books before uninstalling a debug copy to install a release copy.

If you already added your own Android Gradle project, preserve it separately
before applying this update. The setup script expects the standard Kotlin DSL
Flutter template and stops if it cannot recognize the signing block.

## Checks and validation status

`build_android.ps1` runs the model/storage/controller/widget tests and the new
Android regression suite before compiling. The new suite covers app-private
storage, document cancellation and round trips, input composition, touch menus,
phone keyboard layouts, tablet rotation, and controller cleanup when closing
dialogs. Native document-provider behavior and audio still need a real device.

This update was inspected and its archive verified in an environment without
Flutter or the Android SDK. No Android APK has been compiled or device-tested
there. The commands above perform those build checks on your PC.

Before publishing, check writing, auto-pagination, rotation with the keyboard
open, import/export including cancellation, shelf moves, signed books, music
pause/resume, and installing an update over the same signed app.

Official references: [Flutter Android setup](https://docs.flutter.dev/platform-integration/android/setup),
[Android releases and signing](https://docs.flutter.dev/deployment/android),
[Android document access](https://developer.android.com/training/data-storage/shared/documents-files).
