# Glimmer row icons

Every row, sidebar item and choice gets one solid, single-colour SF Symbol, tinted from the theme. Icons never use colour emoji, brand logos, two-tone rendering or drawn art. `Glimmer/Glyph.swift` resolves the symbol and draws the tile. `Glimmer/GlyphMap.swift` holds the map.

Emoji can still appear where they mean something: in lesson text and in anything a person types. Names a person types are kept exactly as typed. Built-in catalog names never show an emoji. The emoji becomes the row's symbol, so "💻 Deep work" shows as a laptop tile next to "Deep work".

## Rendering

- `Image(systemName:)` with `.symbolRenderingMode(.monochrome)` and one `foregroundStyle(tint)`. Never `.hierarchical`, `.palette` or `.multicolor`.
- Use the filled style: the `.fill` variant wherever one exists. Symbols with no fill variant are used as drawn.
- Weight is `.semibold` inside a tile and `.medium` for a plain glyph.
- Use SF Symbols only. Don't use symbols Apple restricts to its own products, such as `message.fill`, `video.fill`, `iphone` or `safari`.
- Icons are decoration. Each one sits beside its text label and is `accessibilityHidden(true)`.

## Tint by kind

| Kind | GlimmerColor |
|---|---|
| Source (apps, sites, feeds), task, to-do, cleaning, maintenance, tag | `accent` |
| Activity, habit | `sage` |
| Person, seasonal, practice | `ember` |
| Challenge, energy | `honey` |
| Lesson, toolkit | `dusk` |

Task library: easy `honey`, focus `accent`, move `sage`, offline `ember`, wind `dusk`, calm `dusk`.

`softBlue` is not an icon tint. Its light value fails 3:1 on a tile. Never tint an icon `.secondary`, grey or `Color.primary`.

## Containers and sizes

Content rows use a tile `GlyphTile`. It is the tint at 13% (20% in the Glimmer theme), with corner radius 28% of the tile, continuous. The glyph is 54% of the tile, stepping down to 44% for very wide symbols. A tile has no border, shadow or gradient.

Navigation (the sidebar and the tab bar) and chips use a plain tinted glyph with no tile.

| Place | Mac | iPhone and iPad |
|---|---|---|
| Sidebar row | 15pt medium glyph, 24pt slot | 20pt medium glyph, 29pt slot |
| Content row | 24pt tile | 30pt tile, scales with Dynamic Type |
| Header or empty state | 44pt tile | 48pt tile |

## Sidebar

| Destination | Symbol | Tint |
|---|---|---|
| Today | `sun.horizon.fill` | accent |
| Insights | `chart.bar.fill` | sage |
| Weekly | `calendar` | honey |
| Coach | `text.bubble.fill` | ember |
| Plan | `list.bullet.clipboard.fill` | accent |
| Toolkit | `wrench.and.screwdriver.fill` | dusk |
| Habits | `leaf.fill` | sage |
| Challenges | `trophy.fill` | honey |
| Lessons | `book.fill` | dusk |
| Cleaning | `bubbles.and.sparkles.fill` | accent |
| Seasonal | `tree.fill` | ember |
| Settings | `gearshape.fill` | dusk |

## Choosing a symbol

The first hit wins:

1. A stored SF Symbol name.
2. `GlyphMap.names`: sources, activities and people by plain name, case-insensitive.
3. `GlyphMap.emoji` for a stored or leading emoji. Keys drop U+FE0F and U+FE0E.
4. `GlyphMap.keywords`, in order, against the lowercased name. Guards come first, so "brunch" never matches "run".
5. `GlyphMap.categoryFallback` for the row's kind or category.
6. `GlyphMap.fallback` (`sparkles`).

A checklist item with no match wears its list's glyph.

The Glimmer logo is the `AppMark` asset only. Never draw it, tint it or substitute a symbol for it. Don't use the single `sparkle` symbol in honey as a row icon, because it reads as a copy of the mark.

## Checks

`native/scripts/core-checks.sh` checks the following:

- every built-in activity, person and lesson page resolves to a real symbol
- no catalog name shows an emoji
- built-in emoji names in older journals migrate without touching names a person typed
