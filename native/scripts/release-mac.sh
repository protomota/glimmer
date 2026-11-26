#!/bin/zsh
# Build, sign, notarize and publish a Glimmer Mac release.
#
#   native/scripts/release-mac.sh <version> [--notes "What changed"] [--build N] [--publish]
#
# Without --publish the script stops after staging the site files so you can review them.
# With --publish it commits the release to main, pushes, and waits for glimmertoday.ai to serve it.
# See native/RELEASING.md for the credentials it expects.
set -euo pipefail

usage() { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

version="" notes="Bug fixes and improvements." build="" publish=0
while (( $# )); do
    case "$1" in
        --notes) notes="$2"; shift 2 ;;
        --build) build="$2"; shift 2 ;;
        --publish) publish=1; shift ;;
        -h|--help) usage ;;
        *) [[ -z "$version" ]] && version="$1" && shift || usage ;;
    esac
done
[[ "$version" =~ '^[0-9]+(\.[0-9]+){1,2}$' ]] || usage

root="${0:A:h:h:h}"
native="$root/native"
config="$native/Glimmer.xcconfig"
site="$root/landing"
team="22HV69L32T"
bundle_id="com.protomota.glimmer"
site_url="https://glimmertoday.ai"

setting() { sed -n "s/^$1 = //p" "$config" | head -1; }
if [[ -z "$build" ]]; then build=$(( $(setting CURRENT_PROJECT_VERSION) + 1 )); fi
[[ "$build" =~ '^[0-9]+$' ]] || { echo "The build number must be a whole number." >&2; exit 2; }

work="${GLIMMER_RELEASE_DIR:-/Volumes/Expand/Projects/Glimmer/glimmer-release}"
if [[ -z "${GLIMMER_RELEASE_DIR:-}" && ! -d /Volumes/Expand ]]; then
    echo "The Expand drive is not mounted. Mount it or set GLIMMER_RELEASE_DIR." >&2; exit 1
fi
out="$work/$version-$build"
derived="$work/derived"
[[ ! -e "$out" ]] || { echo "$out already exists. Choose a new build number or remove it." >&2; exit 1; }
mkdir -p "$out"
secrets="$(mktemp -d)"; chmod 700 "$secrets"
trap 'rm -rf "$secrets"' EXIT

if (( publish )); then
    [[ "$(git -C "$root" branch --show-current)" == main ]] || { echo "Publish from main." >&2; exit 1; }
    [[ -z "$(git -C "$root" status --porcelain --untracked-files=no)" ]] || { echo "Commit or stash tracked changes first." >&2; exit 1; }
fi

step() { print -P "\n%B== $1%b"; }

# --- Credentials -----------------------------------------------------------------
# Apple notarization key: APPLE_API_KEY_PATH/APPLE_API_KEY_ID/APPLE_API_ISSUER, or Bitwarden Secrets Manager.
bws_value() {
    local token="${BWS_ACCESS_TOKEN:-$(launchctl getenv BWS_ACCESS_TOKEN 2>/dev/null || true)}"
    [[ -n "$token" ]] || return 1
    BWS_ACCESS_TOKEN="$token" bws secret list --output json 2>/dev/null |
        /usr/bin/python3 -c 'import json,sys; print(next(s["value"] for s in json.load(sys.stdin) if s["key"]==sys.argv[1]), end="")' "$1"
}
if [[ -z "${APPLE_API_KEY_PATH:-}" ]]; then
    APPLE_API_KEY_PATH="$secrets/AuthKey.p8"
    ( umask 077; bws_value APP_STORE_CONNECT_API_KEY > "$APPLE_API_KEY_PATH" ) ||
        { echo "No Apple API key. Set APPLE_API_KEY_PATH or add APP_STORE_CONNECT_API_KEY to Secrets Manager." >&2; exit 1; }
    APPLE_API_KEY_ID="$(bws_value APP_STORE_CONNECT_KEY_ID)"
    APPLE_API_ISSUER="$(bws_value APP_STORE_CONNECT_ISSUER_ID)"
fi
notary=(--key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER")

# Sparkle update key: GLIMMER_SPARKLE_EDDSA_PRIVATE_KEY, or the login Keychain entry made by generate_keys.
sparkle="$derived/SourcePackages/artifacts/sparkle/Sparkle/bin"
update_key="$secrets/sparkle.key"

notarize() {
    local receipt="$out/${1:t}.notarization.json"
    xcrun notarytool submit "$1" "${notary[@]}" --wait --output-format json > "$receipt"
    local notary_status="$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["status"])' "$receipt")"
    echo "Apple notarization: $notary_status"
    [[ "$notary_status" == Accepted ]] || { echo "Apple did not accept ${1:t}. See $receipt" >&2; exit 1; }
}

# --- Build and sign ---------------------------------------------------------------
# iCloud sync needs a Developer ID provisioning profile named below. With it installed (or checked in
# under native/signing) the release carries iCloud. Without it the release is signed with the same
# Developer ID certificate but leaves iCloud out, and the app says sync is unavailable.
profile_name="Glimmer Developer ID"
profile_dir="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
has_profile() {
    local file
    for file in "$profile_dir"/*.provisionprofile(N) "$HOME/Library/MobileDevice/Provisioning Profiles"/*.provisionprofile(N); do
        local decoded="$(security cms -D -i "$file" 2>/dev/null)"
        grep -A1 '<key>Name</key>' <<< "$decoded" | grep -q ">$profile_name<" && return 0
    done
    return 1
}
if ! has_profile && [[ -f "$native/signing/Glimmer_Developer_ID.provisionprofile" ]]; then
    mkdir -p "$profile_dir"
    cp "$native/signing/Glimmer_Developer_ID.provisionprofile" "$profile_dir/"
fi
signing=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=Developer ID Application" "DEVELOPMENT_TEAM=$team")
export_profiles=""
icloud=1
if has_profile; then
    signing+=("GLIMMER_RELEASE_PROFILE=$profile_name")
    export_profiles="<key>provisioningProfiles</key><dict><key>$bundle_id</key><string>$profile_name</string></dict>"
else
    icloud=0
    signing+=("GLIMMER_MAC_ENTITLEMENTS=Glimmer/Glimmer-Mac-Direct.entitlements")
    echo "No \"$profile_name\" provisioning profile is installed. This release will not include iCloud sync."
fi

step "Archive Glimmer $version ($build)"
archive="$out/Glimmer.xcarchive"
xcodebuild archive -project "$native/Glimmer.xcodeproj" -scheme Glimmer -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$archive" -derivedDataPath "$derived" \
    "${signing[@]}" MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build" > "$out/archive.log" 2>&1 ||
    { grep -E "error:|warning: .*provision" "$out/archive.log" | tail -20 >&2; exit 1; }

step "Export with Developer ID"
cat > "$out/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$team</string>
    <key>signingStyle</key><string>manual</string>
    <key>signingCertificate</key><string>Developer ID Application</string>
    $export_profiles
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$archive" -exportPath "$out/export" \
    -exportOptionsPlist "$out/ExportOptions.plist" \
    > "$out/export.log" 2>&1 || { grep -v IDEDistribution "$out/export.log" | tail -20 >&2; exit 1; }
app="$out/export/Glimmer.app"
codesign --verify --deep --strict --verbose=2 "$app"
# Capture each signature first: with pipefail, grep -q closing the pipe early looks like a failure.
signature="$(codesign -dv --verbose=4 "$app" 2>&1)"
grep -q "Authority=Developer ID Application: Protomota, LLC ($team)" <<< "$signature" ||
    { echo "The exported app is not signed with the Protomota Developer ID." >&2; exit 1; }
entitlements="$(codesign -d --entitlements - --xml "$app" 2>/dev/null)"
if (( icloud )) && ! grep -q "iCloud.$bundle_id" <<< "$entitlements"; then
    echo "The exported app lost its iCloud entitlement." >&2; exit 1
fi
grep -q "com.apple.security.network.client" <<< "$entitlements" ||
    { echo "The exported app cannot reach the update feed (no network entitlement)." >&2; exit 1; }
for helper in Autoupdate Updater.app XPCServices/Installer.xpc XPCServices/Downloader.xpc; do
    signature="$(codesign -dv "$app/Contents/Frameworks/Sparkle.framework/Versions/B/$helper" 2>&1)"
    grep -q "TeamIdentifier=$team" <<< "$signature" ||
        { echo "Sparkle's $helper is not signed with the Developer ID." >&2; exit 1; }
done

step "Notarize the app"
ditto -c -k --keepParent "$app" "$out/Glimmer.zip"
notarize "$out/Glimmer.zip"
xcrun stapler staple "$app"
spctl --assess --type execute --verbose=2 "$app"

# --- Installer ---------------------------------------------------------------------
step "Build the installer"
dmg="$out/Glimmer-$version.dmg"
# The shared Protomota Finder layout (native/installer), built with dmgbuild. The packaging tools live in
# their own Python environment, made on first use.
packaging_python="${GLIMMER_PACKAGING_PYTHON:-$work/installer-tools/bin/python}"
if ! "$packaging_python" -c 'import dmgbuild, ds_store, mac_alias' 2>/dev/null; then
    python3 -m venv "$work/installer-tools"
    "$work/installer-tools/bin/pip" install --quiet -r "$native/installer/requirements.txt"
    packaging_python="$work/installer-tools/bin/python"
fi
"$packaging_python" "$native/installer/package.py" "$app" "$dmg" > "$out/dmg.log" 2>&1 || { tail -20 "$out/dmg.log" >&2; exit 1; }
# Sign the installer with the same certificate Xcode used for the app.
codesign -d --extract-certificates="$secrets/cert" "$app"
identity="$(openssl x509 -inform DER -in "$secrets/cert0" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')"
codesign --force --sign "$identity" --timestamp "$dmg"
notarize "$dmg"
xcrun stapler staple "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"

# --- Update feed -------------------------------------------------------------------
step "Sign the update and write the feed"
if [[ -n "${GLIMMER_SPARKLE_EDDSA_PRIVATE_KEY:-}" ]]; then
    ( umask 077; print -rn -- "$GLIMMER_SPARKLE_EDDSA_PRIVATE_KEY" > "$update_key" )
else
    "$sparkle/generate_keys" --account "$bundle_id" -x "$update_key" > /dev/null
fi
feed="$out/feed"; mkdir "$feed"; cp "$dmg" "$feed/"
print -r -- "<p>${notes}</p>" > "$feed/Glimmer-$version.html"
"$sparkle/generate_appcast" --ed-key-file "$update_key" --download-url-prefix "$site_url/updates/" \
    --link "$site_url" --embed-release-notes -o "$feed/appcast.xml" "$feed"
grep -q "sparkle:version>$build<" "$feed/appcast.xml" && grep -q 'sparkle:edSignature=' "$feed/appcast.xml" ||
    { echo "The update feed is missing this build or its signature." >&2; exit 1; }

step "Stage the site files"
mkdir -p "$site/updates"
find "$site/updates" -name 'Glimmer-*.dmg' -delete
cp "$dmg" "$site/updates/"
cp "$feed/appcast.xml" "$site/updates/appcast.xml"
sha="$(shasum -a 256 "$dmg" | cut -d' ' -f1)"
# The site build reads latest.json, so the download page and buttons pick up this release when it deploys.
/usr/bin/python3 - "$site/updates/latest.json" "$version" "$build" "$sha" "$dmg" "$notes" <<'PY'
import json, os, sys, datetime
latest, version, build, sha, dmg, notes = sys.argv[1:]
json.dump({"version": version, "build": int(build), "file": f"/updates/{os.path.basename(dmg)}", "bytes": os.path.getsize(dmg),
           "sha256": sha, "released": datetime.date.today().isoformat(), "minimumSystem": "macOS 15", "notes": notes},
          open(latest, "w"), indent=2)
open(latest, "a").write("\n")
PY
sed -i '' -e "s/^MARKETING_VERSION = .*/MARKETING_VERSION = $version/" \
    -e "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $build/" "$config"

echo "\nGlimmer $version ($build) is signed, notarized and staged."
echo "Installer: $dmg"
echo "SHA-256:   $sha"

if (( ! publish )); then
    echo "Review landing/updates, then commit and push to main to publish (or rerun with --publish)."
    exit 0
fi

# --- Publish -----------------------------------------------------------------------
step "Publish to main"
git -C "$root" add landing/updates native/Glimmer.xcconfig
git -C "$root" commit -q -m "[glimmer] release Mac $version ($build)"
git -C "$root" push origin main

step "Wait for $site_url"
for attempt in {1..40}; do
    live_feed="$(curl -fsS "$site_url/updates/appcast.xml?build=$build" 2>/dev/null || true)"
    if grep -q "sparkle:version>$build<" <<< "$live_feed"; then
        live_sha="$(curl -fsSL "$site_url/updates/Glimmer-$version.dmg" | shasum -a 256 | cut -d' ' -f1)"
        [[ "$live_sha" == "$sha" ]] || { echo "The live download does not match the signed installer." >&2; exit 1; }
        echo "Live: $site_url/download offers Glimmer $version ($build), byte-identical to the signed installer."
        exit 0
    fi
    sleep 15
done
echo "The site did not serve build $build within 10 minutes. Check the Cloudflare Pages deployment (glimmer-site)." >&2
exit 1
