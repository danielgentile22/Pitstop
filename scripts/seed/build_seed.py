#!/usr/bin/env python3
"""Builds Pitstop's bundled seed of unvisited chain locations in Virginia, Maryland and DC.

Downloads each brand's GeoJSON from the newest All The Places run (CC-0 data) where that brand's
spider finished its scrape, and brands All The Places lacks from OpenStreetMap through Overpass
(ODbL, credited in the README). Keeps points in the region, normalizes names and addresses, removes
duplicates within 50 m of the same brand or parent company, and writes the seed JSON the app
imports on launch. The seed version goes up only when the records change, counting from the app's
seed even when writing elsewhere. The script refuses to write when any brand drops by more than
30 percent or to zero from the app's seed, or when two records share a source ID.

    python3 scripts/seed/build_seed.py                     # network, writes the app's seed file
    python3 scripts/seed/build_seed.py --allow-drop        # same, even when a brand drops
    python3 scripts/seed/build_seed.py --fixtures DIR --output PATH
                                                           # reads DIR/<spider>.geojson and DIR/osm_<state>.json
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from dataclasses import dataclass
from functools import cache
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
BUNDLED_SEED = REPO_ROOT / "Pitstop" / "Pitstop" / "CandidateSeed.json"
ATP_RUN_HISTORY = "https://data.alltheplaces.xyz/runs/history.json"
OVERPASS_API = "https://overpass-api.de/api/interpreter"
USER_AGENT = "Pitstop seed builder (github.com/danielgentile22/Pitstop)"

DUPLICATE_RADIUS_METERS = 50
# A brand losing more than this share of its records since the app's seed usually means its source
# broke (a partial scrape, an outage), so the script stops unless --allow-drop is passed.
MAX_BRAND_DROP = 0.3
# Tries per download. Waits double from FETCH_FIRST_WAIT seconds; few tries, since a spider's GeoJSON
# can take minutes to download.
FETCH_ATTEMPTS = 4
FETCH_FIRST_WAIT = 15


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
    # Only features with this brand:wikidata. Fuel spiders list sibling brands (bp: Amoco and TA truck
    # stops, marathon_petroleum_us: Arco, seven_eleven_ca_us: Speedway and unbranded fuel pumps).
    wikidata: str | None = None

    def load(self, fixtures: Path | None) -> list[dict]:
        if fixtures is not None:
            return json.loads((fixtures / f"{self.spider}.geojson").read_text())["features"]
        run = newest_complete_run(self, run_history(), lambda r: run_feature_counts(r["stats_url"]))
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
BP = "bp"
EXXON_MOBIL = "exxon_mobil"
SEVEN_ELEVEN = "seven_eleven"

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
    AtpSource("wawa", "wawa", "Wawa", min_features=900),
    AtpSource("sheetz", "sheetz", "Sheetz", min_features=850),
    AtpSource("royal_farms", "royal_farms", "Royal Farms", min_features=310),
    AtpSource(
        "seven_eleven_ca_us", "seven_eleven", "7-Eleven", min_features=15_500, wikidata="Q259340", parent=SEVEN_ELEVEN
    ),
    AtpSource("speedway_us", "speedway", "Speedway", min_features=2_700, parent=SEVEN_ELEVEN),
    # Worldwide spider; the region and country checks keep the US stations.
    AtpSource("shell", "shell", "Shell", min_features=49_000),
    # The exxon_mobil spider last finished in June 2026, so its stations are from then.
    AtpSource("exxon_mobil", "exxon", "Exxon", min_features=17_000, wikidata="Q109675651", parent=EXXON_MOBIL),
    AtpSource("exxon_mobil", "mobil", "Mobil", min_features=17_000, wikidata="Q109676002", parent=EXXON_MOBIL),
    AtpSource("bp", "bp", "BP", min_features=19_500, wikidata="Q152057", parent=BP),
    AtpSource("bp", "amoco", "Amoco", min_features=19_500, wikidata="Q465952", parent=BP),
    AtpSource("sunoco_us", "sunoco", "Sunoco", min_features=5_300),
    # All The Places dropped its citgo spider after the May 2026 run, so its stations are from then.
    AtpSource("citgo", "citgo", "Citgo", min_features=4_300),
    AtpSource("valero", "valero", "Valero", min_features=4_200),
    AtpSource("marathon_petroleum_us", "marathon", "Marathon", min_features=7_600, wikidata="Q458363"),
    AtpSource("chevron_us", "chevron", "Chevron", min_features=16_500),
]

# Many 7-Elevens sell another brand's fuel (about 100 sell Exxon in the region), and both brands list
# the site. The restroom is the store's, so a fuel brand's station within 50 m of a 7-Eleven is dropped.
STORES_SELLING_OTHER_FUEL = {"seven_eleven"}
FUEL_BRANDS = {"shell", "exxon", "mobil", "bp", "amoco", "sunoco", "citgo", "valero", "marathon", "chevron"}

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


def fetch_json(url: str, data: bytes | None = None, timeout: int = 120):
    """GETs url, or POSTs data to it, and parses the JSON answer.

    Retries connection errors, server errors, rate limiting and unreadable answers with backoff,
    and exits on other client errors or after FETCH_ATTEMPTS tries.
    """
    for attempt in range(1, FETCH_ATTEMPTS + 1):
        request = urllib.request.Request(url, data=data, headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                answer = json.load(response)
            if isinstance(answer, dict) and "remark" in answer:  # Overpass's timeout or memory error, with a partial answer
                raise ValueError(answer["remark"])
            return answer
        except urllib.error.HTTPError as error:
            if 400 <= error.code < 500 and error.code != 429:
                sys.exit(f"{url}: {error}")
            failure = error
        except (OSError, ValueError) as error:  # busy servers also answer with an HTML page
            failure = error
        if attempt < FETCH_ATTEMPTS:
            wait = FETCH_FIRST_WAIT * 2 ** (attempt - 1)
            print(f"{url}: {failure}, retrying in {wait} s")
            time.sleep(wait)
    sys.exit(f"{url} failed {FETCH_ATTEMPTS} times, last with: {failure}")


@cache
def run_history() -> list[dict]:
    """Fetched once, so every source picks from the same list of runs."""
    return fetch_json(ATP_RUN_HISTORY)


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
    if not elements:  # every state has some of these shops, so none means the source failed
        sys.exit(f"OpenStreetMap returned no shops for {state}.")
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
    elements = fetch_json(OVERPASS_API, data=body, timeout=180)["elements"]
    print(f"overpass {state}: {len(elements)} elements")
    return elements


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
    region = " ".join(filter(None, [state, postcode]))
    if not street and not city:
        return clean(props.get("addr:full")) or region
    return ", ".join(filter(None, [street, city, region]))


def format_name(source: AtpSource | OsmSource, props: dict) -> str:
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
        if isinstance(source, AtpSource) and source.wikidata and props.get("brand:wikidata") != source.wikidata:
            stats[f"skipped {source.spider}: another brand"] += 1
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


def remove_duplicates(records: list[dict], previous_ids: set[str], stats: Counter) -> list[dict]:
    """Keeps one record of any same-brand or same-parent group within DUPLICATE_RADIUS_METERS, and one of
    a fuel brand's station and a store selling its fuel.

    The record kept is one from the previous seed when there is one, else the lowest source ID, so a
    new listing nearby never changes a place's identity (the app links dismissals and visits by ID).
    """

    def rank(record: dict) -> tuple[bool, str]:
        return record["sourceID"] not in previous_ids, record["sourceID"]

    stores = [r for r in records if r["brandKey"] in STORES_SELLING_OTHER_FUEL]
    fuel = [r for r in records if r["brandKey"] in FUEL_BRANDS]
    # The station is dropped, since the restroom is the store's, unless only the station was in the previous seed.
    fuel_at_store = {
        (s if f["sourceID"] in previous_ids and s["sourceID"] not in previous_ids else f)["sourceID"]
        for s in stores
        for f in fuel
        if meters_between(s, f) <= DUPLICATE_RADIUS_METERS
    }
    stats["skipped: fuel sold at a 7-Eleven"] += len(fuel_at_store)
    records = [r for r in records if r["sourceID"] not in fuel_at_store]
    kept: list[dict] = []
    for record in sorted(records, key=rank):
        if any(
            k["_group"] == record["_group"] and meters_between(k, record) <= DUPLICATE_RADIUS_METERS
            for k in kept
        ):
            stats["skipped: duplicate within 50 m"] += 1
            continue
        kept.append(record)
    return kept


def check_unique_ids(records: list[dict]) -> None:
    repeated = sorted(id for id, count in Counter(r["sourceID"] for r in records).items() if count > 1)
    if repeated:
        sys.exit("Records share a source ID: " + ", ".join(repeated))


def dropped_brands(previous: dict | None, records: list[dict]) -> list[str]:
    """Brands with more than MAX_BRAND_DROP fewer records than the previous seed, or none left."""
    if previous is None:
        return []
    before = Counter(r["brandKey"] for r in previous["records"])
    after = Counter(r["brandKey"] for r in records)
    return [
        f"{brand} {count} -> {after[brand]}"
        for brand, count in sorted(before.items())
        if after[brand] == 0 or after[brand] < count * (1 - MAX_BRAND_DROP)
    ]


def next_version(previous: dict | None, records: list[dict]) -> int:
    if previous is None:
        return 1
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
    parser.add_argument("--output", type=Path, help="where to write the seed (default: the app's seed file)")
    parser.add_argument("--allow-drop", action="store_true", help="write even when a brand drops")
    args = parser.parse_args(argv)
    if args.fixtures is not None:
        if args.output is None:
            parser.error("--fixtures needs --output, so fixture data never replaces the app's seed")
        if args.output.resolve() == BUNDLED_SEED.resolve():
            parser.error("--fixtures cannot write the app's seed file")
    output = args.output or BUNDLED_SEED

    stats: Counter = Counter()
    records = []
    for source in SOURCES:
        records.extend(build_records(source, source.load(args.fixtures), stats))
    previous = json.loads(BUNDLED_SEED.read_text()) if BUNDLED_SEED.exists() else None
    previous_ids = {r["sourceID"] for r in previous["records"]} if previous else set()
    records = sorted(remove_duplicates(records, previous_ids, stats), key=lambda r: r["sourceID"])
    print_counts(records, stats)

    check_unique_ids(records)

    for record in records:
        del record["_state"], record["_group"]
    if (dropped := dropped_brands(previous, records)) and not args.allow_drop:
        sys.exit("Brands dropped since the app's seed (pass --allow-drop to write anyway): " + ", ".join(dropped))
    version = next_version(previous, records)
    seed = {"version": version, "records": records}
    output.write_text(json.dumps(seed, indent=2, ensure_ascii=False) + "\n")
    print(f"Wrote version {version} to {output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
