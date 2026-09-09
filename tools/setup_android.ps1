#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$androidRoot = Join-Path $projectRoot 'android'
$utf8 = New-Object System.Text.UTF8Encoding($false)
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter was not found. Add Flutter bin to PATH, then reopen PowerShell.'
}
Push-Location $projectRoot
try {
    # Use the installed Flutter SDK's own Gradle/AGP/Kotlin versions rather
    # than pairing a downloaded Gradle wrapper with guessed plugin versions.
    $needsScaffold = -not (Test-Path (Join-Path $androidRoot 'settings.gradle.kts'))
    if ($needsScaffold -and (Test-Path (Join-Path $androidRoot 'settings.gradle'))) {
        throw 'An older Groovy Android project already exists. Move android aside and reapply this update before setup.'
    }
    if ($needsScaffold) {
        $temporaryProject = Join-Path ([IO.Path]::GetTempPath()) ('book-quill-android-' + [Guid]::NewGuid().ToString('N'))
        try {
            & flutter create --platforms=android --android-language=kotlin --org com.shantiashams --project-name book_and_quill --no-pub $temporaryProject
            if ($LASTEXITCODE -ne 0) { throw 'Flutter could not generate the Android build scaffold.' }
            $generatedAndroid = Join-Path $temporaryProject 'android'
            foreach ($source in Get-ChildItem $generatedAndroid -File -Recurse -Force) {
                $relative = $source.FullName.Substring($generatedAndroid.Length + 1)
                $destination = Join-Path $androidRoot $relative
                if (-not (Test-Path $destination)) {
                    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
                    Copy-Item -LiteralPath $source.FullName -Destination $destination
                }
            }
            # local.properties may contain the temporary project's paths.
            $localProperties = Join-Path $androidRoot 'local.properties'
            if (Test-Path $localProperties) { Remove-Item -LiteralPath $localProperties }
        } finally {
            if (Test-Path $temporaryProject) { Remove-Item -LiteralPath $temporaryProject -Recurse -Force }
        }
    }

    $buildFile = Join-Path $androidRoot 'app/build.gradle.kts'
    if (-not (Test-Path $buildFile)) { throw 'Android app/build.gradle.kts is missing. Run setup with a current stable Flutter SDK.' }
    $gradle = [IO.File]::ReadAllText($buildFile)
    if ($gradle -notmatch 'BOOK_AND_QUILL_SIGNING') {
        $debugSigning = 'signingConfig = signingConfigs.getByName("debug")'
        if (-not $gradle.Contains($debugSigning) -or $gradle -notmatch 'buildTypes\s*\{') {
            throw 'The Android Gradle template has an unfamiliar signing block. No signing settings were changed; follow ANDROID_SETUP.md.'
        }
        $signing = @'
    // BOOK_AND_QUILL_SIGNING: debug keys are never used for a release.
    signingConfigs {
        val propertiesFile = rootProject.file("key.properties")
        if (propertiesFile.exists()) {
            val signingProperties = Properties()
            propertiesFile.inputStream().use { signingProperties.load(it) }
            create("release") {
                keyAlias = signingProperties.getProperty("keyAlias")
                keyPassword = signingProperties.getProperty("keyPassword")
                storeFile = file(signingProperties.getProperty("storeFile"))
                storePassword = signingProperties.getProperty("storePassword")
            }
        }
    }

'@
        $gradle = $gradle.Replace($debugSigning, 'signingConfig = signingConfigs.findByName("release")')
        $buildTypesPattern = [regex]'(?m)^    buildTypes\s*\{'
        if (-not $buildTypesPattern.IsMatch($gradle)) { throw 'Could not locate the Android buildTypes block.' }
        $gradle = $buildTypesPattern.Replace($gradle, $signing + "`n    buildTypes {", 1)
        if ($gradle -notmatch '(?m)^import java.util.Properties') {
            $gradle = "import java.util.Properties`n`n" + $gradle
        }
        $gradle = $gradle.Replace('minSdk = flutter.minSdkVersion', 'minSdk = maxOf(23, flutter.minSdkVersion)')
        # Avoid the misleading stock template comment after changing signing.
        $gradle = [regex]::Replace($gradle, '(?m)^\s*// Signing with the debug keys.*\r?\n', '')
        $gradle = [regex]::Replace($gradle, '(?m)^\s*// so `flutter run --release`.*\r?\n', '')
        [IO.File]::WriteAllText($buildFile, $gradle, $utf8)
    }

    $icon = Join-Path $projectRoot 'assets/imported/textures/book_and_quil.png'
    $fonts = @('minecraft_local_v2.ttf', 'minecraft_book_grid_v3.ttf')
    if (-not (Test-Path $icon)) { throw 'Missing assets/imported/textures/book_and_quil.png. Keep your existing assets or run tools/import_minecraft_assets.ps1 first.' }
    foreach ($font in $fonts) {
        if (-not (Test-Path (Join-Path $projectRoot "assets/imported/fonts/$font"))) {
            throw "Missing $font. Keep your existing imported fonts before building."
        }
    }
    Copy-Item -LiteralPath $icon -Destination (Join-Path $androidRoot 'app/src/main/res/drawable/book_and_quil.png') -Force
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Flutter pub get failed.' }
    Write-Host 'Android setup complete. Run tools/build_android.ps1 for a test APK.' -ForegroundColor Green
} finally { Pop-Location }
