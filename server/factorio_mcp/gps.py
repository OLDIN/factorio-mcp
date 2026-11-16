"""Parser for Factorio [gps=x,y,surface] tags."""

from __future__ import annotations

import math
import re
from dataclasses import dataclass

_MAX_LEN = 100
_GPS = re.compile(r"\[gps=([^,\[\]]+),([^,\[\]]+)(?:,([^,\[\]]+))?\]")
_SURFACE = re.compile(r"[A-Za-z0-9_\-. ]{1,64}")


class GpsParseError(ValueError):
    pass


@dataclass(frozen=True)
class GpsPoint:
    x: float
    y: float
    surface: str


def parse_gps(text: str) -> GpsPoint:
    if not text or len(text) > _MAX_LEN or any(ord(c) < 32 or ord(c) == 127 for c in text):
        raise GpsParseError("invalid gps text")
    match = _GPS.search(text)
    if match is None:
        raise GpsParseError("no [gps=x,y,surface] tag found")
    if re.match(r"[\w\]]", text[match.end() :]):
        raise GpsParseError("unexpected text right after the gps tag")
    try:
        x, y = float(match.group(1)), float(match.group(2))
    except ValueError:
        raise GpsParseError("gps coordinates are not numbers") from None
    if not (math.isfinite(x) and math.isfinite(y)):
        raise GpsParseError("gps coordinates must be finite")
    surface = match.group(3) or "nauvis"
    if _SURFACE.fullmatch(surface) is None:
        raise GpsParseError("invalid surface name")
    return GpsPoint(x, y, surface)
