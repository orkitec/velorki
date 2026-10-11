fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

----


## Android

### android internal

```sh
[bundle exec] fastlane android internal
```

Build a signed AAB and upload it to the Play internal testing track

### android latest_version_code

```sh
[bundle exec] fastlane android latest_version_code
```

Write the highest version code on any Play track to LATEST_VERSION_CODE_FILE

### android store_listing

```sh
[bundle exec] fastlane android store_listing
```

Upload the Play screenshots, feature graphic and icon (and with UPLOAD_METADATA=true the texts) to the store listing

### android promote_closed

```sh
[bundle exec] fastlane android promote_closed
```

Promote the newest internal build to the closed test track

----


## iOS

### ios latest_build_number

```sh
[bundle exec] fastlane ios latest_build_number
```

Write the latest build number on App Store Connect to LATEST_BUILD_NUMBER_FILE

### ios store_assets

```sh
[bundle exec] fastlane ios store_assets
```

Upload the store screenshots (and with UPLOAD_METADATA=true the texts) to an App Store version

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
