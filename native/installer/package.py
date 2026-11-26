"""Package the signed Glimmer app in the shared Protomota Finder installer layout.

    python native/installer/package.py <Glimmer.app> <output.dmg>

The window background is the artwork inside the signed app (Contents/Resources/installer-background.tiff),
the same way Jotley and Inkspring do it, so the disk image shows only Glimmer and Applications.
Needs dmgbuild, ds-store and mac-alias (native/installer/requirements.txt). Signing and notarizing
the disk image are done by native/scripts/release-mac.sh.
"""

import argparse
import os
import subprocess
import tempfile
from pathlib import Path

from dmgbuild import build_dmg
from ds_store import DSStore
from mac_alias import Alias

ARTWORK = Path("Contents/Resources/installer-background.tiff")
WINDOW = ((160, 160), (720, 520))
ICON_SIZE = 104
LOCATIONS = {"Glimmer.app": (195, 230), "Applications": (525, 230)}


def package(app: Path, output: Path) -> None:
    mount: Path

    def remember_mount(mount_point: str, _options: dict) -> None:
        nonlocal mount
        mount = Path(mount_point)

    def write_background_alias(event: dict) -> None:
        if event.get("type") != "operation::finished" or event.get("operation") != "dsstore::create":
            return
        with DSStore.open(str(mount / ".DS_Store"), "r+") as store:
            icons = store["."]["icvp"]
            icons["backgroundType"] = 2
            icons["backgroundImageAlias"] = Alias.for_file(str(mount / app.name / ARTWORK)).to_bytes()
            store["."]["icvp"] = icons

    build_dmg(str(output), app.stem, settings={
        "format": "UDZO",
        "filesystem": "HFS+",
        "files": [str(app)],
        "symlinks": {"Applications": "/Applications"},
        "window_rect": WINDOW,
        "default_view": "icon-view",
        "show_toolbar": False,
        "show_sidebar": False,
        "show_status_bar": False,
        "show_pathbar": False,
        "show_tab_view": False,
        "arrange_by": None,
        "scroll_position": (0, 0),
        "icon_size": ICON_SIZE,
        "text_size": 15,
        "label_pos": "bottom",
        "icon_locations": LOCATIONS,
        "create_hook": remember_mount,
    }, callback=write_background_alias)


def verify(image: Path) -> None:
    """Check the layout in the finished image: two items, their positions, and the artwork reference."""
    # Finder metadata reads reliably only from a local mount point, even when builds run on an external drive.
    with tempfile.TemporaryDirectory(prefix="glimmer-dmg-check-", dir="/private/tmp") as temporary:
        mount = Path(temporary) / "volume"
        mount.mkdir()
        subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen", "-noverify",
                        "-mountpoint", str(mount), str(image)], check=True, stdout=subprocess.DEVNULL)
        try:
            names = {path.name for path in mount.iterdir()}
            assert names - {".DS_Store", ".fseventsd", ".Trashes"} == set(LOCATIONS), names
            assert os.readlink(mount / "Applications") == "/Applications"
            with DSStore.open(str(mount / ".DS_Store"), "r") as store:
                window, icons = store["."]["bwsp"], store["."]["icvp"]
                locations = {name: tuple(store[name]["Iloc"])[:2] for name in LOCATIONS}
            assert window["WindowBounds"] == "{{160, 160}, {720, 520}}", window["WindowBounds"]
            assert icons["iconSize"] == ICON_SIZE and icons["backgroundType"] == 2, icons
            assert locations == LOCATIONS, locations
            assert Alias.from_bytes(icons["backgroundImageAlias"]).target.filename == ARTWORK.name
            assert (mount / "Glimmer.app" / ARTWORK).is_file()
        finally:
            subprocess.run(["hdiutil", "detach", str(mount)], check=True, stdout=subprocess.DEVNULL)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("output", type=Path)
    arguments = parser.parse_args()
    if arguments.app.name != "Glimmer.app" or not (arguments.app / ARTWORK).is_file():
        parser.error("Use a Glimmer.app that contains the installer artwork (a Mac build of the current project).")
    if arguments.output.exists():
        parser.error("The output path already exists.")
    package(arguments.app, arguments.output)
    verify(arguments.output)
    print("Installer layout verified.")
