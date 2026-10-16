#!/bin/sh
set -eu

# Xcode Cloud runs this hook in its temporary checkout. Ordinary local clones
# keep their build-setting placeholders and existing configuration workflow.
if [ "${CI_XCODE_CLOUD:-}" != "TRUE" ]; then
    printf 'Public app configuration unchanged outside Xcode Cloud.\n'
    exit 0
fi

python3 - <<'PY'
import ipaddress
import os
from pathlib import Path
import plistlib
import re
from urllib.parse import urlsplit


def fail(message):
    raise SystemExit("Xcode Cloud configuration: " + message)


client_id = os.environ.get("MORE_GOOGLE_CLIENT_ID", "")
suffix = ".apps.googleusercontent.com"
prefix = client_id[:-len(suffix)] if client_id.endswith(suffix) else ""
if not re.fullmatch(r"[A-Za-z0-9-]{1,512}", prefix):
    fail("MORE_GOOGLE_CLIENT_ID must be a valid public iOS Google client ID.")

callback = os.environ.get("MORE_GOOGLE_CALLBACK_SCHEME", "")
if callback != "com.googleusercontent.apps." + prefix:
    fail("MORE_GOOGLE_CALLBACK_SCHEME must match the public Google client ID.")

# Empty means the optional backend remains unconfigured, as in the manual build.
api_url = os.environ.get("MORNING_API_BASE_URL", "")
if api_url:
    if len(api_url) > 2048 or any(c.isspace() or ord(c) < 32 or ord(c) == 127 for c in api_url):
        fail("MORNING_API_BASE_URL must be empty or a valid HTTPS base URL.")
    try:
        parsed = urlsplit(api_url)
        host = parsed.hostname
        port = parsed.port
        if (parsed.scheme != "https" or not host or parsed.username is not None
                or parsed.password is not None or parsed.query or parsed.fragment
                or (port is not None and not 1 <= port <= 65535)):
            raise ValueError()
        try:
            ipaddress.ip_address(host)
        except ValueError:
            host = host.encode("idna").decode("ascii").rstrip(".")
            if len(host) > 253 or not all(
                re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", label)
                for label in host.split(".")
            ):
                raise ValueError()
    except (ValueError, UnicodeError):
        fail("MORNING_API_BASE_URL must be empty or a valid HTTPS base URL without credentials, query or fragment.")

checkout = os.environ.get("CI_PRIMARY_REPOSITORY_PATH")
if not checkout:
    fail("CI_PRIMARY_REPOSITORY_PATH is missing.")
path = Path(checkout) / "Configuration" / "iOS-Info.plist"
try:
    document = plistlib.loads(path.read_bytes())
    google_entries = [entry for entry in document["CFBundleURLTypes"]
                      if entry.get("CFBundleURLName") == "com.gibouu.morningoperator.google"]
    if (len(google_entries) != 1 or not isinstance(document["MOREGoogleClientID"], str)
            or not isinstance(document["MorningAPIBaseURL"], str)
            or not isinstance(google_entries[0]["CFBundleURLSchemes"], list)):
        raise ValueError()
except (OSError, KeyError, TypeError, ValueError, plistlib.InvalidFileException):
    fail("The app plist is missing or its public configuration structure changed.")

document["MOREGoogleClientID"] = client_id
document["MorningAPIBaseURL"] = api_url
google_entries[0]["CFBundleURLSchemes"] = [callback]
path.write_bytes(plistlib.dumps(document, sort_keys=False))
print("Public Google configuration prepared; optional backend " + ("configured." if api_url else "left empty."))
PY
