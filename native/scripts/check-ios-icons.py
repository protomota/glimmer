#!/usr/bin/env python3
"""Verify both device icons in the signed IPA that will actually reach TestFlight."""
import json
import plistlib
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

with zipfile.ZipFile(sys.argv[1]) as ipa, tempfile.TemporaryDirectory() as tmp:
    bundle = "Payload/Glimmer.app/"
    info = plistlib.loads(ipa.read(bundle + "Info.plist"))
    if set(info["UIDeviceFamily"]) != {1, 2}:
        sys.exit("The IPA must support both iPhone and iPad.")
    for key in ("CFBundleIcons", "CFBundleIcons~ipad"):
        primary = info[key]["CFBundlePrimaryIcon"]
        if primary.get("CFBundleIconName") != "AppIcon" or not primary.get("CFBundleIconFiles"):
            sys.exit(f"The {key} entry has no installed AppIcon.")

    catalog = Path(tmp) / "Assets.car"
    catalog.write_bytes(ipa.read(bundle + "Assets.car"))
    raw = subprocess.check_output(["xcrun", "assetutil", "--info", str(catalog)])
    icons = {item.get("Idiom") for item in json.loads(raw)
             if item.get("Name") == "AppIcon" and item.get("AssetType") == "Icon Image"
             and item.get("PixelWidth") == 1024 and item.get("PixelHeight") == 1024
             and item.get("Opaque") is True}
    if not {"phone", "pad"}.issubset(icons):
        sys.exit(f"Missing opaque 1024px AppIcon for phone or pad. Found {sorted(icons)}.")
    print("Verified exported iPhone and iPad AppIcon artwork and Info.plist declarations.")
