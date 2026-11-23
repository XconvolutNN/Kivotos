"""Resolve the newest published Blender LTS Linux x64 release from official sources."""

import json
import os
from html.parser import HTMLParser
from pathlib import Path
import re
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


API = "https://projects.blender.org/api/v1/repos/blender/blender/milestones"
RELEASES = "https://download.blender.org/release/"

# Used when Blender's hosts rate-limit or block the build host: a known LTS
# release keeps the image build working instead of failing the workflow.
FALLBACK_VERSION = "5.2.4"

USER_AGENT = "kivotos-ci/1.0 (+https://github.com/XconvolutNN/Kivotos)"

# What Cloudflare serves instead of the page when it challenges a client.
CHALLENGE_MARKERS = ("Just a moment", "cf_chl_opt", "challenge-platform")


def fetch(url, attempts=3):
    error = None
    for attempt in range(attempts):
        try:
            request = Request(url, headers={"User-Agent": USER_AGENT})
            with urlopen(request, timeout=30) as response:
                text = response.read().decode("utf-8")
            if any(marker in text for marker in CHALLENGE_MARKERS):
                raise ValueError(f"Cloudflare challenge page at {url}")
            return text
        except (HTTPError, URLError, TimeoutError) as failure:
            error = failure
            if attempt + 1 < attempts:
                time.sleep(5 * (attempt + 1))
    if error is None:
        raise RuntimeError(f"Failed to fetch {url}")
    raise error


class Links(HTMLParser):
    def __init__(self, html):
        super().__init__()
        self.hrefs = set()
        self.feed(html)

    def handle_starttag(self, tag, attrs):
        if tag == "a":
            self.hrefs.update(value for key, value in attrs if key == "href" and value)


def resolve():
    series = set()
    page = 1
    while True:
        milestones = json.loads(fetch(f"{API}?state=open&limit=100&page={page}"))
        if not isinstance(milestones, list):
            raise ValueError("Unexpected milestone API response")
        if not milestones:
            break
        for milestone in milestones:
            match = re.fullmatch(r"(\d+)\.(\d+) LTS", milestone["title"])
            if match:
                series.add(tuple(map(int, match.groups())))
        page += 1

    published = Links(fetch(RELEASES)).hrefs
    for major, minor in sorted(series, reverse=True):
        name = f"{major}.{minor}"
        directory = f"Blender{name}/"
        if directory not in published:
            print(f"Skipping unpublished LTS series {name}", file=sys.stderr)
            continue
        base = RELEASES + directory
        files = Links(fetch(base)).hrefs
        versions = set()
        for filename in files:
            match = re.fullmatch(
                rf"blender-({re.escape(name)}\.\d+)-linux-x64\.tar\.xz", filename
            )
            if match and f"blender-{match[1]}.sha256" in files:
                versions.add(match[1])
        for version in sorted(versions, key=lambda value: tuple(map(int, value.split("."))), reverse=True):
            archive = f"blender-{version}-linux-x64.tar.xz"
            checksums = fetch(base + f"blender-{version}.sha256")
            hashes = [
                fields[0]
                for line in checksums.splitlines()
                if len(fields := line.split()) == 2 and fields[1].lstrip("*") == archive
            ]
            if len(hashes) != 1 or not re.fullmatch(r"[0-9a-fA-F]{64}", hashes[0]):
                raise ValueError(f"Missing or invalid SHA256 for {archive}")
            return version
    raise ValueError("No published Blender LTS Linux x64 release with SHA256 found")


def main():
    try:
        version = resolve()
    except Exception as failure:  # noqa: BLE001 - any lookup failure uses the pin
        print(
            f"warning: {failure}; falling back to Blender {FALLBACK_VERSION}",
            file=sys.stderr,
        )
        version = FALLBACK_VERSION
    print(version)
    if output := os.environ.get("GITHUB_OUTPUT"):
        with Path(output).open("a", encoding="utf-8") as stream:
            stream.write(f"version={version}\n")


if __name__ == "__main__":
    main()