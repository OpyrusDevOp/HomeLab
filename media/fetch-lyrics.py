#!/usr/bin/env python3
"""Fetch missing lyrics for the Jellyfin music library from LRCLIB.

Scans every audio item in Jellyfin, and for each track without lyrics
(embedded or external), queries lrclib.net and uploads the .lrc back
through the Jellyfin API — no direct filesystem access needed.

Usage:
  JELLYFIN_URL=http://localhost:8096 JELLYFIN_API_KEY=xxxx ./fetch-lyrics.py [options]

Options:
  --dry-run          Show what would be uploaded without changing anything
  --plain-fallback   Also accept plain (unsynced) lyrics when no synced ones exist
  --delay SECONDS    Pause between LRCLIB requests (default: 0.5)
  --limit N          Stop after processing N tracks missing lyrics (0 = no limit)

Get an API key in Jellyfin: Dashboard > Advanced > API Keys.
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

LRCLIB_URL = "https://lrclib.net/api"
USER_AGENT = "homelab-lyrics-fetcher/1.0 (https://github.com/OpyrusDevOp)"
PAGE_SIZE = 500
# Search fallback: accept a result whose duration is within this many seconds
DURATION_TOLERANCE = 5


def http_json(url, headers=None, retries=0):
    req = urllib.request.Request(url, headers=headers or {})
    req.add_header("User-Agent", USER_AGENT)
    for attempt in range(retries + 1):
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError:
            raise
        except OSError:  # timeouts, connection resets, DNS hiccups
            if attempt == retries:
                raise
            time.sleep(2 * (attempt + 1))


class Jellyfin:
    def __init__(self, base_url, api_key):
        self.base = base_url.rstrip("/")
        self.headers = {"Authorization": f'MediaBrowser Token="{api_key}"'}

    def audio_items(self):
        """Yield every audio item in the library, paginated."""
        start = 0
        while True:
            params = urllib.parse.urlencode({
                "IncludeItemTypes": "Audio",
                "Recursive": "true",
                "StartIndex": start,
                "Limit": PAGE_SIZE,
                "SortBy": "AlbumArtist,Album,SortName",
            })
            page = http_json(f"{self.base}/Items?{params}", self.headers)
            items = page.get("Items", [])
            yield from items
            start += len(items)
            if start >= page.get("TotalRecordCount", 0) or not items:
                return

    def upload_lyrics(self, item_id, filename, lrc_text):
        params = urllib.parse.urlencode({"fileName": filename})
        req = urllib.request.Request(
            f"{self.base}/Audio/{item_id}/Lyrics?{params}",
            data=lrc_text.encode("utf-8"),
            method="POST",
            headers={**self.headers, "Content-Type": "text/plain",
                     "User-Agent": USER_AGENT},
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            resp.read()


def lrclib_lookup(artist, title, album, duration, plain_fallback):
    """Return (lyrics_text, synced?) or (None, False)."""
    # Exact match first
    params = {"artist_name": artist, "track_name": title}
    if album:
        params["album_name"] = album
    if duration:
        params["duration"] = duration
    try:
        rec = http_json(f"{LRCLIB_URL}/get?{urllib.parse.urlencode(params)}", retries=2)
        if rec.get("syncedLyrics"):
            return rec["syncedLyrics"], True
        if plain_fallback and rec.get("plainLyrics"):
            return rec["plainLyrics"], False
    except urllib.error.HTTPError as e:
        if e.code != 404:
            raise

    # Fuzzy search fallback, pick closest duration with synced lyrics
    params = urllib.parse.urlencode({"artist_name": artist, "track_name": title})
    results = http_json(f"{LRCLIB_URL}/search?{params}", retries=2)
    candidates = [
        r for r in results
        if not duration or abs((r.get("duration") or 0) - duration) <= DURATION_TOLERANCE
    ]
    for r in candidates:
        if r.get("syncedLyrics"):
            return r["syncedLyrics"], True
    if plain_fallback:
        for r in candidates:
            if r.get("plainLyrics"):
                return r["plainLyrics"], False
    return None, False


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--plain-fallback", action="store_true")
    ap.add_argument("--delay", type=float, default=0.5)
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    url = os.environ.get("JELLYFIN_URL")
    api_key = os.environ.get("JELLYFIN_API_KEY")
    if not url or not api_key:
        sys.exit("error: set JELLYFIN_URL and JELLYFIN_API_KEY environment variables")

    jf = Jellyfin(url, api_key)
    scanned = missing = found = uploaded = failed = 0

    for item in jf.audio_items():
        scanned += 1
        if item.get("HasLyrics"):
            continue
        missing += 1
        if args.limit and missing > args.limit:
            missing -= 1
            print(f"\nreached --limit {args.limit}, stopping")
            break

        title = item.get("Name") or ""
        artists = item.get("Artists") or []
        artist = artists[0] if artists else (item.get("AlbumArtist") or "")
        album = item.get("Album") or ""
        ticks = item.get("RunTimeTicks") or 0
        duration = round(ticks / 10_000_000) if ticks else None
        label = f"{artist} - {title}"

        if not title or not artist:
            print(f"skip  {label!r} (missing title or artist metadata)")
            continue

        try:
            lyrics, synced = lrclib_lookup(artist, title, album, duration,
                                           args.plain_fallback)
        except Exception as e:
            print(f"error {label}: lrclib lookup failed: {e}")
            failed += 1
            time.sleep(args.delay)
            continue

        if not lyrics:
            print(f"none  {label}")
            time.sleep(args.delay)
            continue

        found += 1
        kind = "synced" if synced else "plain"
        if args.dry_run:
            print(f"found {label} ({kind}, dry-run)")
        else:
            try:
                # Extension drives how Jellyfin stores it; .lrc for synced, .txt for plain
                ext = "lrc" if synced else "txt"
                jf.upload_lyrics(item["Id"], f"{title}.{ext}", lyrics)
                uploaded += 1
                print(f"ok    {label} ({kind})")
            except Exception as e:
                failed += 1
                print(f"error {label}: upload failed: {e}")

        time.sleep(args.delay)

    print(f"\nscanned {scanned} tracks: {missing} missing lyrics, "
          f"{found} found on lrclib, {uploaded} uploaded, {failed} errors")


if __name__ == "__main__":
    main()
