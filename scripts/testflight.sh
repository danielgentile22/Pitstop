#!/bin/bash
# Archives Pitstop, signs it for the App Store and uploads it to TestFlight with the App Store
# Connect API key named in .env at the repo root (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH).
# Export signs with the distribution certificate named in Pitstop/ExportOptions.plist and the
# "Pitstop App Store" profile, which must be installed once. The
# distribution certificate lives in the shared tvhome-signing keychain, unlocked here with
# SIGNING_KEYCHAIN_PASSWORD (passed on stdin, so it never shows in the process list) so signing
# never stops on a password prompt, and locked again on every exit. Each build is numbered by
# the UTC date and time to the second, so every upload is new.
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
[ -f .env ] || { echo "error: $PWD/.env not found" >&2; exit 1; }
env_value() { sed -n "s/^$1=//p" .env | tr -d '\r'; }
for name in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH SIGNING_KEYCHAIN_PASSWORD; do
  [ -n "$(env_value "$name")" ] || { echo "error: $name is missing from .env" >&2; exit 1; }
done
key_id=$(env_value ASC_KEY_ID)
issuer=$(env_value ASC_ISSUER_ID)
key_path=$(env_value ASC_KEY_PATH)
key_path=${key_path/#\~/$HOME}
[ -f "$key_path" ] || { echo "error: ASC_KEY_PATH file not found: $key_path" >&2; exit 1; }
auth=(-allowProvisioningUpdates -authenticationKeyPath "$key_path" -authenticationKeyID "$key_id" -authenticationKeyIssuerID "$issuer")
archive=build/Pitstop.xcarchive
export_dir=build/export
keychain=$HOME/Library/Keychains/tvhome-signing.keychain-db

trap 'security lock-keychain "$keychain"' EXIT
env_value SIGNING_KEYCHAIN_PASSWORD | security unlock-keychain "$keychain"

xcodebuild archive -project Pitstop/Pitstop.xcodeproj -scheme Pitstop -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$archive" "${auth[@]}" \
  CURRENT_PROJECT_VERSION="$(date -u +%Y%m%d%H%M%S)" -quiet
rm -rf "$export_dir"
# Apple's openrsync runs `rsync` from PATH, and Homebrew's rejects its options.
PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild -exportArchive -archivePath "$archive" \
  -exportPath "$export_dir" -exportOptionsPlist Pitstop/ExportOptions.plist "${auth[@]}" -quiet
ipa="$export_dir/Pitstop.ipa"
if [ "$upload" = 0 ]; then
  echo "Exported $PWD/$ipa (not uploaded)"
  exit 0
fi
xcrun altool --upload-app -t ios -f "$ipa" --apiKey "$key_id" --apiIssuer "$issuer" \
  --p8-file-path "$key_path"
