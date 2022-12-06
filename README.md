# Appcircle _Firebase Upload dSYM_ component

Upload debug symbols to Firebase. This step must be added **after** `Xcodebuild for Devices` step.

## Required Inputs

- `AC_FIREBASE_EXPORT_ALL`: Export all debug symbols including frameworks. If you want to export only the app's debug symbols, set this to NO.
- `AC_FIREBASE_PLIST_PATH`: Path of the GoogleService-Info.plist. Full path of GoogleService-Info.plist file. For example $AC_REPOSITORY_DIR/GoogleService-Info.plist
- `AC_FIREBASE_CRASHLYTICS_PATH`: Path of the Crashlytics uploader. Full path of Crashlytics `upload-symbols` binary. 

|Project Type|Path|
|------------|----|
|Native iOS CocoaPods|$AC_REPOSITORY_DIR/Pods/FirebaseCrashlytics/upload-symbols|
|Native iOS SPM|$HOME/Library/Developer/Xcode/DerivedData/**/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols|
|React Native iOS|$AC_REPOSITORY_DIR/ios/Pods/FirebaseCrashlytics/upload-symbols|
|Flutter iOS|$AC_REPOSITORY_DIR/ios/Pods/FirebaseCrashlytics/upload-symbols|
