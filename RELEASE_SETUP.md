# Book and Quill 3.3.2 - Windows release kit

This is the installer/build setup, not a compiled application. No GitHub
repository or release has been created. It adds new files to your working
project; it does not replace your Dart code, native media bridge, or assets.

## Build on your Windows PC

1. Extract this ZIP into the same folder as your project's `pubspec.yaml`.
   You should now have `tools/package_windows.ps1` and
   `installer/book_and_quill.iss` in that project.
2. Close Book and Quill. Use your already-working Flutter/Visual Studio
   environment. The uploaded lockfile requires Flutter >=3.44.0 and
   Dart >=3.12.0; do not downgrade the SDK or regenerate the lockfile.
3. Install [Inno Setup](https://jrsoftware.org/isdl.php), version 6.3 or newer.
   **Inno Setup 7.1 x64 is supported.** It is needed on the build PC, not on
   users' PCs. The script searches the standard Inno Setup 7 and 6 folders.
4. Open PowerShell in the project folder and run:

```powershell
.\tools\package_windows.ps1
```

If Windows blocks a downloaded script, review its contents and unblock the
download in its Properties dialog if you trust it. Do not disable security
software or change a managed execution policy.

Check prerequisites without building:

```powershell
.\tools\package_windows.ps1 -CheckOnly
```

For a nonstandard Inno Setup installation:

```powershell
.\tools\package_windows.ps1 -InnoCompiler 'D:\Tools\Inno Setup 6\ISCC.exe'
```

If the earlier kit rejected Inno Setup 7 with "This installer needs Inno
Setup 6.3 or newer", replace `tools/package_windows.ps1` with this corrected
copy and rerun it. That check incorrectly used the EXE's Windows file-version
metadata. It has been removed; Inno validates the installer directives when
compiling, and compiler failures still stop packaging. Explicit
`-InnoCompiler` paths and compilers on PATH continue to take precedence over
standard installation folders. The app version remains 3.3.2.

## Output

The script prints the exact output directory, under
`dist/3.3.2/<timestamp-unique-id>/`. Each build gets a new directory, so an
earlier installer is not overwritten.

- `Book-and-Quill-3.3.2-windows-x64-setup.exe` - per-user installer, Start menu
  shortcut, optional desktop shortcut, and Windows uninstall entry.
- `Book-and-Quill-3.3.2-windows-x64-portable.zip` - full executable/DLL/data
  bundle. Extract the entire ZIP, then run `book_and_quill.exe`.
- `SHA256SUMS.txt` - SHA-256 checksums for those two files.
- `Book and Quill/` - staged runtime files, useful for a local smoke test.

This release targets x64 Windows 10/11, not ARM64 or 32-bit Windows. It includes
the Visual C++ runtime DLLs from your installed Visual Studio redistributable
directory. The build machine still needs Flutter, Visual Studio C++ tools,
and network access for the locked Dart dependencies.

The portable ZIP is installation-free, not data-portable: both versions use
`%LOCALAPPDATA%\Book and Quill` for your library/settings. No saved books are
copied into either package. The installer puts program files in the separate
`%LOCALAPPDATA%\Programs\Book and Quill` directory. Its uninstall rules do not
remove the save folder.

## What the build script does

- Checks required files, Flutter, Inno Setup, and Visual C++ runtime files.
- Refuses to build while Book and Quill is running; it does not kill processes.
- Runs `flutter clean` to discard only generated Flutter build caches. This
  also addresses the CMake cache mismatch caused by moving the project.
- Restores dependencies with `flutter pub get --enforce-lockfile`.
- Analyzes `lib/`, treating errors as fatal while reporting warnings/infos.
- Runs the three existing data/controller test files. It does **not** claim
  full test-suite coverage: the uploaded `test/widget_test.dart` still uses
  old PageSheet arguments and old layout expectations, and needs updating.
- Rebuilds your icon using the existing `book_and_quil.png` icon generator.
- Builds Windows Release using `AppVersion.value` from `lib/app_version.dart`
  and the numeric build suffix in `pubspec.yaml`. The upload's stale
  `1.11.0+21` value is overridden with `3.3.2+21` for this release, without
  changing runtime code. The script verifies the resulting EXE version.
- Stages the full runtime bundle, excluding PDB debug symbols and local
  `import_status.json` path metadata, and retains Flutter's dependency notices.
- Creates the installer, portable ZIP, and checksums. Nothing is uploaded.

For future updates, update `lib/app_version.dart` and increment the build
suffix in `pubspec.yaml`. Keep their version strings aligned for ordinary
builds too. Keep the installer `AppId` unchanged across releases.

## Test before publishing

This kit was inspected and its ZIP verified in a Linux environment. It was
not executed with PowerShell, Flutter, MSVC, or Inno Setup here. Successful
Windows compilation and the following checks are still required:

- Run the installer as a normal user; verify the icon and version 3.3.2.
- Check writing/saving, reopening books, rename cancellation, and search.
- Check music controls/Windows media integration and transparent F1 mode,
  including dragging and resizing the book.
- Check the portable ZIP on a clean Windows machine without Flutter or
  Visual Studio installed, especially for missing DLLs, assets, and music.
- Back up the save folder, then test reinstall/upgrade/uninstall: notes must
  survive. Keep the default separate installation and save directories.
- Investigate analyzer warnings and refresh the outdated widget tests before
  describing the project as fully tested.
- A locally built installer is unsigned. Public distribution should include
  a code-signing and trust plan; this kit does not sign the executable.

## GitHub publishing - decisions still needed

Provide the target GitHub repository URL, or choose its owner/name and
visibility. Also choose a source-code license; none has been selected for you.
There is no connected GitHub publishing tool in this session.

The uploaded project includes Minecraft textures, derived fonts, game music,
album art, and an item-based app icon. The current importer works on the
developer's machine **before compiling**. It is not an installer/first-run
importer: a compiled release currently bundles those files. Ignoring the
source assets in Git does not remove them from an installer or portable ZIP.

Before public distribution, choose a reviewed asset/branding approach:
obtain the needed permissions, replace assets with ones you can distribute,
or implement end-user local asset importing. The last option needs a runtime
asset-loading change; it has not been silently added to this working build.
An unofficial-project disclaimer is useful but is not a redistribution
license. Review the [Minecraft usage guidelines](https://www.minecraft.net/en-us/usage-guidelines)
and the rights for music and cover artwork separately.

Do **not** upload the original full project archive to a public repository.
Before staging source, exclude generated files, imported media/fonts/icons,
local paths, credentials, signing keys, and personal saves. The supplied
`release/GITIGNORE_PUBLIC.txt` is a fragment to review and merge, not an
automatic repository change. Ignore rules do not untrack existing commits.

Once the assets, license, repository, and Windows smoke tests are resolved:

1. Commit the reviewed source, installer, lockfile, and release scripts.
2. In the repository, choose **Releases > Draft a new release**.
3. Use tag `v3.3.2` targeting the exact tested source commit and title
   `Book and Quill 3.3.2`.
4. Attach the reviewed installer, portable ZIP, and `SHA256SUMS.txt` from the
   same build. Keep it as a draft until you have checked every attachment.
5. Publish only after the above review. A GitHub Actions build can be added
   once CI has an approved way to obtain the required assets and a pinned,
   tested Flutter SDK. This kit does not add a workflow that would fail
   because the imported assets are absent from a clean checkout.

## Reference documentation

- [Flutter Windows versioning and releases](https://docs.flutter.dev/deployment/windows)
- [Flutter commands, including clean](https://docs.flutter.dev/reference/flutter-cli)
- [Inno Setup compiler](https://jrsoftware.org/ishelp/topic_compilercmdline.htm)
- [Inno per-user installation](https://jrsoftware.org/ishelp/topic_setup_privilegesrequired.htm)
- [Microsoft app-local runtime deployment](https://learn.microsoft.com/en-us/cpp/windows/walkthrough-deploying-a-visual-cpp-application-to-an-application-local-folder?view=msvc-170)
- [Creating GitHub releases](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)
