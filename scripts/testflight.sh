#!/bin/bash
# Archives Pitstop, signs it for the App Store and uploads it to TestFlight with the App Store
# Connect API key named in .env at the repo root (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH).
# Export signs with the distribution certificate named in Pitstop/ExportOptions.plist and the
# "Pitstop App Store" profile, which must be installed once. The
# distribution certificate lives in the shared tvhome-signing keychain, unlocked here with
# SIGNING_KEYCHAIN_PASSWORD so signing never stops on a password prompt. Each build is numbered
# by the date and time, so every upload is new.
#
#   scripts/testflight.sh              # archive, export, upload
#   scripts/testflight.sh --no-upload  # archive and export only (build/export/Pitstop.ipa)
set -euo pipefail
cd "$(dirname "$0")/.."
upload=1
for arg in "$@"; do
  case "$arg" in
    --no-upload) upload=0 ;;
    *) echo "usage: $0 [--no-upload]" >&2; exit 2 ;;
  esac
done
env_value() { sed -n "s/^$1=//p" .env | tr -d '\r'; }
key_id=$(env_value ASC_KEY_ID)
issuer=$(env_value ASC_ISSUER_ID)
key_path=$(env_value ASC_KEY_PATH)
key_path=${key_path/#\~/$HOME}
auth=(-allowProvisioningUpdates -authenticationKeyPath "$key_path" -authenticationKeyID "$key_id" -authenticationKeyIssuerID "$issuer")
archive=build/Pitstop.xcarchive
export_dir=build/export
keychain=$HOME/Library/Keychains/tvhome-signing.keychain-db

security unlock-keychain -p "$(env_value SIGNING_KEYCHAIN_PASSWORD)" "$keychain"

xcodebuild archive -project Pitstop/Pitstop.xcodeproj -scheme Pitstop -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$archive" "${auth[@]}" \
  CURRENT_PROJECT_VERSION="$(date +%Y%m%d%H%M)" -quiet
rm -rf "$export_dir"
# Apple's openrsync runs `rsync` from PATH, and Homebrew's rejects its options.
PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild -exportArchive -archivePath "$archive" \
  -exportPath "$export_dir" -exportOptionsPlist Pitstop/ExportOptions.plist "${auth[@]}" -quiet
ipa="$export_dir/Pitstop.ipa"
if [ "$upload" = 0 ]; then
  echo "Exported $PWD/$ipa (not uploaded)"
  exit 0
fi
# altool finds the key by its ID in ~/.appstoreconnect/private_keys.
xcrun altool --upload-app -t ios -f "$ipa" --apiKey "$key_id" --apiIssuer "$issuer"
