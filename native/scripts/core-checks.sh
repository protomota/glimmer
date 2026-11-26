#!/bin/zsh
# Compiles and runs the core checks (recurrence, statistics, persistence, backup and journal merge).
set -euo pipefail
native="${0:A:h:h}"
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT
xcrun swiftc -parse-as-library "$native/Checks/CoreChecks.swift" \
    "$native"/Glimmer/{Catalog,Journal,JournalStore,JournalReplica,JournalCloud,ReflectionSummary,EarnedCoins,ReadingMotion,EditorialLibrary,GalleryCatalog,GalleryAmbience,Gallery,ReaderRanks,Design,AgentAccess,AgentSetup,AgentSkillInstaller,PersonalReminders,Toolkit,CoachPrompts,Tactile,Glyph,GlyphMap,SupportReminder,InkspringLink}.swift \
    -o "$build/core-checks"
"$build/core-checks" "$native" "$@"
