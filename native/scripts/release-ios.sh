#!/bin/zsh
# Build Glimmer for iPhone and iPad and upload it to TestFlight.
#
#   native/scripts/release-ios.sh [--build N]
#
# Uses the version in native/Glimmer.xcconfig. The build number defaults to one more than the newest
# build App Store Connect has for that version. See native/RELEASING.md for what it expects.
set -euo pipefail

build=""
while (( $# )); do
    case "$1" in
        --build) build="$2"; shift 2 ;;
        *) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
    esac
done

root="${0:A:h:h:h}"
native="$root/native"
team="22HV69L32T"
bundle_id="com.protomota.glimmer"
app_id="6837750690"                      # Glimmer: Gentle Life Coach in App Store Connect
profile_name="Glimmer App Store 2"
version="$(sed -n 's/^MARKETING_VERSION = //p' "$native/Glimmer.xcconfig" | head -1)"

work="${GLIMMER_RELEASE_DIR:-/Volumes/Expand/Projects/Glimmer/glimmer-release}"
if [[ -z "${GLIMMER_RELEASE_DIR:-}" && ! -d /Volumes/Expand ]]; then
    echo "The Expand drive is not mounted. Mount it or set GLIMMER_RELEASE_DIR." >&2; exit 1
fi
secrets="$(mktemp -d)"; chmod 700 "$secrets"
trap 'rm -rf "$secrets"' EXIT
step() { print -P "\n%B== $1%b"; }

# --- Credentials: the team's App Store Connect upload key, from the environment or Bitwarden Secrets
# Manager. The default prefix is the same upload credential Jotley's release script uses.
bws_value() {
    local token="${BWS_ACCESS_TOKEN:-$(launchctl getenv BWS_ACCESS_TOKEN 2>/dev/null || true)}"
    [[ -n "$token" ]] || return 1
    BWS_ACCESS_TOKEN="$token" bws secret list --output json 2>/dev/null |
        /usr/bin/python3 -c 'import json,sys; print(next(s["value"] for s in json.load(sys.stdin) if s["key"]==sys.argv[1]).replace("\\n", "\n"), end="")' "$1"
}
if [[ -z "${APPLE_API_KEY_ID:-}" ]]; then
    prefix="${GLIMMER_ASC_SECRET_PREFIX:-INKSPRING_ASC_UPLOAD}"
    APPLE_API_KEY_ID="$(bws_value "${prefix}_KEY_ID")"
    APPLE_API_ISSUER="$(bws_value "${prefix}_ISSUER_ID")"
    ( umask 077; bws_value "${prefix}_PRIVATE_KEY" > "$secrets/AuthKey_$APPLE_API_KEY_ID.p8"; echo >> "$secrets/AuthKey_$APPLE_API_KEY_ID.p8" )
else
    ( umask 077; cp "$APPLE_API_KEY_PATH" "$secrets/AuthKey_$APPLE_API_KEY_ID.p8" )
fi
export APPLE_API_KEY_ID APPLE_API_ISSUER
export APPLE_API_KEY_FILE="$secrets/AuthKey_$APPLE_API_KEY_ID.p8"
api() { /usr/bin/python3 "$native/scripts/asc.py" "$@"; }

if [[ -z "$build" ]]; then
    build=$(( $(api latest-build "$app_id" "$version") + 1 ))
fi
out="$work/ios-$version-$build"
mkdir -p "$out"

# --- Signing: the App Store profile, installed from native/signing when it is missing.
profile_dir="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
if [[ -f "$native/signing/Glimmer_App_Store.mobileprovision" ]]; then
    mkdir -p "$profile_dir"
    cp "$native/signing/Glimmer_App_Store.mobileprovision" "$profile_dir/Glimmer_App_Store.mobileprovision"
fi

if [[ -f "$out/export/Glimmer.ipa" ]]; then
    echo "Using the build already exported in $out."
    ipa="$out/export/Glimmer.ipa"
else
    step "Archive Glimmer $version ($build) for iPhone and iPad"
    archive="$out/Glimmer.xcarchive"
    xcodebuild archive -project "$native/Glimmer.xcodeproj" -scheme Glimmer -configuration Release \
        -destination 'generic/platform=iOS' -archivePath "$archive" -derivedDataPath "$work/derived-ios-release" \
        CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=Apple Distribution" "DEVELOPMENT_TEAM=$team" \
        "GLIMMER_IOS_RELEASE_PROFILE=$profile_name" \
        MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build" > "$out/archive.log" 2>&1 ||
        { grep -E "error:" "$out/archive.log" | tail -20 >&2; exit 1; }

    step "Export for App Store Connect"
    cat > "$out/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
        <key>method</key><string>app-store-connect</string>
        <key>destination</key><string>export</string>
        <key>teamID</key><string>$team</string>
        <key>signingStyle</key><string>manual</string>
        <key>signingCertificate</key><string>Apple Distribution</string>
        <key>provisioningProfiles</key><dict><key>$bundle_id</key><string>$profile_name</string></dict>
        <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST
    xcodebuild -exportArchive -archivePath "$archive" -exportPath "$out/export" \
        -exportOptionsPlist "$out/ExportOptions.plist" > "$out/export.log" 2>&1 ||
        { grep -v IDEDistribution "$out/export.log" | tail -20 >&2; exit 1; }
    ipa="$(print -l "$out"/export/*.ipa | head -1)"
    [[ -f "$ipa" ]] || { echo "No IPA was exported." >&2; exit 1; }
fi

step "Verify exported iPhone and iPad icons"
/usr/bin/python3 "$native/scripts/check-ios-icons.py" "$ipa"

step "Upload to App Store Connect"
API_PRIVATE_KEYS_DIR="$secrets" xcrun altool --upload-app -f "$ipa" -t ios \
    --apiKey "$APPLE_API_KEY_ID" --apiIssuer "$APPLE_API_ISSUER" > "$out/upload.log" 2>&1 ||
    { tail -20 "$out/upload.log" >&2; exit 1; }
tail -3 "$out/upload.log"

step "Wait for Apple to process the build"
api wait-build "$app_id" "$version" "$build"

step "Make it available to internal testers"
api internal-group "$app_id" "$version" "$build"

echo "\nGlimmer $version ($build) is in TestFlight."
