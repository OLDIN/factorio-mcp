from __future__ import annotations

import pytest

from factorio_mcp.gps import GpsParseError, GpsPoint, parse_gps


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("[gps=1.5,-2.25]", GpsPoint(1.5, -2.25, "nauvis")),
        ("[gps=1,2,nauvis]", GpsPoint(1.0, 2.0, "nauvis")),
        ("look [gps=10,20,vulcanus] here", GpsPoint(10.0, 20.0, "vulcanus")),
    ],
)
def test_parse_ok(text, expected):
    assert parse_gps(text) == expected


@pytest.mark.parametrize(
    "text",
    ["[gps=1,2,na]uvis]", "[gps=nan,1]", "[gps=1,2,a\nb]", "[gps=1e999,0]", "", "[gps=1,2," + "a" * 120 + "]"],
)
def test_parse_rejects(text):
    with pytest.raises(GpsParseError):
        parse_gps(text)
