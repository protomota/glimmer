# Glimmer for Mac, iPhone and iPad

Glimmer is a gentle, private spiritual life coach for Mac, iPhone, and iPad, made for deep thinkers, neurodivergent minds, and anyone too busy thinking to stay organized. It is built around small, practical experiments. Log short moments on your own device, try one concrete change at a time, and review your week to see what genuinely helped. Glimmer respects rest and keeps every decision in your hands.

Open `Glimmer.xcodeproj`, select the **Glimmer** scheme, and choose My Mac, an iPhone, or an iPad. This is one native SwiftUI target (macOS 15 and iOS/iPadOS 18 or later). On iPhone it uses tabs; Mac and regular-width iPad use a sidebar.

The native app includes onboarding, check-ins and the aftertaste dial, Today, recurring plans and the task library, habits and mood, guided Tiny Wins and timers, cleaning lists, coaching and experiment review, insights, and weekly summaries. A 120-lesson reading plan opens one lesson per day and deepens as it goes: lessons 91–120 form the Deep Path (watching the mind, stillness, impermanence and grief, conscience, quiet service, a practice of your own). Five reader ranks reflect distinct days of personal practice, with the first 90 lessons also required for Guru. Each rank also sets Glimmer's journey stage (1–5 at 0, 14, 30, 60 and 90 active days): challenges and practices carry a `level`, and the Daily Glimmer, the next challenge and coach suggestions favor the current stage. Everything stays open to browse and start, and a low or empty energy check that day brings suggestions back to stage 2 or below (`Journal.guidanceLevel`). All 66 original lesson and challenge illustrations are bundled. Navigation and controls use Liquid Glass on macOS, iOS, and iPadOS 26 or later, with system materials on earlier versions.

Glimmer saves its journal locally and works offline. Settings exports and restores a versioned JSON backup. Importing replaces the current journal after a preview and confirmation and syncs those changes when enabled. Insights use the user's actual logs. The optional Apple Intelligence reflection uses Apple's on-device model on supported devices. The rule-based coach also works offline.

## Personal to-dos and reminders

Use **Plan → Personal to-dos → Add to-do** for your own one-off tasks. You can set a due date, set a reminder time, or leave both blank. Unfinished tasks due today or earlier appear in **Today**. You can edit or complete a task from either view and reopen it under **Completed** in Plan. Personal to-dos have their own completion state and do not affect coaching progress or coins.

Glimmer schedules reminders using the device’s notification permissions. A scheduled alert works while the app is closed. With iCloud sync enabled, the task and reminder time sync between devices. Open Glimmer on each device where you want alerts and enable its notifications there. Changes made by a Mac agent or on another device are scheduled or canceled when Glimmer reads them on the receiving device.

Mac agents with **Settings → Agent access → Let agents log and check off** can call `list_personal_todos`, `add_personal_todo`, `set_personal_todo_done` and `set_todo_steps`. For a date, pass `due_day` as `YYYY-MM-DD`. For a requested reminder, pass `reminder_at` as an ISO 8601 timestamp with a time zone. Reuse a client-generated `request_id` UUID for retries. `add_personal_todo` also takes optional `steps` (up to 12 short titles) and `estimate_minutes` (1–1440). `set_todo_steps` replaces a to-do's steps, or the smaller steps under one top-level step with `parent_step_id`; steps with unchanged titles keep their `step_id` and done state. `list_personal_todos` returns each to-do's steps (two levels) and estimate. The existing coaching plan tools remain available.

## Toolkit

**Toolkit** (sidebar on Mac and iPad, Plan on iPhone) holds small helpers for busy minds: **Unload** sorts a brain dump into to-dos, **Break it down** turns a to-do into steps with one more level of smaller steps, **Time check** estimates a to-do adjusted for today's energy check-in, **One thing** shows only the next step with a gentle timer, **Read the room** describes how a message may come across, **Reword** rewrites a message in seven tones, and **Weigh it** lays out a decision and suggests a 7-day experiment. One **Step size** control (Big strides to Tiny steps) sets how fine-grained Break it down and Unload get and how much Reword changes.

Steps (`todoSteps`) and estimates (`todoEstimates`) are their own synced records keyed by to-do ID, kept in a sibling section of the replica so older versions of Glimmer leave them untouched. They back up and restore with the journal. Code: `Toolkit.swift` (models and the offline guide), `ToolkitAI.swift` (routing), and one view file per tool.

Each result is labeled with where it came from:

1. **Mac with a Coach agent**: Glimmer asks the agent chosen in Settings → Coach (Claude Code, Codex, Gemini CLI or a Local MCP server's optional `toolkit_respond` tool). Only the text typed into that tool is sent, never the journal.
2. **Apple Intelligence** (`FoundationModels`, guided generation) on iPhone, iPad and Mac when available, and as the Mac fallback.
3. **Glimmer's offline guide**: rule-based steps, to-do sorting, estimates, a word-pattern tone read, Shorter and Bullet points rewording, and a blank Weigh it form.

`toolkit_respond` receives `{tool, instructions, prompt, input}` and returns `structuredContent` shaped for the tool:

| `tool` | `input` | `structuredContent` |
| --- | --- | --- |
| `break_it_down` | `todo`, `step` (or null), `step_size` 1–5 | `{"steps": ["Open the doc", …]}` |
| `unload` | `text`, `today` (YYYY-MM-DD) | `{"items": [{"title": "Call the dentist", "due_day": "2026-11-27"}]}` |
| `time_check` | `todo`, `steps`, `focus` (scattered, steady, clear) | `{"minutes": 25}` |
| `read_the_room` | `text`, `direction` (received or sending) | `{"tones": [{"tone": "Urgent", "why": "…"}], "takeaway": "…"}` |
| `reword` | `text`, `tone`, `strength` 1–5 | `{"text": "…"}` |
| `weigh_it` | `decision` | `{"pros": […], "cons": […], "unknowns": […], "experiment": "…"}` |

Glimmer trims, deduplicates and caps whatever comes back, and falls back to Apple Intelligence or the offline guide if the call fails. Debug review launches: `GLIMMER_DETAIL` = `toolkit`, `unload`, `breakitdown`, `timecheck`, `onething`, `readtheroom`, `reword`, `weighit`, or the sheets `breaksheet`, `timesheet`, `focussheet`, `todoeditor`; `GLIMMER_TOOLKIT_TEXT` prefills a text tool (`|` is a new line), `GLIMMER_TOOLKIT_AUTORUN=1` runs it, and `GLIMMER_TEST_TOOLKIT_MODEL=1` allows Apple Intelligence in a test journal.

## iCloud Sync

Turn on **Sync with iCloud** during setup or in **Settings → iCloud Sync** on each device. Use the same Apple Account with iCloud Drive enabled. The app uses the private iCloud Documents container `iCloud.com.protomota.glimmer`. Sync covers the journal, plan, check-ins, habits, lessons, challenges, cleaning, experiments, rewards and journal preferences. Changes to different records merge. Concurrent edits to the same record or check-in resolve deterministically. Store review eligibility and Mac agent access are per device.

For signed builds on iPhone, iPad and Mac, the universal App ID `com.protomota.glimmer` must have iCloud Documents enabled and the Glimmer container assigned. Use development provisioning profiles with the corresponding iCloud entitlements. For a signed Mac Debug build, set `GLIMMER_MAC_ENTITLEMENTS=Glimmer/Glimmer.entitlements`. Local Mac Debug and simulator builds continue to work without iCloud provisioning.

To verify a signed build, turn on sync on all three devices. Log a moment and check a plan task on iPhone, change a habit on iPad, and open Insights and Plan on Mac to verify the results. Disconnect one device, make independent edits on two devices, reconnect, and confirm the changes and an undone check reach all three after a relaunch.

### Apple setup for live testing

1. Open [Apple Developer Identifiers](https://developer.apple.com/account/resources/identifiers/list) under Protomota, LLC. Click **+ → iCloud Containers → Continue**. Enter **Glimmer** as the description and `iCloud.com.protomota.glimmer` as the identifier. Click **Continue → Register**.
2. Open the [Glimmer App ID](https://developer.apple.com/account/resources/identifiers/bundleId/edit/4TYAD66X5K). Enable **iCloud**, click **Edit** in that capability, select the Glimmer container, and save.
3. In [App Store Connect Apps](https://appstoreconnect.apple.com/apps), click **+ → New App**. Select **iOS** and **macOS**, enter **Glimmer**, select **English (U.S.)** and the registered bundle ID, and use `GLIMMER` as the SKU. Use the same team access as the other Protomota apps. Click **Create** to save the draft record.
4. Connect and unlock the iPhone and iPad. Confirm that both devices and the Mac use the same Apple Account with iCloud Drive enabled. Use the development team and the signed builds from the preceding section for the transfer test.

## Mac download and updates

The Mac app is also distributed from https://glimmertoday.ai as a Developer ID signed, notarized installer. That build updates itself with Sparkle through **Glimmer → Check for Updates…**. One command builds, signs, notarizes and publishes a release: see [RELEASING.md](RELEASING.md). Debug builds leave the updater off.

## Agent access on Mac (MCP)

Glimmer's MCP server is the app executable started with `--mcp` (`AgentAccess.swift`). It reads and writes the journal file directly, so the app does not need to be open, and the running app reloads the journal when an agent saves to it. Settings → **Agent access** has two switches:

- **Share read-only summaries**: `get_attention_summary` and `get_plan_summary`. Grouped ratings and today's counts only. No journal entries, source names, task titles or onboarding answers.
- **Let agents log and check off**: adds `get_today` (today's tasks with names and IDs), `log_moment`, `add_plan_task` (a one-time task for today or tomorrow), `set_task_done`, `record_energy`, `check_in_experiment`, and the personal to-do tools `list_personal_todos`, `add_personal_todo`, `set_personal_todo_done` and `set_todo_steps`.

Setup lives in the same panel (`AgentSetup.swift`), Claude Code first:

- **Claude Code**: **Save Project Connection…** adds a `glimmer` STDIO entry to `.mcp.json` in a folder the user picks and keeps other servers. The plugin `protomota-glimmer-mcp` in [protomota/mcp](https://github.com/protomota/mcp) does the same with a bundled skill.
- **Codex**: Settings → MCP servers → Add server → STDIO, with the command (`/Applications/Glimmer.app/Contents/MacOS/Glimmer`) and the argument `--mcp`.
- **Claude chat**: **Save Claude Extension…** writes `Glimmer.mcpb`, a small Node wrapper that starts the same server.

**Test Connection** starts this copy of Glimmer the way an agent does and lists its tools. The panel shows the last agent and request, from `AgentActivity.json` next to the journal. `native/scripts/core-checks.sh` covers permissions, every tool, the app picking up agent changes and the `.mcp.json` merge. Public setup steps: https://glimmertoday.ai/mcp

## Ratings and support

Settings and the Mac About window share the rating, free technical support, sharing, feedback and More Free Apps links. Glimmer has no purchases: every feature is free and support tickets on protomota.com cost nothing. Feedback opens the same Protomota form used by Jotley and OpenTalon. After five successful local moment logs in an App Store-configured build, Glimmer makes one native review request when Today is idle, unless the user already opened the manual review link. Apple controls whether its prompt appears.

On Mac, after five logged moments, Glimmer shows a support card (feedback, share, free support, more apps) at most once a week. **Later** hides it for a week; **Don’t show again** turns it off for good (`glimmer.community.supportDismissed`). Settings → Ratings & support still opens the card on request. The iPhone and iPad apps show no prompt of their own.

For distribution, sign `com.protomota.glimmer` with the production team and set `GLIMMER_APP_STORE_ID` to the numeric Apple ID from the App Store Connect record. The manual review link is disabled without an Apple ID.

## Checks

Run the Glimmer scheme's UI tests on each platform. The test runner uses isolated journals. The core checks in `Checks/CoreChecks.swift` cover recurrence, statistics, duplicate awards, unlocks, persistence, backup, and a three-device journal merge over coordinated local files. Compile them with `Catalog.swift`, `Journal.swift`, `JournalStore.swift`, `JournalReplica.swift`, `JournalCloud.swift`, `ReflectionSummary.swift`, `Design.swift`, and `AgentAccess.swift`, then pass the absolute path to this `native` directory.

The offline catalog can be regenerated with Node 22.18+ using `node native/Checks/make-catalog.mjs` from the repo root. The native gallery rotates by local calendar day. Today features a motion scene and most other artwork is still. The app discovers scenes from `https://media.protomota.com/glimmer/gallery/gallery.json` on active use, conditionally refreshing after six hours. A validated atomic snapshot and bundled posters support offline use. To add a new scene, publish its immutable JPEG poster and optional silent fast-start H.264 MP4 beneath the same gallery path. An optional lossless ALAC file in an M4A container supplies the scene’s ambient sound. The app starts sound on request, downloads that file separately, and loops its decoded samples independently of the video. Upload the track and poster with content-hashed filenames, then add the new plate to the remote index. Keep existing entries and set `schemaVersion` to 1, with ordered `plates` containing a unique `id`, `description`, actual numeric `aspectRatio`, relative `poster` and optional `video` and `ambience` filenames, and optional `wholeSubject`. Existing bundled stills can omit the poster path. A downloaded poster is cached on the device. Reduce Motion, offline playback and small thumbnails use stills. Run `native/scripts/core-checks.sh` to verify gallery behavior.

Native lesson takeaways and coach experiments are maintained in `LibraryContent/Editorial.json`; the catalog generator applies these updates after importing the original curriculum. The recurring theme is deliberate attention: curate around genuine interests, mute or block repeat rage bait, and make room for enjoyable or restorative alternatives to endless feeds. See `../WEBSITE-AND-EDITORIAL.md` for the website and content direction.

The native motion design takes inspiration from [BorderBeam](https://github.com/ismnoiet/border-beam-ios) for a finite completion stroke and [ThinkingOrbs](https://github.com/haplollc/ThinkingOrbs) for depth cues during on-device generation. Glimmer implements both in SwiftUI and supports Reduce Motion.
