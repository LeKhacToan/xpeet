#!/usr/bin/env -S python3 -I
"""Turns part of a recorded drive into an anonymised test clip (specs/speed-accuracy R31).

Usage: python3 -I scripts/make-fixture.py build/drives/<drive>.jsonl <from_s> <to_s> XpeetTests/Fixtures/Drives/<name>.jsonl

- Keeps lines whose time is within [from_s, to_s] seconds of the recording's start (at most 120 s).
- Dates become seconds from the clip's start, so no real date is left.
- Coordinates become metres from the clip's first fix, written back as degrees around 0°, 0° on the same sphere
  the app uses, so distances stay exact and no real place is left.
- Refuses to write more than 1 MB.

Stdlib only. Run with python3 -I.
"""
import json
import math
import sys

EARTH_RADIUS = 6_371_000.0
MAX_SECONDS = 120
MAX_BYTES = 1_000_000


def line_time(event):
    kind = event["type"]
    if kind == "header":
        return event["header"]["startedAt"]
    if kind == "shown":
        return event["shown"]["time"]
    return event["arrival"]


def main(source, start, end, destination):
    start, end = float(start), float(end)
    if end <= start or end - start > MAX_SECONDS:
        sys.exit(f"error: clip must be 0-{MAX_SECONDS} s long")
    with open(source, encoding="utf-8") as handle:
        events = [json.loads(line) for line in handle if line.strip()]
    if not events or events[0]["type"] != "header":
        sys.exit("error: not a recorded drive (no header line)")

    recording_start = events[0]["header"]["startedAt"]
    clip_start = recording_start + start
    clip = [e for e in events[1:] if clip_start <= line_time(e) <= recording_start + end]
    origin = next(
        (e["fix"] for e in clip if e["type"] == "fix" and e["fix"]["horizontalAccuracy"] >= 0),
        None,
    )
    if origin is None:
        sys.exit("error: no fix with a position in that range")
    to_radians = math.pi / 180
    origin_lat, origin_lon = origin["latitude"] * to_radians, origin["longitude"] * to_radians
    cos_mid = math.cos(origin_lat)

    def anonymise(event):
        kind = event["type"]
        if "arrival" in event:
            event["arrival"] -= clip_start
        if kind == "fix":
            fix = event["fix"]
            fix["timestamp"] -= clip_start
            if fix["horizontalAccuracy"] >= 0:
                north = (fix["latitude"] * to_radians - origin_lat) * EARTH_RADIUS
                east = (fix["longitude"] * to_radians - origin_lon) * EARTH_RADIUS * cos_mid
                fix["latitude"] = north / EARTH_RADIUS / to_radians
                fix["longitude"] = east / EARTH_RADIUS / to_radians
            else:
                fix["latitude"] = fix["longitude"] = 0.0
        elif kind == "shown":
            event["shown"]["time"] -= clip_start
        return event

    header = events[0]
    header["header"]["startedAt"] = 0
    lines = [json.dumps(header, separators=(",", ":"))]
    lines += [json.dumps(anonymise(e), separators=(",", ":")) for e in clip]
    data = "\n".join(lines) + "\n"
    if len(data.encode("utf-8")) > MAX_BYTES:
        sys.exit(f"error: clip is over {MAX_BYTES} bytes; pick a shorter range")
    with open(destination, "w", encoding="utf-8") as handle:
        handle.write(data)
    print(f"make-fixture: {len(clip)} lines -> {destination}")


if __name__ == "__main__":
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    main(*sys.argv[1:])
