# Book and Quill

A Minecraft-inspired desktop writing app built with **Dart and Flutter**, by
**SHANTIASHAMS**.

Starting with **version 3.3.2**, the project is available on GitHub.

**Not an official Minecraft product. Not approved by or associated with
Mojang or Microsoft.**

## Features

- Organize books on interactive bookshelves with drag-and-drop support.
- Write in single-page or two-page mode, with text colors and formatting.
- Customize book appearances and choose background textures and opacity.
- Search your library and highlight matching text when opening a result.
- Add editable dates, sign books, and import/export `.qbook` files.
- Use the music island for playback controls and Windows media integration.
- Press **F1** in the editor for transparent mode: only the book is visible,
  and it can be dragged and resized from its frame.
- Save books and settings automatically on your computer.

## Downloads

Published Windows builds will be available on the
[Releases page](https://github.com/shantiashams/book-and-quill/releases).
When available, use the x64 installer or extract the complete portable ZIP.
The source archive is for building the application, not for installation.

## Build from source on Windows

Requirements:

- Windows with the Flutter Windows desktop toolchain and Visual Studio's
  **Desktop development with C++** workload.
- Flutter **3.44.0 or newer** with Dart **3.12.0 or newer**, as required by
  the committed dependency lockfile. Use a known-working SDK; keep the
  lockfile instead of upgrading dependencies just to build.
- Python 3, Pillow, and fontTools to generate the local fonts.
- A locally installed, current Minecraft Java Edition client, including its
  downloaded asset index and objects. Launch that version through the
  official launcher first if its assets have not been downloaded.

Clone the repository and open PowerShell in its root:

```powershell
git clone https://github.com/shantiashams/book-and-quill.git
cd book-and-quill
py -3 -m pip install pillow fonttools
.\tools\import_minecraft_assets.ps1
```

The importer reads textures from a local client JAR and audio from the local
Minecraft asset store. You can choose a JAR explicitly:

```powershell
.\tools\import_minecraft_assets.ps1 -JarPath 'D:\Minecraft\versions\YOUR_VERSION\YOUR_VERSION.jar'
```

Before building, confirm that the importer generated both font files:

```powershell
Test-Path .\assets\imported\fonts\minecraft_local_v2.ttf
Test-Path .\assets\imported\fonts\minecraft_book_grid_v3.ttf
```

Both must return `True`. Fonts are intentionally not committed. If generation
fails, resolve the Python/font-conversion error and rerun the importer; do
not rely on its older messages about a bundled fallback font.

Then restore locked dependencies and run the app:

```powershell
flutter pub get --enforce-lockfile
.\tools\run_windows.ps1
```

See [asset setup](assets/imported/README.md) for optional player-head and
album-cover images. Missing optional images use the app's fallback rendering.

## Build an installer

After the local asset setup, install [Inno Setup](https://jrsoftware.org/isdl.php)
6.3 or newer; **7.1 x64 works with the packaging script**. Close the running
app and execute:

```powershell
.\tools\package_windows.ps1
```

This creates an installer, a portable ZIP, and checksums under
`dist/3.3.2/<build-id>/`. Use `-CheckOnly` to check packaging prerequisites.
For a custom compiler location, use `-InnoCompiler 'D:\Tools\Inno Setup 7\ISCC.exe'`.

The package script uses the displayed version from `lib/app_version.dart`
and the build number in `pubspec.yaml`. Update both version declarations
together for future releases, and keep the installer AppId unchanged.

Building with locally imported media also bundles that media into the
installer. Excluding assets from Git does not remove them from compiled
releases. Review the distribution approach and required permissions before
publishing binaries; this source setup is not an end-user asset importer.

## Tests and current limitations

Run the current model, storage, and editing-controller tests with:

```powershell
flutter test test/book_record_test.dart test/book_storage_test.dart test/rich_text_editing_controller_test.dart
```

Those nine tests passed in the 3.3.2 Windows packaging run, which also
successfully compiled the application and installer. This does not cover
every UI interaction. `test/widget_test.dart` still contains older page
constructor arguments and layout expectations and needs updating before
the entire test suite can pass. Analyzer warnings and deprecation notices
also remain. Windows installation and feature smoke tests are separate
from compilation.

## Save location

On Windows, books and settings are stored in:

```text
%LOCALAPPDATA%\Book and Quill
```

The installer uses a separate program directory and does not delete that
save folder during uninstallation. The portable build uses the same save
location. Back up your writing before testing updates.

## Assets and licensing

This project includes textures, sounds, music, fonts, and app icon assets sourced from or derived from Minecraft, alongside album artwork.

These assets belong to their respective rights holders. Their inclusion does not grant additional redistribution rights. See the [Minecraft usage guidelines](https://www.minecraft.net/en-us/usage-guidelines).

Third-party assets and dependencies retain their respective rights and license terms. No project-wide source-code license has been selected yet.


## Feedback

Report bugs or suggest improvements through
[GitHub Issues](https://github.com/shantiashams/book-and-quill/issues).
For bugs, include the app version, Windows version, steps to reproduce, and
relevant errors. Remove personal writing and private paths from public logs.
