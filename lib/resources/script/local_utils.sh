#!/usr/bin/env bash

# utils run locally

set -e
#set -x

# constants
dummy_ssh_keys_dir='dummy-ssh-keys'
fastlane_dir='ios/fastlane'

main(){
  case $1 in
    --build-debug-ipa)
        build_debug_ipa
        ;;
    --ci)
        if [[ -z $2 ]]; then show_help; fi
        config_ci $2
        ;;
    *)
        show_help
        ;;
  esac
}

show_help() {
    printf "\n\nusage: %s [--build-debug-ipa] [--ci <staging dir>]

Utilities ran locally

where:
    --build-debug-ipa
        package a debug app as a .ipa
        (app must include 'enableFlutterDriverExtension()')
    --ci <staging dir>
        configure a CI build environment
    --help
        print this message
" "$(basename "$0")"
    exit 1
}

# constants
default_debug_ipa_name='Debug_Runner.ipa'
default_debug_ipa_dir="."

# install certificate and provisioning profile using match
# assumes resources unbundled from sylph
config_ci() {
  local app_dir=$1

  # install fastfiles
#  cp -r "$staging_dir/fastfile" 'ios'
#  cp "$staging_dir/Gemfile*" 'ios'
#
#  # install dummy keys
#  cp -r "$staging_dir/$dummy_ssh_keys_dir" '.'
#
#  echo "Installed fastfiles and keys"

  # setup ssh for fastlane match
  # set default identity file
  cat << EOF > ~/.ssh/config
Host *
AddKeysToAgent yes
UseKeychain yes
IdentityFile $app_dir/dummy-ssh-keys/key
EOF

  # add MATCH_HOST public key to known hosts
  ssh-keyscan -t ecdsa -p $MATCH_PORT $MATCH_HOST >> ~/.ssh/known_hosts
  chmod 600 "$app_dir/dummy-ssh-keys/key"
  chmod 700 "$app_dir/dummy-ssh-keys"

  # install fastlane
  gem install bundler:2.0.1 # the fastlane gem file requires bundler 2.0
  (cd "$app_dir/ios"; bundle install)

  # call match to install developer certificate and provisioning profile
  (cd "$app_dir/ios"; fastlane enable_match_code_signing mode:debug)
}

# currently assumes using forked version of flutter with archiving of debug .app permitted.
# todo: remove this restriction by permitting on the fly
build_debug_ipa() {
    APP_NAME="Runner"
    FINAL_APP_NAME="Debug_Runner"
    SCHEME=$APP_NAME

#    IOS_BUILD_DIR=$PWD/build/ios/Release-iphoneos
    IOS_BUILD_DIR=$PWD/build/ios/Debug-iphoneos
#    CONFIGURATION=Release
    CONFIGURATION=Debug
#    export FLUTTER_BUILD_MODE=Release
    export FLUTTER_BUILD_MODE=Debug
    APP_COMMON_PATH="$IOS_BUILD_DIR/$APP_NAME"
    ARCHIVE_PATH="$APP_COMMON_PATH.xcarchive"

    echo "Building debug .ipa for upload to Device Farm..."
    flutter clean > /dev/null
    flutter packages get > /dev/null # in case building from a different flutter repo
    echo "Running flutter build ios -t test_driver/main.dart --debug..."
    flutter build ios -t test_driver/main.dart --debug

    echo "Generating debug archive..."
    xcodebuild archive \
      -workspace ios/$APP_NAME.xcworkspace \
      -scheme $SCHEME \
      -sdk iphoneos \
      -configuration $CONFIGURATION \
      -archivePath "$ARCHIVE_PATH" \
      | xcpretty

    echo "Generating debug .ipa at $IOS_BUILD_DIR/$APP_NAME.ipa..."
    xcodebuild -exportArchive \
      -archivePath "$ARCHIVE_PATH" \
      -exportOptionsPlist ios/exportOptions.plist \
      -exportPath "$IOS_BUILD_DIR" \
      | xcpretty

    # rename debug .ipa to standard name
    mv "$IOS_BUILD_DIR/$APP_NAME.ipa" "$IOS_BUILD_DIR/$default_debug_ipa_name"

    echo "Debug .ipa successfully created in $IOS_BUILD_DIR/$default_debug_ipa_name"
}

main "$@"