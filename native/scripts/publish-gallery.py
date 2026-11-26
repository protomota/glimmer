#!/usr/bin/env python3
"""Publish reviewed Glimmer posters and films to R2, then atomically switch the public catalog."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

BUCKET = "protomota-media"
PREFIX = "glimmer/gallery/"
INDEX = "gallery.json"
CONTENT = "glimmer/content/library-v1.json"
BASE = "https://media.protomota.com/"
MEDIA_CACHE = "public, max-age=31536000, immutable"
INDEX_CACHE = "public, max-age=60, must-revalidate"
BUNDLED = Path(__file__).resolve().parents[1] / "LibraryContent" / "Gallery"
ASSET = re.compile(r"v1/[a-z0-9][a-z0-9-]*-([0-9a-f]{16,64})\.(jpg|jpeg|mp4|m4a)")
TYPES = {"jpg": "image/jpeg", "jpeg": "image/jpeg", "mp4": "video/mp4", "m4a": "audio/mp4"}


def validate(data: bytes) -> set[str]:
    doc = json.loads(data)
    if len(data) > 1024 * 1024 or doc.get("schemaVersion") != 1 or not isinstance(doc.get("plates"), list) or not doc["plates"]:
        raise ValueError("Expected a nonempty, schemaVersion 1 gallery catalog under 1 MB")
    ids, assets = set(), set()
    for item in doc["plates"]:
        name = item["id"]
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", name) or name in ids:
            raise ValueError(f"Duplicate or invalid plate ID: {name!r}")
        ids.add(name)
        if not item.get("description", "").strip() or not math.isfinite(item["aspectRatio"]) or item["aspectRatio"] <= 0:
            raise ValueError(f"{name}: missing accessible description or valid aspect ratio")
        if "wholeSubject" in item and type(item["wholeSubject"]) is not bool:
            raise ValueError(f"{name}: wholeSubject must be a boolean")
        if not item.get("poster") and (item.get("video") or not (BUNDLED / (name + ".jpg")).is_file()):
            raise ValueError(f"{name}: supply a versioned poster for every film and new plate")
        for field, extensions in (("video", {"mp4"}), ("poster", {"jpg", "jpeg"}), ("ambience", {"m4a"})):
            if field not in item:
                continue
            match = ASSET.fullmatch(item[field])
            if not match or match.group(2) not in extensions:
                raise ValueError(f"{name}: invalid {field} path; use v1/name-<sha256-prefix>.<ext>")
            assets.add(item[field])
    return assets


def check_film(path: Path) -> None:
    """Reject a mislabeled file before it can enter an immutable release."""
    output = subprocess.check_output([
        "ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
        "stream=width,height,codec_name:stream_side_data=rotation:format=duration", "-of", "json", str(path),
    ])
    info = json.loads(output)
    streams = info.get("streams", [])
    if not streams:
        raise ValueError(f"{path.name}: no video track")
    stream = streams[0]
    width, height = stream["width"], stream["height"]
    rotation = next((row["rotation"] for row in stream.get("side_data_list", []) if "rotation" in row), 0)
    if int(rotation) % 180:
        width, height = height, width
    if width <= height or float(info["format"]["duration"]) <= 0:
        raise ValueError(f"{path.name}: film must have a landscape display frame and a positive duration")


def public_check(path: str, expected: str, size: int | None = None, fresh: bool = False, prefix: str = PREFIX) -> None:
    """Confirm the public CDN bytes before exposing the index. Old referenced files can be verified by hash alone."""
    url = BASE + prefix + path
    # A never-before-published index or an update may have a cached predecessor.
    if fresh:
        url += "?revision=" + expected
    is_video = path.endswith(".mp4")
    if is_video:
        with urlopen(Request(url, headers={"Range": "bytes=0-1", "User-Agent": "Glimmer-Gallery-Publisher/1"}), timeout=30) as response:
            if response.status != 206 or not re.fullmatch(r"bytes 0-1/\d+", response.headers.get("Content-Range", "")) or len(response.read(2)) != 2:
                raise ValueError(f"{path}: CDN does not support a byte-range request")
    with urlopen(Request(url, headers={"User-Agent": "Glimmer-Gallery-Publisher/1"}), timeout=90) as response:
        if response.geturl() != url:
            raise ValueError(f"{path}: unexpected redirect")
        is_index = path.endswith(".json")
        wanted = "application/json" if is_index else TYPES[path.rsplit(".", 1)[1]]
        etag = response.headers.get("ETag")
        if response.headers.get_content_type() != wanted or not etag:
            raise ValueError(f"{path}: unexpected MIME type or missing ETag")
        cache = {directive.strip().lower() for directive in response.headers.get("Cache-Control", "").split(",")}
        required = (INDEX_CACHE if is_index else MEDIA_CACHE).split(", ")
        if not set(required) <= cache:
            raise ValueError(f"{path}: unexpected cache policy {sorted(cache)}")
        digest = hashlib.sha256()
        count = 0
        while chunk := response.read(128 * 1024):
            count += len(chunk)
            digest.update(chunk)
        if not digest.hexdigest().startswith(expected) or (size is not None and size != count):
            raise ValueError(f"{path}: public content digest or size mismatch")
    try:
        with urlopen(Request(url, method="HEAD", headers={"If-None-Match": etag, "User-Agent": "Glimmer-Gallery-Publisher/1"}), timeout=30) as result:
            raise ValueError(f"{path}: If-None-Match unexpectedly returned {result.status}")
    except HTTPError as err:
        if err.code != 304:
            raise
        err.close()


def code(err: ClientError) -> int:
    return int(err.response["ResponseMetadata"]["HTTPStatusCode"])


def current(s3: object, key: str = PREFIX + INDEX) -> str:
    try:
        return s3.head_object(Bucket=BUCKET, Key=key)["ETag"]
    except ClientError as err:
        if code(err) == 404:
            return "absent"
        raise


def main() -> None:
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument("--content", action="store_true", help="Publish the unified editorial library, with the supplied gallery indexed inside")
    args.add_argument("--status", action="store_true", help="Print the current quoted ETag or absent")
    args.add_argument("--stage-assets", action="store_true", help="Upload and verify only immutable assets, leaving the public catalog unchanged")
    args.add_argument("--manifest", type=Path)
    args.add_argument("--assets", type=Path, help="Directory containing the v1/ folder")
    args.add_argument("--expected-etag", help="ETag you observed before preparing this revision, or absent for first publication")
    opts = args.parse_args()
    endpoint = os.environ["GLIMMER_R2_ENDPOINT"].rstrip("/")
    if not re.fullmatch(r"https://[0-9a-f]{32}\.r2\.cloudflarestorage\.com", endpoint):
        raise ValueError("Set GLIMMER_R2_ENDPOINT to the existing R2 account endpoint")
    s3 = boto3.client("s3", endpoint_url=endpoint, region_name="auto", config=Config(signature_version="s3v4", s3={"addressing_style": "path"}, request_checksum_calculation="when_required"))
    target = CONTENT if opts.content else PREFIX + INDEX
    observed = current(s3, target)
    if opts.status:
        print(observed)
        return
    if not opts.manifest or not opts.assets or not opts.expected_etag:
        args.error("Publishing requires --manifest, --assets and --expected-etag")
    if opts.expected_etag != observed:
        raise ValueError("Catalog changed. Read the latest index and merge your changes before publishing.")
    data = opts.manifest.read_bytes()
    if opts.content:
        edition = json.loads(data)
        library = edition["content"]
        bundled = json.loads((BUNDLED.parent / "Catalog.json").read_bytes())
        lessons = library["lessons"]
        if (edition.get("schemaVersion") != 1 or len(data) > 2 * 1024 * 1024
                or set(library) - {"seasonal", "quotes"} != set(bundled) - {"seasonal", "quotes"}
                or len(lessons) < len(bundled["lessons"])
                or [item["number"] for item in lessons] != list(range(1, len(lessons) + 1))
                or len({item["slug"] for item in lessons}) != len(lessons)
                or any(old["slug"] != new["slug"] or [p["kind"] for p in old["pages"]] != [p["kind"] for p in new["pages"]]
                       for old, new in zip(bundled["lessons"], lessons))):
            raise ValueError("The edition is incompatible with the bundled library")
        paths = validate(json.dumps(edition["gallery"]).encode())
    else:
        paths = validate(data)
    delayed: list[tuple[str, str, int]] = []
    for path in sorted(paths):
        local = opts.assets / path
        prefix = ASSET.fullmatch(path).group(1)
        if local.is_file():
            if local.suffix == ".mp4":
                check_film(local)
            body = local.read_bytes()
            sha = hashlib.sha256(body).hexdigest()
            if not sha.startswith(prefix):
                raise ValueError(f"{path}: local bytes do not match the hash in the filename")
            try:
                s3.put_object(Bucket=BUCKET, Key=PREFIX + path, Body=body, IfNoneMatch="*", ContentType=TYPES[local.suffix[1:]], CacheControl=MEDIA_CACHE)
            except ClientError as err:
                if code(err) != 412:
                    raise
            try:
                public_check(path, sha, len(body))
            except HTTPError as err:
                if err.code != 404:
                    raise
                # A link checker may have cached a 404 just before this first upload.
                public_check(path, sha, len(body), fresh=True)
                delayed.append((path, sha, len(body)))
        else:
            public_check(path, prefix)
    for path, sha, size in delayed:
        deadline = time.monotonic() + 210
        while True:
            try:
                public_check(path, sha, size)
                break
            except HTTPError as err:
                if err.code != 404 or time.monotonic() >= deadline:
                    raise
                time.sleep(6)
    if opts.stage_assets:
        print(f"Staged and verified {len(paths)} remote assets. Catalog still has ETag {current(s3, target)}.")
        return
    options = {"IfNoneMatch": "*"} if observed == "absent" else {"IfMatch": observed}
    try:
        s3.put_object(Bucket=BUCKET, Key=target, Body=data, ContentType="application/json", CacheControl=INDEX_CACHE, **options)
    except ClientError as err:
        if code(err) == 412:
            raise ValueError("Catalog changed during upload. Fetch and merge the latest index.") from err
        raise
    index_sha = hashlib.sha256(data).hexdigest()
    public_check(target, index_sha, len(data), fresh=True, prefix="")
    # Unqualified client requests may still have the previous 60-second CDN entry.
    deadline = time.monotonic() + 100
    while True:
        try:
            public_check(target, index_sha, len(data), prefix="")
            break
        except (ValueError, HTTPError):
            if time.monotonic() >= deadline:
                raise
            time.sleep(4)
    print(f"Verified {len(paths)} referenced remote assets. Published {BASE}{target} with ETag {current(s3, target)}.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, ClientError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
