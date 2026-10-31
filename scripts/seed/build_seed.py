#!/usr/bin/env python3
"""Builds Pitstop's bundled seed of unvisited chain locations in Virginia, Maryland and DC.

Downloads each brand's GeoJSON from the newest All The Places run (CC-0 data) where that brand's
spider finished its scrape, and brands All The Places lacks from OpenStreetMap through Overpass
(ODbL, credited in the README). Keeps points in the region, normalizes names and addresses, removes
duplicates within 50 m of the same brand or parent company, and writes the seed JSON the app
imports on launch. The seed version goes up only when the records change.

    python3 scripts/seed/build_seed.py                     # network, writes the app's seed file
    python3 scripts/seed/build_seed.py --fixtures DIR      # reads DIR/<spider>.geojson and DIR/osm_<state>.json
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
import time
import urllib.parse
import urllib.request
from collections import Counter
from dataclasses import dataclass
from functools import cache
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = REPO_ROOT / "Pitstop" / "Pitstop" / "CandidateSeed.json"
ATP_RUN_HISTORY = "https://data.alltheplaces.xyz/runs/history.json"
OVERPASS_API = "https://overpass-api.de/api/interpreter"
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
    # Only features with this OpenStreetMap shop tag. Grocery spiders also list in-store pharmacies
    # and fuel stations (safeway: 107 stores, 95 pharmacies, 16 fuel stations in the region).
    shop: str | None = None
    # Stores of brands with the same parent are deduplicated together, so a store a parent lists
    # under two of its banners shows one pin.
    parent: str | None = None

    def load(self, fixtures: Path | None) -> list[dict]:
        if fixtures is not None:
            return json.loads((fixtures / f"{self.spider}.geojson").read_text())["features"]
        run = newest_complete_run(self, fetch_json(ATP_RUN_HISTORY), lambda r: run_feature_counts(r["stats_url"]))
        print(f"{self.spider}: run {run['run_id']}")
        base = run["output_url"].rsplit("/", 1)[0]
        return fetch_json(f"{base}/output/{self.spider}.geojson")["features"]

    def source_id(self, feature: dict) -> str | None:
        ref = clean((feature.get("properties") or {}).get("ref")) or clean(feature.get("id"))
        return f"atp:{self.spider}:{ref}" if ref else None


@dataclass(frozen=True)
class OsmSource:
    """A brand All The Places has no spider for, read from OpenStreetMap supermarkets by brand:wikidata."""

    wikidata: str
    brand_key: str
    display_name: str
    shop: str | None = "supermarket"
    parent: str | None = None

    def load(self, fixtures: Path | None) -> list[dict]:
        return [f for state in ("VA", "MD", "DC") for f in osm_features(state, fixtures) if f["_wikidata"] == self.wikidata]

    def source_id(self, feature: dict) -> str | None:
        return f"osm:{feature['id']}"


AHOLD_DELHAIZE = "ahold_delhaize"

SOURCES = [
    AtpSource("barnes_and_noble_us", "barnes_and_noble", "Barnes & Noble", min_features=550),
    AtpSource("target_us", "target", "Target", min_features=1_900),
    # One brand for Supercenters and Neighborhood Markets; the branch keeps them apart in the name.
    AtpSource("walmart_us", "walmart", "Walmart", min_features=4_000),
    AtpSource("wegmans_us", "wegmans", "Wegmans", min_features=110, shop="supermarket"),
    AtpSource("giant_food_us", "giant", "Giant", min_features=155, shop="supermarket", parent=AHOLD_DELHAIZE),
    AtpSource("safeway", "safeway", "Safeway", min_features=1_850, shop="supermarket"),
    AtpSource("whole_foods", "whole_foods", "Whole Foods", min_features=520, shop="supermarket"),
    AtpSource("publix_us", "publix", "Publix", min_features=3_100, shop="supermarket"),
    # Worldwide spider; the region and country checks keep the US stores.
    AtpSource("lidl", "lidl", "Lidl", min_features=12_500, shop="supermarket"),
    AtpSource("food_lion_us", "food_lion", "Food Lion", min_features=1_100, shop="supermarket", parent=AHOLD_DELHAIZE),
    AtpSource("trader_joes_us", "trader_joes", "Trader Joe's", min_features=620, shop="supermarket"),
    AtpSource("aldi_sud_us", "aldi", "Aldi", min_features=2_500, shop="supermarket"),
    # All The Places has no Harris Teeter or Weis spider (checked 2026-10-31).
    OsmSource("Q5665067", "harris_teeter", "Harris Teeter"),
    OsmSource("Q7980370", "weis", "Weis"),
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


@cache
def osm_features(state: str, fixtures: Path | None) -> list[dict]:
    """Every OsmSource brand's shops inside one state, as GeoJSON-like features.

    The state comes from the query area, since many OpenStreetMap shops have no addr:state tag.
    """
    if fixtures is not None:
        elements = json.loads((fixtures / f"osm_{state.lower()}.json").read_text())["elements"]
    else:
        elements = overpass(state)
    features = []
    for element in elements:
        tags = element.get("tags") or {}
        center = element.get("center") or element
        if "lat" not in center:
            continue
        features.append(
            {
                "id": f"{element['type']}/{element['id']}",
                "_wikidata": tags.get("brand:wikidata"),
                "properties": {**tags, "addr:state": state},
                "geometry": {"type": "Point", "coordinates": [center["lon"], center["lat"]]},
            }
        )
    return features


def overpass(state: str) -> list[dict]:
    wikidata = "|".join(s.wikidata for s in SOURCES if isinstance(s, OsmSource))
    query = f"""[out:json][timeout:120];
area["ISO3166-2"="US-{state}"]->.region;
nwr["brand:wikidata"~"^({wikidata})$"](area.region);
out center tags;"""
    body = urllib.parse.urlencode({"data": query}).encode()
    for attempt in range(5):
        request = urllib.request.Request(OVERPASS_API, data=body, headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(request, timeout=180) as response:
                answer = json.load(response)
            if "remark" in answer:  # a timeout or memory error, reported with a partial answer
                raise ValueError(answer["remark"])
            elements = answer["elements"]
            print(f"overpass {state}: {len(elements)} elements")
            return elements
        except (OSError, ValueError) as error:  # the public server answers 429/504 or an HTML page when busy
            wait = 15 * 2**attempt
            print(f"overpass {state}: {error}, retrying in {wait} s")
            time.sleep(wait)
    sys.exit(f"Overpass did not answer for {state}.")


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


def build_records(source: AtpSource | OsmSource, features: list[dict], stats: Counter) -> list[dict]:
    records = []
    for feature in features:
        props = feature.get("properties") or {}
        geometry = feature.get("geometry") or {}
        source_id = source.source_id(feature)
        if geometry.get("type") != "Point" or not source_id:
            stats["skipped: no point or ID"] += 1
            continue
        state = state_code(props)
        if state is None or clean(props.get("addr:country")) not in (None, "US"):
            stats["skipped: outside VA, MD, DC"] += 1
            continue
        if source.shop and props.get("shop") != source.shop:
            stats[f"skipped: not shop={source.shop}"] += 1
            continue
        lon, lat = geometry["coordinates"][:2]
        hours = clean(props.get("opening_hours"))
        records.append(
            {
                "sourceID": source_id,
                "brandKey": source.brand_key,
                "name": format_name(source, props),
                "latitude": round(lat, 6),
                "longitude": round(lon, 6),
                "address": format_address(props, state),
                "isOpen24Hours": is_open_24_hours(hours),
                "openingHours": hours,
                "_state": state,
                "_group": source.parent or source.brand_key,
            }
        )
    return records


def remove_duplicates(records: list[dict], stats: Counter) -> list[dict]:
    """Keeps the lowest source ID of any same-brand or same-parent group within DUPLICATE_RADIUS_METERS."""
    kept: list[dict] = []
    for record in sorted(records, key=lambda r: r["sourceID"]):
        if any(
            k["_group"] == record["_group"] and meters_between(k, record) <= DUPLICATE_RADIUS_METERS
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
        records.extend(build_records(source, source.load(args.fixtures), stats))
    records = remove_duplicates(records, stats)
    print_counts(records, stats)

    for record in records:
        del record["_state"], record["_group"]
    version = next_version(args.output, records)
    seed = {"version": version, "records": records}
    args.output.write_text(json.dumps(seed, indent=2, ensure_ascii=False) + "\n")
    print(f"Wrote version {version} to {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
