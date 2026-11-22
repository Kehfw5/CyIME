#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# CyIME iOS CI signing setup.
#
# Imports an enterprise (.p12) distribution identity into a throwaway keychain
# and installs two provisioning profiles (app + keyboard extension) so that
# `xcodebuild -exportArchive` can re-sign an unsigned archive.
#
# Required environment variables (passed in as GitHub secrets):
#   IOS_P12_BASE64                base64 of the .p12 (cert + private key)
#   IOS_P12_PASSWORD              password used to export the .p12
#   IOS_PROFILE_APP_BASE64        base64 of the In-House profile for com.cyletix.cyime
#   IOS_PROFILE_KEYBOARD_BASE64   base64 of the In-House profile for com.cyletix.cyime.keyboard
#
# Both profiles MUST have the App Group "group.com.cyletix.cyime" enabled.
#
# Exports to $GITHUB_ENV (so later workflow steps can read them):
#   PROFILE_APP_NAME / PROFILE_KEYBOARD_NAME   (used in ExportOptions.plist)
# ---------------------------------------------------------------------------
set -euo pipefail

KEYCHAIN_NAME="cyime-ci.keychain"
KEYCHAIN_PASS="cyime-ci-$(date +%s)"
GITHUB_ENV="${GITHUB_ENV:-}"

require() {
  if [[ -z "${!1:-}" ]]; then
    echo "::error::Missing required secret: $1"
    exit 1
  fi
}
require IOS_P12_BASE64
require IOS_P12_PASSWORD
require IOS_PROFILE_APP_BASE64
require IOS_PROFILE_KEYBOARD_BASE64

# 1. Import the distribution identity into a fresh keychain ---------------
echo "$IOS_P12_BASE64" | base64 --decode > /tmp/cyime-dist.p12

security create-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN_NAME"
security set-keychain-settings -lut 21600 "$KEYCHAIN_NAME"   # auto-lock after 6h
security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN_NAME"
security import /tmp/cyime-dist.p12 \
  -P "$IOS_P12_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN_NAME"
security list-keychain -d user -s "$KEYCHAIN_NAME" "login.keychain"
# Suppress the "codesign wants to use keychain" dialog:
security set-key-partition-list -S apple-tool:,apple: -s \
  -k "$KEYCHAIN_PASS" "$KEYCHAIN_NAME" >/dev/null 2>&1 || true

# Sanity: show the identity we just imported
echo "--- available signing identities ---"
security find-identity -v -p codesigning "$KEYCHAIN_NAME" | tail -n +1 || true

# 2. Install provisioning profiles ---------------------------------------
PP_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$PP_DIR"

install_profile() {
  local b64="$1" env_name="$2"
  echo "$b64" | base64 --decode > /tmp/pp.mobileprovision
  security cms -D -i /tmp/pp.mobileprovision > /tmp/pp.plist
  local uuid name app_id
  uuid=$(/usr/libexec/PlistBuddy -c "Print :UUID" /tmp/pp.plist)
  name=$(/usr/libexec/PlistBuddy -c "Print :Name" /tmp/pp.plist)
  app_id=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:application-identifier" /tmp/pp.plist 2>/dev/null || echo "?")
  cp /tmp/pp.mobileprovision "$PP_DIR/$uuid.mobileprovision"
  echo "Installed profile '$name' ($uuid) app-id=$app_id"
  if [[ -n "$GITHUB_ENV" ]]; then
    echo "${env_name}=${name}" >> "$GITHUB_ENV"
  fi
}

install_profile "$IOS_PROFILE_APP_BASE64"      PROFILE_APP_NAME
install_profile "$IOS_PROFILE_KEYBOARD_BASE64" PROFILE_KEYBOARD_NAME

echo "Signing setup complete."
