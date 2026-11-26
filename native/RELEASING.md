# Releasing Glimmer for Mac

One command builds, signs, notarizes and publishes the direct-download Mac app and its Sparkle update:

```sh
native/scripts/release-mac.sh 1.0.1 --notes "What changed" --publish
```

Run it from a clean `main`. It takes about ten minutes, most of it waiting for Apple's notarization.

## What the script does

1. Archives the Release build and exports it with the Protomota Developer ID certificate and the hardened runtime, with the iCloud entitlement when the provisioning profile is available.
2. Notarizes the app with Apple, staples the ticket and checks Gatekeeper.
3. Builds `Glimmer-<version>.dmg` in the shared Protomota installer layout (see “The installer window” below), checks the layout, signs it, notarizes it and staples it.
4. Signs the update with Glimmer's Sparkle key and writes `landing/updates/appcast.xml`.
5. Replaces the installer in `landing/updates/`, and writes `landing/updates/latest.json`. The site build reads that file, so the download page at https://glimmertoday.ai/download and the buttons show the new version, file and checksum when the site deploys.
6. Records the version and build number in `native/Glimmer.xcconfig`.
7. With `--publish`: commits as `[glimmer] release Mac <version> (<build>)`, pushes to `main`, waits for the Cloudflare Pages deploy, and confirms that the installer the download page offers is byte-identical to the signed one.

Without `--publish` it stops after step 6 so you can review the staged files. The build number goes up by one each release; pass `--build N` to choose it. Working files and logs go to `/Volumes/Expand/Projects/Glimmer/glimmer-release/<version>-<build>/` (set `GLIMMER_RELEASE_DIR` to use another folder).

Installed copies find the update through **Glimmer → Check for Updates…** and Sparkle's automatic checks. The feed is https://glimmertoday.ai/updates/appcast.xml.

## What it needs on the release Mac

- Xcode 27 and Python 3. The script makes a small Python environment for the installer tools (`native/installer/requirements.txt`) the first time it runs.
- The **Developer ID Application: Protomota, LLC (22HV69L32T)** certificate in the login Keychain.
- The **Glimmer Developer ID** provisioning profile, for iCloud sync. The script installs `native/signing/Glimmer_Developer_ID.provisionprofile` when it is checked in. Without the profile the release is still signed and notarized, but it is built with `Glimmer-Mac-Direct.entitlements` and leaves iCloud out: the app then reports that iCloud Drive is unavailable and keeps the journal on the Mac. To create the profile, open [Profiles](https://developer.apple.com/account/resources/profiles/add), choose **Developer ID**, then **Mac**, the App ID `com.protomota.glimmer` and the Protomota Developer ID certificate, name it **Glimmer Developer ID**, download it and save it at that path.
- An App Store Connect API key for notarization. The script reads `APP_STORE_CONNECT_API_KEY`, `APP_STORE_CONNECT_KEY_ID` and `APP_STORE_CONNECT_ISSUER_ID` from Bitwarden Secrets Manager, or uses `APPLE_API_KEY_PATH`, `APPLE_API_KEY_ID` and `APPLE_API_ISSUER` when they are set.
- Glimmer's Sparkle signing key. It is in the login Keychain under the account `com.protomota.glimmer`, created with Sparkle's `generate_keys`. The script exports it to a temporary file for signing and removes the file. Set `GLIMMER_SPARKLE_EDDSA_PRIVATE_KEY` to use a copy from a secret store. The public half is `GLIMMER_UPDATE_PUBLIC_KEY` in `Glimmer.xcconfig`. Never replace the key: installed copies only accept updates signed with it.

## The installer window

The disk image uses the same drag installer as Jotley, Inkspring, OpenTalon and PulseCanvas: a 720 x 520 window with Glimmer on the left, Applications on the right and an arrow between them.

- `native/installer/make-background.py` draws the artwork in Glimmer's colors and writes `native/Glimmer/installer-background.tiff` (1x and 2x). Run it only when the artwork changes, with the packaging Python, and commit the result. The arrow is drawn at four times the size and scaled down, which keeps its head smooth; drawing it at final size is what made it ragged.
- The TIFF ships inside the Mac app's resources (iOS builds leave it out), so the window points at signed artwork inside `Glimmer.app` and the disk image holds nothing but Glimmer and the Applications shortcut.
- `native/installer/package.py` builds the image with `dmgbuild`, then mounts it and checks the window size, icon positions and artwork reference.

## Releasing from GitHub Actions

`.github/workflows/mac-release.yml` runs the same script on a GitHub macOS runner. Start it from **Actions → Mac release → Run workflow** and enter the version. It needs these repository secrets:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | The Developer ID certificate and private key, exported as `.p12` and base64 encoded |
| `DEVELOPER_ID_P12_PASSWORD` | The password chosen for that export |
| `APPLE_API_KEY` | Contents of the App Store Connect `.p8` key |
| `APPLE_API_KEY_ID` | Its key ID |
| `APPLE_API_ISSUER` | Its issuer ID |
| `GLIMMER_SPARKLE_EDDSA_PRIVATE_KEY` | The Sparkle private key, from `generate_keys --account com.protomota.glimmer -x <file>` |

Check the provisioning profile in at `native/signing/Glimmer_Developer_ID.provisionprofile` for releases with iCloud sync.

## iPhone and iPad (TestFlight)

```sh
native/scripts/release-ios.sh
```

The script archives the app with the **Apple Distribution: Protomota, LLC** certificate and the **Glimmer App Store 2** provisioning profile, uploads it to App Store Connect, waits for Apple to finish processing, and makes sure the build is in the internal tester group **Glimmer Internal**. It uses the version in `Glimmer.xcconfig` and the next free build number (`--build N` to choose).

- The app record is **Glimmer: Gentle Life Coach** (Apple ID `6837750690`, bundle ID `com.protomota.glimmer`, SKU `GLIMMER`). The plain name “Glimmer” was already taken on the App Store; the home-screen name is still Glimmer.
- Uploads use the team's App Store Connect upload key from Bitwarden Secrets Manager (`INKSPRING_ASC_UPLOAD_KEY_ID`, `_ISSUER_ID`, `_PRIVATE_KEY`, the same credential Jotley's release script uses). Set `GLIMMER_ASC_SECRET_PREFIX` to use another. The general `APP_STORE_CONNECT_API_KEY` can notarize but is not allowed to upload builds.
- The App Store profile lives at `native/signing/Glimmer_App_Store.mobileprovision` (not in Git, because `*.mobileprovision` is ignored) and is installed into Xcode's profile folder by the script. It expires with the distribution certificate on October 11, 2027. Create a new one under [Profiles](https://developer.apple.com/account/resources/profiles/add): **App Store Connect**, App ID `com.protomota.glimmer`, the Protomota distribution certificate, named **Glimmer App Store 2**.
- Add or remove testers in [App Store Connect](https://appstoreconnect.apple.com/apps/6837750690/testflight/ios) under **TestFlight → Internal Testing → Glimmer Internal**. Adding internal testers through the API is refused, so do it there.
- A new tester gets one invitation email from TestFlight and has to tap **View in TestFlight** in it. Until they accept, Apple sends them no build notifications, and the script says so at the end of each run. To send the invitation again, open the tester in App Store Connect and choose **Resend Invite**.

## Checks

`.github/workflows/native-checks.yml` runs on every push to `main` that touches `native/`. It runs `native/scripts/core-checks.sh` and builds the app for Mac and for iPhone and iPad.

## Notes

- `--mcp` agent access (MCP) and iCloud sync behave the same in the direct-download build. App Store ratings need an App Store build and stay unavailable here.
- Debug builds never start the updater.

## Publish a gallery update

Glimmer fetches its gallery from <https://media.protomota.com/glimmer/gallery/gallery.json>. This is a public catalog in the existing `protomota-media` R2 bucket. The app can open with its bundled poster catalog offline. Gallery releases can ship independently of an app release. Keep previously distributed files available for older cached catalogs.

1. Create a Python 3.10+ virtual environment for release tools and install `boto3>=1.40,<2`. Put FFmpeg’s `ffprobe` on the executable path. Set `GLIMMER_R2_ENDPOINT` to the team's S3-compatible R2 endpoint. Supply the bucket's authorized object read/write credentials using the standard `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` environment variables from the secrets manager. Keep them out of source and catalogs.
2. Run `python native/scripts/publish-gallery.py --status` and save the output, including the quotation marks around an existing ETag. Fetch the current public index and edit that snapshot. For the very first publication the status is `absent`.
3. Prepare reviewed horizontal MP4s and matching JPEG posters. Name each file `v1/<scene>-<first 16 or more hex characters of that file’s SHA-256>.<ext>` beneath a local staging directory. Keep IDs stable across revisions. Put all plates in the desired order under `{"schemaVersion":1,"plates":[...]}`. Each plate has `id`, `description` and `aspectRatio` (display width divided by height). Include `video` and `poster` relative paths for each film. Reference remote stills with `poster`; an unchanged bundled still may omit that path. Set `wholeSubject` for crops where a person or animal should stay fully visible.
4. Run the publisher with the observed ETag. It uploads new media first, verifies hashes, MIME types and byte-range video delivery, then switches the index using an atomic conditional write. For previously published hashed files the publisher verifies the public copies when they are absent locally.

```sh
python native/scripts/publish-gallery.py --manifest ./gallery.json --assets ./gallery-staging --expected-etag "$observed_etag"
```

To stage media for creative review, include `--stage-assets` on the same command. It leaves the index untouched. Run the command again without that flag when the catalog is approved.

The catalog uses a 60-second cache with revalidation. Immutable media uses a one-year cache. A concurrent index change stops publication and preserves the other publisher’s work. Fetch the new snapshot, merge it, review the result and retry with its ETag. Roll back by publishing the previous catalog bytes against the current ETag. Never recycle a filename for changed media.


## Publish coaching content without an app update

Glimmer 1.0.18 and later fetch [the public R2 library](https://media.protomota.com/glimmer/content/library-v1.json) on launch and while active, at most once every 15 minutes. It has schemaVersion 1, a `content` object matching `LibraryContent/Catalog.json`, and a `gallery` object matching the gallery index. The same file carries all lessons, coaching practices, onboarding questions, challenges, routines, and the paths for gallery images, video and audio. The media themselves stay in immutable R2 objects, so downloading the catalog does not download the videos. App controls and layout still ship in the native apps.

1. Edit the lesson seed in `supabase/seed_lessons.sql`, the coaching and takeaway source in `native/LibraryContent/Editorial.json` (`lessonEdits` rewrites lessons in place by number, keeping page kinds and option counts; `extraLessons` appends lessons after 90; `challenges` adds challenges after the original four; practices and challenges take a `level` from 1 to 5 for the journey stages), or the shared onboarding and routine copy in `src/data.ts`. Regenerate the offline copy with `node native/Checks/make-catalog.mjs`, then run `native/scripts/core-checks.sh`.
2. Read the live library and its ETag using the existing R2 configuration and `python native/scripts/publish-gallery.py --content --status`. Preserve independent media and content edits already in that library. Put the updated content and gallery in one JSON file. For example, `jq -n --slurpfile content native/LibraryContent/Catalog.json --slurpfile gallery ./gallery.json '{schemaVersion:1,content:$content[0],gallery:$gallery[0]}' > library-v1.json`. Use the latest gallery and retain the previously published edition for rollback.
3. Publish with `python native/scripts/publish-gallery.py --content --manifest ./library-v1.json --assets ./gallery-staging --expected-etag "$observed_etag"`. The same tool stages and verifies gallery media before switching the index, and refuses to overwrite a changed ETag. The separate gallery URL is for builds through 1.0.17. When publishing a new gallery, update both indexes while those builds are in use.
4. Verify a refresh in an existing install and reopen it offline. Keep lesson slugs, numbers, existing page positions and option counts stable. A journal remembers answers by their original text. Revise a choice only when needed. Previously saved text stays in the journal, and a rewritten choice requires a fresh selection. Builds through 1.0.18 require exact choice text and fall back to their last compatible edition. Preserve onboarding option IDs and the IDs for practices, challenges, cleaning, and habits. New lessons go at the end. Roll back by restoring the old wording under the same IDs, preserving any lessons added since that revision.

The app caches only a validated edition and keeps its bundled edition for a first launch without a connection. The Mac MCP session uses the most recent local edition as of session start. This public catalog contains no journal entries, account details, or secrets. Cloudflare usage and catalog changes are independent of iCloud journal sync.

The same library holds `content.seasonal` and `content.quotes`, with bundled source data in `LibraryContent/Editorial.json`. For a Seasonal edition, keep existing edition, checklist, and item IDs stable, and use IDs from `content.cleaning.maintenance` for shared upkeep. The Today feature window uses inclusive local calendar dates in `MM-DD` format. For a new daily quote, verify the words and attribution against the original text and append an object with `id`, `text`, and `author`. Keep research links in the editorial verification records. The app reads the quote array in order, so use stable IDs and append to the end. Both sections work from the bundled data until a compatible R2 update is available.

When the author of a daily quote cannot be verified, write an original Glimmer line that carries the idea and set `author` to `Glimmer`. Record the inspiration in the editorial verification notes. Reserve the Glimmer credit for original wording.

### Mac Coach connection

Coach uses Apple Intelligence on supported devices. On Mac, Settings → Coach chooses who replies: On this device, Claude Code, Codex, Gemini CLI (Antigravity `agy`) or a Local MCP server, with model chips, reasoning effort, a time limit and Test Coach. The CLIs run sandboxed with the real home folder, an empty MCP config and Glimmer-only instructions; `Glimmer --test-coach claude|codex|gemini [model] [effort]` checks one from Terminal. Coach diagnostics in Settings can be shared without journal content. The Local MCP server address must use `http://127.0.0.1:<port>/<path>` and the bearer token is saved in Keychain. The server should bind exclusively to loopback and require the token.

Expose an MCP tool named `coach_respond`. It receives `instructions` and `prompt` as strings and responds with `structuredContent` containing an `answer` string and an optional `recommendation` string. Use an exact recommendation key from the prompt. Glimmer validates it against the current editorial choices before presenting any action. Coach sends the submitted question, recent turns from that connection and public guidance. It does not send journal records or on-device statistics. The existing Glimmer MCP server under Agent access continues to serve external clients separately.

> **Public repository note:** signing profiles, release credentials and the GitHub release workflows are not included here. To ship your own build, use your own Apple Developer team, bundle identifiers and iCloud container.
