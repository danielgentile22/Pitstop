#!/usr/bin/env python3
"""Builds Pitstop's bundled seed of unvisited chain locations in Virginia, Maryland and DC.

Downloads each brand's GeoJSON from the newest All The Places run (CC-0 data) where that brand's
spider finished its scrape, keeps points in
the region, normalizes names and addresses, removes same-brand duplicates within 50 m, and writes
the seed JSON the app imports on launch. The seed version goes up only when the records change.

    python3 scripts/seed/build_seed.py                     # network, writes the app's seed file
    python3 scripts/seed/build_seed.py --fixtures DIR      # reads DIR/<spider>.geojson instead
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
import urllib.request
from collections import Counter
from dataclasses import dataclass
from functools import cache
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = REPO_ROOT / "Pitstop" / "Pitstop" / "CandidateSeed.json"
ATP_RUN_HISTORY = "https://data.alltheplaces.xyz/runs/history.json"
USER_AGENT = "Pitstop seed builder (github.com/danielgentile22/Pitstop)"

DUPLICATE_RADIUS_METERS = 50


@dataclass(frozen=True)
class AtpSource:
    """One All The Places spider, mapped to a brand key from the app's brand table (BrandProfile.swift)."""

    spider: str
    brand_key: str
    display_name: str
    # Nationwide feature count a full scrape reaches. Spiders often stop early (walmart_us returned
    # 540 of about 4,400 stores on 2026-10-17), so runs below this are skipped for that brand.
    min_features: int


SOURCES = [
    AtpSource("barnes_and_noble_us", "barnes_and_noble", "Barnes & Noble", min_features=550),
    AtpSource("target_us", "target", "Target", min_features=1_900),
    # One brand for Supercenters and Neighborhood Markets; the branch keeps them apart in the name.
    AtpSource("walmart_us", "walmart", "Walmart", min_features=4_000),
]

STATES = {
    "VA": "VA",
    "VIRGINIA": "VA",
    "MD": "MD",
    "MARYLAND": "MD",
    "DC": "DC",
    "D.C.": "DC",
    "DISTRICT OF COLUMBIA": "DC",
    "WASHINGTON DC": "DC",
    "WASHINGTON, DC": "DC",
}


# MARK: - Sources


def fetch_json(url: str):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response:
        return json.load(response)


def newest_complete_run(source: AtpSource, runs: list[dict], feature_counts) -> dict:
    """The newest run where the source's spider reached min_features. feature_counts(run) maps spider to count."""
    for run in sorted(runs, key=lambda r: r["run_id"], reverse=True):
        if feature_counts(run).get(source.spider, 0) >= source.min_features:
            return run
    sys.exit(f"No All The Places run has a complete {source.spider} scrape (at least {source.min_features}).")


@cache
def run_feature_counts(stats_url: str) -> dict[str, int]:
    return {r["spider"]: r["features"] for r in fetch_json(stats_url)["results"]}


def load_features(source: AtpSource, fixtures: Path | None) -> list[dict]:
    if fixtures is not None:
        return json.loads((fixtures / f"{source.spider}.geojson").read_text())["features"]
    run = newest_complete_run(source, fetch_json(ATP_RUN_HISTORY), lambda r: run_feature_counts(r["stats_url"]))
    print(f"{source.spider}: run {run['run_id']}")
    base = run["output_url"].rsplit("/", 1)[0]
    return fetch_json(f"{base}/output/{source.spider}.geojson")["features"]


# MARK: - Normalizing


def clean(value) -> str | None:
    if value is None:
        return None
    text = " ".join(str(value).split())
    return text or None


def state_code(props: dict) -> str | None:
    state = clean(props.get("addr:state"))
    return STATES.get(state.upper()) if state else None


def format_address(props: dict, state: str) -> str | None:
    street = clean(props.get("addr:street_address")) or clean(
        " ".join(filter(None, [clean(props.get("addr:housenumber")), clean(props.get("addr:street"))]))
    )
    city = clean(props.get("addr:city"))
    postcode = clean(props.get("addr:postcode"))
    if postcode:
        postcode = postcode[:5]
    if not street and not city:
        return clean(props.get("addr:full"))
    region = " ".join(filter(None, [state, postcode]))
    return ", ".join(filter(None, [street, city, region]))


def format_name(source: AtpSource, props: dict) -> str:
    branch = clean(props.get("branch"))
    return f"{source.display_name} ({branch})" if branch else source.display_name


DAYS = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
FULL_DAY = {"00:00-24:00", "00:00-23:59"}
RULE = re.compile(r"^(?P<days>[A-Za-z]{2}(?:\s*[-,]\s*[A-Za-z]{2})*)\s+(?P<times>.+)$")


def expand_days(selector: str) -> list[str] | None:
    days: list[str] = []
    for part in selector.split(","):
        bounds = [d.strip() for d in part.split("-")]
        if any(d not in DAYS for d in bounds) or len(bounds) > 2:
            return None
        start, end = DAYS.index(bounds[0]), DAYS.index(bounds[-1])
        span = (end - start) % 7
        days.extend(DAYS[(start + i) % 7] for i in range(span + 1))
    return days


def is_open_24_hours(hours: str | None) -> bool:
    """True only when an OpenStreetMap opening_hours string clearly covers all seven days, all day.

    Anything it cannot parse counts as not 24 hours, the safe answer for an emergency at 2am.
    """
    if not hours or not hours.strip():
        return False
    open_all_day: dict[str, bool] = {}
    for rule in filter(None, (r.strip() for r in hours.split(";"))):
        if rule == "24/7":
            open_all_day.update({d: True for d in DAYS})
            continue
        match = RULE.match(rule)
        days = expand_days(match["days"]) if match else None
        if days is None:
            return False
        times = match["times"].replace(" ", "")
        for day in days:
            open_all_day[day] = times in FULL_DAY
    return all(open_all_day.get(d, False) for d in DAYS)


# MARK: - Records


def meters_between(a: dict, b: dict) -> float:
    lat1, lon1, lat2, lon2 = map(math.radians, (a["latitude"], a["longitude"], b["latitude"], b["longitude"]))
    h = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    return 2 * 6_371_000 * math.asin(math.sqrt(h))


def build_records(source: AtpSource, features: list[dict], stats: Counter) -> list[dict]:
    records = []
    for feature in features:
        props = feature.get("properties") or {}
        geometry = feature.get("geometry") or {}
        ref = clean(props.get("ref")) or clean(feature.get("id"))
        if geometry.get("type") != "Point" or not ref:
            stats["skipped: no point or ID"] += 1
            continue
        state = state_code(props)
        if state is None:
            stats["skipped: outside VA, MD, DC"] += 1
            continue
        lon, lat = geometry["coordinates"][:2]
        hours = clean(props.get("opening_hours"))
        records.append(
            {
                "sourceID": f"atp:{source.spider}:{ref}",
                "brandKey": source.brand_key,
                "name": format_name(source, props),
                "latitude": round(lat, 6),
                "longitude": round(lon, 6),
                "address": format_address(props, state),
                "isOpen24Hours": is_open_24_hours(hours),
                "openingHours": hours,
                "_state": state,
            }
        )
    return records


def remove_duplicates(records: list[dict], stats: Counter) -> list[dict]:
    """Keeps the lowest source ID of any same-brand group within DUPLICATE_RADIUS_METERS."""
    kept: list[dict] = []
    for record in sorted(records, key=lambda r: r["sourceID"]):
        if any(
            k["brandKey"] == record["brandKey"] and meters_between(k, record) <= DUPLICATE_RADIUS_METERS
            for k in kept
        ):
            stats["skipped: duplicate within 50 m"] += 1
            continue
        kept.append(record)
    return kept


def next_version(output: Path, records: list[dict]) -> int:
    if not output.exists():
        return 1
    previous = json.loads(output.read_text())
    if previous.get("records") == records:
        return previous["version"]
    return previous.get("version", 0) + 1


def print_counts(records: list[dict], stats: Counter) -> None:
    by_brand = Counter(r["brandKey"] for r in records)
    by_state = Counter(r["_state"] for r in records)
    by_brand_state = Counter((r["brandKey"], r["_state"]) for r in records)
    print(f"{len(records)} locations")
    for brand, count in sorted(by_brand.items()):
        states = ", ".join(f"{s} {by_brand_state[(brand, s)]}" for s in ("VA", "MD", "DC"))
        print(f"  {brand}: {count} ({states})")
    print("By state: " + ", ".join(f"{s} {by_state[s]}" for s in ("VA", "MD", "DC")))
    for reason, count in sorted(stats.items()):
        print(f"  {reason}: {count}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--fixtures", type=Path, help="read <spider>.geojson files from this folder, no network")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args(argv)

    stats: Counter = Counter()
    records = []
    for source in SOURCES:
        records.extend(build_records(source, load_features(source, args.fixtures), stats))
    records = remove_duplicates(records, stats)
    print_counts(records, stats)

    for record in records:
        del record["_state"]
    version = next_version(args.output, records)
    seed = {"version": version, "records": records}
    args.output.write_text(json.dumps(seed, indent=2, ensure_ascii=False) + "\n")
    print(f"Wrote version {version} to {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
