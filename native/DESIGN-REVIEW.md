# Glimmer native UI: design review and redesign (2026-11-14)

This records two passes. The first pass fixed structure but was still loud. The second pass, after Brad's feedback about blue buttons and overpowering UI, is what the app looks like now.

## What was wrong

### The original UI

1. Content cards, buttons and backgrounds all used the same pale translucent treatment, so nothing told you what you could touch.
2. Every screen was a stack of equally weighted cards. Today gave the check-in, stats, lesson, plan and settings links the same weight.
3. Mac and iPad stretched the iPhone column.
4. The primary action in each flow scrolled away, and Cancel, Back and Continue moved between steps.
5. Washed-out art, and a penguin mascot that is not approved.

### The first redesign pass

1. **Too much blue.** Every primary action was a full-width saturated blue bar. Selected segments, step bars, toolbar icons and several secondary buttons were blue as well.
2. **Oversized controls.** Rows were 60pt tall slabs with icon badges. Chips, check buttons and the action bar were all at the largest control size.
3. **Cards inside cards.** Glass rows sat inside bordered panels on a gradient page, so most screens had three nested outlines.
4. **Decoration without meaning.** Uppercase tracked labels sat above every section in five different colours. Four coloured statistics repeated numbers shown elsewhere on Today. Sidebar icons were five colours.
5. **Generic look.** Cream gradient, serif headlines everywhere and a placeholder mascot badge on four screens.

## The design now

**Paper for reading, glass for touching, and very little colour.**

- **Colour is kept for meaning.**
  - The main action on a screen is ink (near-black in light mode, warm white in dark mode). There is one per screen.
  - Every other button is neutral Liquid Glass with a primary-colour label.
  - Soft blue appears only for selection: a chosen chip or option, a toggle, the selected segment, and the aftertaste dial.
  - Sage and honey appear only for progress and for the held or slipped check-ins.
- **Type.** SF for the whole interface, in sentence case, with quiet grey section headings. New York serif is kept for the journal's own voice: the line of the day on Today and the word on the dial.
- **Surfaces.** A flat warm-grey page. Reading content (lessons, charts, summaries) sits on plain paper panels with a hairline and no shadow. Groups of rows sit directly on the page with a small heading, not inside another card.
- **Smaller controls.** Rows, chips and buttons are regular size. On Mac the action bar is a normal trailing button group. On iPhone the primary action is one thumb-width button.
- **Less on each screen.**
  - The repeated statistics strip on Today is gone.
  - Sidebar and row icons are monochrome.
  - The placeholder mascot mark is removed everywhere except About, where it is labelled as temporary in the code.
  - On Mac and iPad, Today no longer repeats the sidebar's links.
- **Layout per device.** Mac and iPad use a sidebar with two-column grids where the content suits it. iPhone uses a tab bar that minimizes on scroll, and focused flows hide it.

## Tactile pass (2026-11-24)

Brad's feedback on 1.1.2: checking off habits lost its animation, the Habits checklist was crowded and not inviting to tap, the mood row was "horrible UI, nobody wants buttons", and the app "starts feeling like a form". This pass keeps the paper, glass and ink rules above and adds one more.

**Things you touch answer like objects.** They give under a finger, settle with a small spring and confirm with a tap you can feel. The shared pieces are in `Tactile.swift` and `MoodSky.swift`.

- **One tick everywhere.** `Tick` replaces the mix of small circles, squares and trailing check symbols. It sits on the leading edge in a 44 point target (`TickButton`). Checking it fills the ring in sage with a spring, draws the check as a stroke and lets a ring of light leave it. Unchecking is quick and plain. Done lines dim instead of being struck through.
- **Feel.** `tickFeedback` plays a success tap on iPhone and iPad and a trackpad click on Mac (`NSHapticFeedbackManager`). Ticks that only include or select something use the lighter selection tap.
- **Habit stones.** Each habit is a round stone you press. Its rim is the last seven days, with today as the last arc. Pressing it lights today's arc, the icon hops and a ring leaves the stone. A full week turns the rim honey.
- **Mood sky.** Today's mood is a small sky. Drag or tap the sun along its path: rain thins to cloud, cloud parts and the light warms through Low, Off, Okay, Good and Great, with a tick at each stop. It saves when the sun lands. VoiceOver reads it as one adjustable control, and arrow keys move it on Mac. A vertical swipe that starts on the sky still scrolls the page.
- **The coin celebration is unchanged.** Row motion finishes in about 0.4 seconds, before `CoinBurst` and the earned-coins toast start, so the two never compete. Check-offs still go through `toggleTask`, `toggleHabit` and `setPersonalTodoDone`.
- **Fewer form controls.**
  - Plan drops the boxed progress card, the tracker picker (it stays in Settings), the "Show all scheduled tasks" switch and the outlined add buttons. Tasks are plain lines with the tick first. The praise line under the progress bar has its own place, so the list never moves under a finger.
  - New tasks and to-dos are written on the next line of the list, marked with a dashed tick.
  - Weigh it and Unload add lines the same way instead of with outlined buttons.
  - The energy dial sits straight on the page, and the line under it answers as the dial turns.
- **Calmer lists.** Rows are 44 points tall on iPhone and iPad, light softly under the finger and have quieter dividers. A row that ends in a tick shows selection with the tick alone, without a tinted fill.
- **Month.** Days are plain numbers until they are done, then sage stones. Today has a ring.
- **Reduce Motion.** Springs, hops, ripples, rain and the sun's glide are all dropped. Ticks and the sky change with a short fade, and the haptics stay.

## Screen and control coverage

Key for the 26+ column:

- **G** = custom Liquid Glass drawn with `glassEffect(.regular.interactive())`
- **GP** = `.buttonStyle(.glassProminent)` in ink
- **GC** = grouped with `GlassEffectContainer`
- **Sys** = a system control, which already gets Liquid Glass from the OS on 26+ and is not double-glassed

Before 26, custom glass falls back to `.regularMaterial` with a hairline border, or an opaque surface when Reduce Transparency is on. The prominent style falls back to `.borderedProminent`. This was checked on an iOS 18.5 simulator.

| Area | Controls | 26+ | Before 26 |
|---|---|---|---|
| Toolbar (Mac, iPad, iPhone) | Check in, Quick actions menu, Log a moment | Sys toolbar glass | toolbar buttons |
| Sidebar and tabs | Split-view sidebar, iPhone tab bar | Sys | Sys |
| Today | Check-in rows, lesson row, plan row | G rows (GC) | material rows |
| Onboarding (14 steps) | Back, option rows, name field, Continue / Start my plan | G icon button, G rows (blue tint when selected), GP in the pinned bar | material, borderedProminent |
| Log a moment | Source chips, Add, date picker, tag chips, dial, slider, decision picker, Cancel / Back / Continue / Save | G chips, G dial knob, Sys slider, date picker and segmented picker, G Cancel and Back, GP primary | material, borderedProminent |
| Energy check-in | Dial, slider, Cancel, Set today's energy | same as logging | same |
| Insights | Alignment, trend chart, input mix, platform disclosure, today's logs | Paper panels for reading, Sys disclosure | same |
| Weekly | Inputs, pattern, on-device reflection button, suggested experiments | G button, G rows | material |
| Coach | Start the review, Held / Slipped, Design it together, Keep watching, experiment rows, links | G buttons (GC for pairs), G rows | material |
| Experiment review | Outcome rows | G rows | material |
| Plan | Progress line, show-all link, task lines with a leading tick and edit, quick add line, New scheduled task, links | Tick, plain lines on a paper panel | same |
| Task editor | Name, emoji icons, date, repeat toggle, frequency, weekday chips, Cancel / Delete / Save | G icon circles and chips, Sys pickers and toggle, GP save | material, borderedProminent |
| Task library, Suggestions | Category rows, selectable suggestion rows, Add to my plan | G rows, GP | material |
| Habits | Today / Month picker, habit stones, mood sky, month navigation and day stones | G segmented, stones and sky drawn in SwiftUI, G icon buttons | same |
| Tiny wins | Start rows, steps, timer Start / Stop, feedback chips, primary action | G rows, G buttons and chips, GP | material |
| Lessons | Lesson rows, reader Previous / Next / Complete, reflection choices | G rows, G icon button, GP | material |
| Cleaning | Lists, rooms, session task rows | G rows | material |
| Settings | Name and Save name, tracker picker, backup and restore rows, Mac agent toggle and copy buttons | Sys field, picker and toggle, G buttons and rows | material |
| About, ratings and support | Link rows, share, Review (disabled with no App Store ID), free support, Done | G rows and buttons | material |
| Notices | Saved and award toast | G capsule | material capsule |
| Toolkit | Step size stones, tool rows in four short lists (Get started, Get it done, Say it, Decide) | G stones, G rows (GC) | material |
| Unload, Break it down, Time check | Brain-dump editor, editable suggestion rows with include checks and due chips, step editor with Try again and Undo, focus segments, estimate stepper, one ink primary | G rows and chips, Sys segmented and stepper, GP | material, borderedProminent |
| One thing | Full-screen cover on iPhone and iPad (sheet on Mac): to-do title, step dots, large next step, optional timer with stepper, More menu, Done | G icon button, Sys stepper, GP Done | material |
| Read the room, Reword, Weigh it | Direction segments, text editors, tone chips, result panels with Copy / Use this / Share, editable For, Against and Still unknown lists, Try it for 7 days | Sys segmented, G chips and buttons, GP | material |

### Accessibility

- **Reduce Transparency.** Custom glass becomes an opaque surface. System glass follows the OS setting.
- **Increase Contrast.** Panel borders get stronger, and labels use the semantic primary and secondary colours.
- **Reduce Motion.** The dial value animation is switched off, and onboarding uses a plain fade instead of a push transition.
- **VoiceOver.**
  - The dial is an adjustable element, and the slider is labelled.
  - Task checks are labelled "Complete <task>" or "Uncheck <task>".
  - Selected chips and rows carry the selected trait.
  - The accessibility identifiers used by the UI tests are unchanged.
- **Toolkit (2026-11-24).**
  - Step size is one adjustable element ("Step size", value "Balanced"); swipe up or down to change it. At accessibility text sizes the chosen size moves to its own line instead of hyphenating.
  - Every Toolkit result carries a combined source label ("Suggested on this device", "Suggested by your writing agent", "From Glimmer’s offline guide").
  - The One thing step is a header, the timer reads as minutes and seconds left, and step progress is spoken as "2 of 7 steps done". Reduce Motion drops the step change animation.
  - Tone chips that need a model are dimmed and disabled when none is available, with a footnote saying why.
  - The sheet Cancel button is an explicit xmark icon labelled Cancel, fixing a clipped glyph on iOS 26.
  - Creative director pass (Gemini Carbon, two rounds on real renders): tool pages hide the tab bar like other focused flows; row and list icons are monochrome; text fields sit straight on the panel's paper; Step size moved below the tools; Reword shows its result under the message, tones scroll in one row (offline tones first), and Copy is the main action once there is a result; Read the room's main action disappears once read and returns when the message changes; Weigh it lists use plain plus, minus and question marks with an "Add your own" button; the One thing card is full screen with sage progress and the timer unboxed.
- **Keyboard (Mac).** ⌘⇧E checks in, ⌘⇧L logs a moment, Return activates the primary action in a flow, and Escape cancels a sheet.

## What did not change

These are all unchanged:

- The journal model, persistence, backup and restore
- Recurrence, awards and unlocks
- The catalog, including the 50 lessons, 66 illustrations and editorial changes
- The rule-based coach and the optional on-device reflection
- MCP consent, revocation and data exclusions
- The review request after five logs, with no fake review link

No analytics, accounts or network calls were added, and the minimum OS versions are still macOS 15 and iOS 18.

## Debug-only review hooks

These only run in Debug builds, and only when `GLIMMER_TEST_JOURNAL` is set, so they never touch a real journal:

- `GLIMMER_SCREEN`
- `GLIMMER_FLOW`
- `GLIMMER_LOG_STEP`
- `GLIMMER_DETAIL`
- `GLIMMER_APPEARANCE`
- `GLIMMER_TOOLKIT_TEXT`, `GLIMMER_UNLOAD_TEXT`, `GLIMMER_TOOLKIT_AUTORUN` and `GLIMMER_TEST_TOOLKIT_MODEL` (Toolkit inputs; see README)
