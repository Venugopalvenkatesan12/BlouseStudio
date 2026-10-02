# Blouse Studio - get your APK using GitHub (no software to install)

1. Create a free account at github.com and click New repository (name: blouse-studio, Public or Private).
2. On the new repository page click "uploading an existing file". On a PC, open this unzipped folder and drag in
   EVERYTHING: the `lib` folder, `.github` folder, `pubspec.yaml` and `.gitignore`.
   (Folder `.github/workflows/build.yml` MUST keep that exact path. If the `.github` folder will not upload,
   choose Add file > Create new file, type  .github/workflows/build.yml  as the name and paste the file's text.)
3. Click Commit changes.
4. Open the "Actions" tab > "Build Android APK". Wait about 8-10 minutes for the green tick.
   (If it does not start: click the workflow > Run workflow.)
5. Click the finished run > scroll to Artifacts > download "BlouseStudio-apk" (a zip containing app-release.apk).
6. Copy app-release.apk to the Moto Edge 70 Fusion, tap it, allow "Install unknown apps", install.

First use: default PIN is 1234 (change it in Settings, the gear icon).
Printer: phone and printer on the same WiFi, Mopria / HP Print Service / Epson Print Enabler turned on.
If the build shows a red cross, open the failed step and send me the error text.


## Windows PC version (same app)
The same GitHub build also makes a Windows program. In step 5 download the artifact "BlouseStudio-windows" as well.
Unzip it to a folder (e.g. C:\BlouseStudio), keep ALL files together, and double-click blouse_studio.exe
(right-click > Send to > Desktop to make a shortcut). Printing uses your normal Windows printer dialog.
If Windows says a DLL is missing, install the free "Microsoft Visual C++ Redistributable (x64)".
PC data is stored separately from the phone (no sync yet). Camera button is replaced by "Choose photo" on PC.
