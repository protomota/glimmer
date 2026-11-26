#!/usr/bin/env python3
"""Small App Store Connect helper for the TestFlight release script.

Reads APPLE_API_KEY_ID, APPLE_API_ISSUER and APPLE_API_KEY_FILE from the environment.

  asc.py latest-build <app-id> <version>          prints the newest build number for that version (0 if none)
  asc.py wait-build <app-id> <version> <build>    waits until Apple finishes processing the build
  asc.py internal-group <app-id> <version> <build>  puts the build in an internal tester group
"""
import base64, json, os, subprocess, sys, time, urllib.error, urllib.parse, urllib.request

GROUP_NAME = "Glimmer Internal"


def token():
    def b64(raw):
        return base64.urlsafe_b64encode(raw).rstrip(b"=")
    header = b64(json.dumps({"alg": "ES256", "kid": os.environ["APPLE_API_KEY_ID"], "typ": "JWT"}).encode())
    now = int(time.time())
    claims = b64(json.dumps({"iss": os.environ["APPLE_API_ISSUER"], "iat": now, "exp": now + 900,
                             "aud": "appstoreconnect-v1"}).encode())
    message = header + b"." + claims
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", os.environ["APPLE_API_KEY_FILE"]],
                         input=message, capture_output=True, check=True).stdout
    # openssl returns a DER signature; the token needs the raw r and s values.
    r_length = der[3]
    r = der[4:4 + r_length]
    s = der[6 + r_length:6 + r_length + der[5 + r_length]]
    return (message + b"." + b64(r[-32:].rjust(32, b"\0") + s[-32:].rjust(32, b"\0"))).decode()


def call(path, method="GET", body=None):
    request = urllib.request.Request(
        "https://api.appstoreconnect.apple.com/v1/" + path, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request) as response:
            text = response.read()
            return json.loads(text) if text else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        raise SystemExit(f"App Store Connect answered {error.code} for {method} {path}: {detail[:400]}")


def builds(app, version):
    query = urllib.parse.urlencode({"filter[app]": app, "filter[preReleaseVersion.version]": version,
                                    "limit": 200, "fields[builds]": "version,processingState"})
    return call("builds?" + query)["data"]


def latest_build(app, version):
    numbers = [int(row["attributes"]["version"]) for row in builds(app, version) if row["attributes"]["version"].isdigit()]
    print(max(numbers, default=0))


def find_build(app, version, build):
    return next((row for row in builds(app, version) if row["attributes"]["version"] == str(build)), None)


def wait_build(app, version, build):
    deadline = time.time() + 40 * 60
    while time.time() < deadline:
        row = find_build(app, version, build)
        state = row["attributes"]["processingState"] if row else "not listed yet"
        print(f"Build {version} ({build}): {state}", flush=True)
        if state == "VALID":
            return
        if state in ("INVALID", "FAILED"):
            raise SystemExit("Apple rejected the build during processing. Check the email from App Store Connect.")
        time.sleep(45)
    raise SystemExit("Apple is still processing after 40 minutes. Run `asc.py wait-build` again later.")


def internal_group(app, version, build):
    row = find_build(app, version, build)
    if not row:
        raise SystemExit("The build is not in App Store Connect.")
    groups = call(f"apps/{app}/betaGroups?limit=200")["data"]
    group = next((g for g in groups if g["attributes"].get("isInternalGroup")), None)
    if not group:
        group = call("betaGroups", "POST", {"data": {
            "type": "betaGroups",
            "attributes": {"name": GROUP_NAME, "isInternalGroup": True, "hasAccessToAllBuilds": True},
            "relationships": {"app": {"data": {"type": "apps", "id": app}}}}})["data"]
        print(f"Created the internal group “{GROUP_NAME}”.")
    if not group["attributes"].get("hasAccessToAllBuilds"):
        call(f"betaGroups/{group['id']}/relationships/builds", "POST", {"data": [{"type": "builds", "id": row["id"]}]})
    testers = call(f"betaGroups/{group['id']}/betaTesters?limit=200")["data"]
    print(f"Group “{group['attributes']['name']}” has the build and {len(testers)} tester(s).")
    if not testers:
        print("Add testers in App Store Connect: TestFlight, Internal Testing, then the + next to Testers.")
    # Apple only notifies a tester about builds after they accept the invitation email.
    waiting = [t["attributes"].get("firstName") or "a tester" for t in testers if t["attributes"].get("state") == "INVITED"]
    if waiting:
        print(f"Not accepted yet: {', '.join(waiting)}. They get no build notifications until they open the "
              "TestFlight invitation email and tap View in TestFlight.")


if __name__ == "__main__":
    commands = {"latest-build": latest_build, "wait-build": wait_build, "internal-group": internal_group}
    if len(sys.argv) < 2 or sys.argv[1] not in commands:
        raise SystemExit(__doc__)
    commands[sys.argv[1]](*sys.argv[2:])
