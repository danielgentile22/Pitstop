import http.client
import io
import json
import re
import shutil
import urllib.error
from collections import Counter
from pathlib import Path

import pytest

import build_seed

FIXTURES = Path(__file__).parent / "fixtures"


@pytest.fixture(autouse=True)
def bundled_seed(tmp_path, monkeypatch):
    """Points the bundled seed at a temporary path, so no test reads or writes the app's real seed."""
    path = tmp_path / "bundled" / "CandidateSeed.json"
    path.parent.mkdir()
    monkeypatch.setattr(build_seed, "BUNDLED_SEED", path)
    return path


def run(output: Path, *flags: str, fixtures: Path = FIXTURES) -> dict:
    build_seed.main(["--fixtures", str(fixtures), "--output", str(output), *flags])
    return json.loads(output.read_text())


def edited_fixtures(tmp_path, name: str, edit) -> Path:
    """A copy of the fixtures folder with edit(data) applied to one file's parsed JSON."""
    folder = tmp_path / "fixtures"
    shutil.copytree(FIXTURES, folder)
    data = json.loads((folder / name).read_text())
    edit(data)
    (folder / name).write_text(json.dumps(data))
    return folder


@pytest.fixture
def seed(tmp_path):
    return run(tmp_path / "seed.json")


def by_id(seed):
    return {r["sourceID"]: r for r in seed["records"]}


def test_keeps_only_virginia_maryland_and_dc(seed):
    ids = by_id(seed)
    assert "atp:barnes_and_noble_us:200" not in ids  # Pennsylvania
    assert "atp:barnes_and_noble_us:101" in ids  # Maryland
    assert "atp:barnes_and_noble_us:102" in ids  # DC
    assert "atp:barnes_and_noble_us:103" in ids  # state spelled out


def test_skips_features_without_a_point(seed):
    assert "atp:barnes_and_noble_us:106" not in by_id(seed)


def test_removes_same_brand_duplicates_within_50_meters(seed):
    ids = by_id(seed)
    assert "atp:barnes_and_noble_us:100" in ids
    assert "atp:barnes_and_noble_us:104" not in ids  # about 20 m from 100
    assert "atp:barnes_and_noble_us:105" in ids  # about 150 m from 100


def test_normalizes_name_and_address(seed):
    ids = by_id(seed)
    assert ids["atp:barnes_and_noble_us:100"]["name"] == "Barnes & Noble (Potomac Yard)"
    assert ids["atp:barnes_and_noble_us:102"]["name"] == "Barnes & Noble (Union Station)"
    assert ids["atp:barnes_and_noble_us:103"]["name"] == "Barnes & Noble"
    assert ids["atp:barnes_and_noble_us:100"]["address"] == "100 Main St, Town, VA 22305"
    assert ids["atp:barnes_and_noble_us:103"]["address"] == "103 Main St, Town, VA 22305"


def test_record_shape(seed):
    record = by_id(seed)["atp:barnes_and_noble_us:100"]
    assert record == {
        "sourceID": "atp:barnes_and_noble_us:100",
        "brandKey": "barnes_and_noble",
        "name": "Barnes & Noble (Potomac Yard)",
        "latitude": 38.837931,
        "longitude": -77.051482,
        "address": "100 Main St, Town, VA 22305",
        "isOpen24Hours": False,
        "openingHours": "Mo-Sa 09:00-21:00; Su 11:00-19:00",
    }


def test_sets_24_hour_flag_and_raw_hours(seed):
    ids = by_id(seed)
    assert ids["atp:barnes_and_noble_us:101"]["isOpen24Hours"] is True
    assert ids["atp:barnes_and_noble_us:101"]["openingHours"] == "24/7"
    assert ids["atp:barnes_and_noble_us:102"]["isOpen24Hours"] is True
    assert ids["atp:barnes_and_noble_us:103"]["isOpen24Hours"] is False
    assert ids["atp:barnes_and_noble_us:103"]["openingHours"] is None


@pytest.mark.parametrize(
    "hours, expected",
    [
        ("24/7", True),
        (" 24/7 ", True),
        ("Mo-Su 00:00-24:00", True),
        ("Mo-Su 00:00-23:59", True),
        ("Mo-Fr 00:00-24:00; Sa,Su 00:00-24:00", True),
        ("Mo-Fr 00:00-24:00; Sa 00:00-24:00", False),  # Sunday missing
        ("Mo-Su 06:00-24:00", False),
        ("Mo-Sa 09:00-21:00; Su 11:00-19:00", False),
        ("Mo-Su 00:00-24:00; Su off", False),
        ("", False),
        (None, False),
    ],
)
def test_is_open_24_hours(hours, expected):
    assert build_seed.is_open_24_hours(hours) is expected


def test_records_are_sorted_by_source_id(seed):
    ids = [r["sourceID"] for r in seed["records"]]
    assert ids == sorted(ids)


def test_version_bumps_only_when_records_change(tmp_path, bundled_seed):
    output = tmp_path / "seed.json"
    first = run(output)
    assert first["version"] == 1

    bundled_seed.write_text(json.dumps({"version": 7, "records": first["records"]}))
    assert run(output)["version"] == 7

    bundled_seed.write_text(json.dumps({"version": 7, "records": first["records"][1:]}))
    assert run(output)["version"] == 8


def test_version_is_based_on_the_bundled_seed_not_the_output(tmp_path, bundled_seed):
    output = tmp_path / "seed.json"
    records = run(output)["records"]
    bundled_seed.write_text(json.dumps({"version": 41, "records": records[1:]}))
    output.write_text(json.dumps({"version": 3, "records": records[1:]}))
    assert run(tmp_path / "new.json")["version"] == 42
    assert run(output)["version"] == 42


def test_fixture_mode_requires_an_output_path():
    with pytest.raises(SystemExit) as exit:
        build_seed.main(["--fixtures", str(FIXTURES)])
    assert exit.value.code != 0


def test_fixture_mode_refuses_to_write_the_bundled_seed(bundled_seed):
    bundled_seed.write_text('{"version": 5, "records": []}')
    with pytest.raises(SystemExit) as exit:
        build_seed.main(["--fixtures", str(FIXTURES), "--output", str(bundled_seed.parent / "." / bundled_seed.name)])
    assert exit.value.code != 0
    assert bundled_seed.read_text() == '{"version": 5, "records": []}'


def previous_seed(records: list[dict], brand_key: str, count: int) -> dict:
    """A previous seed with this run's records, but `count` records of one brand."""
    template = next(r for r in records if r["brandKey"] == brand_key)
    others = [r for r in records if r["brandKey"] != brand_key]
    brand = [{**template, "sourceID": f"{template['sourceID']}-old{i}"} for i in range(count)]
    return {"version": 1, "records": others + brand}


@pytest.mark.parametrize("previous_count, fails", [(7, False), (8, True)])
def test_a_brand_dropping_more_than_30_percent_fails(tmp_path, bundled_seed, previous_count, fails):
    output = tmp_path / "seed.json"
    records = run(output)["records"]
    output.unlink()
    assert Counter(r["brandKey"] for r in records)["barnes_and_noble"] == 5
    # 7 to 5 is a 29 percent drop, 8 to 5 is 38 percent.
    bundled_seed.write_text(json.dumps(previous_seed(records, "barnes_and_noble", previous_count)))
    if fails:
        with pytest.raises(SystemExit) as exit:
            run(output)
        assert "barnes_and_noble 8 -> 5" in str(exit.value.code)
        assert not output.exists()
    else:
        assert run(output)["version"] == 2


@pytest.mark.parametrize(
    "before, after, fails",
    [(10, 7, False), (10, 6, True), (1, 1, False), (1, 0, True), (3, 2, True), (100, 150, False)],
)
def test_drop_threshold(before, after, fails):
    previous = {"records": [{"brandKey": "wawa"}] * before}
    assert bool(build_seed.dropped_brands(previous, [{"brandKey": "wawa"}] * after)) is fails


def test_a_brand_dropping_to_zero_fails(tmp_path, bundled_seed):
    output = tmp_path / "seed.json"
    records = run(output)["records"]
    output.unlink()
    previous = {"version": 1, "records": records}
    bundled_seed.write_text(json.dumps(previous))
    without_target = edited_fixtures(tmp_path, "target_us.geojson", lambda data: data.update(features=[]))
    with pytest.raises(SystemExit) as exit:
        run(output, fixtures=without_target)
    assert exit.value.code != 0
    assert not output.exists()


def test_allow_drop_writes_a_seed_that_drops_a_brand(tmp_path, bundled_seed):
    output = tmp_path / "seed.json"
    records = run(output)["records"]
    bundled_seed.write_text(json.dumps({"version": 1, "records": records}))
    without_target = edited_fixtures(tmp_path, "target_us.geojson", lambda data: data.update(features=[]))
    seed = run(output, "--allow-drop", fixtures=without_target)
    assert seed["version"] == 2
    assert not any(r["brandKey"] == "target" for r in seed["records"])


def test_an_empty_openstreetmap_result_fails(tmp_path):
    output = tmp_path / "seed.json"
    empty_maryland = edited_fixtures(tmp_path, "osm_md.json", lambda data: data.update(elements=[]))
    with pytest.raises(SystemExit) as exit:
        run(output, fixtures=empty_maryland)
    assert exit.value.code != 0
    assert not output.exists()


def test_duplicate_source_ids_fail_and_name_the_ids(tmp_path):
    output = tmp_path / "seed.json"

    def add_far_copy_of_store_100(data):
        store = next(f for f in data["features"] if f["properties"]["ref"] == "100")
        copy = json.loads(json.dumps(store))
        copy["geometry"]["coordinates"][1] += 0.01  # about 1.1 km north, too far to count as a duplicate
        data["features"].append(copy)

    duplicated = edited_fixtures(tmp_path, "barnes_and_noble_us.geojson", add_far_copy_of_store_100)
    with pytest.raises(SystemExit) as exit:
        run(output, fixtures=duplicated)
    assert "atp:barnes_and_noble_us:100" in str(exit.value.code)
    assert not output.exists()


def test_maps_target_and_walmart_to_their_brands(seed):
    ids = by_id(seed)
    assert ids["atp:target_us:3430"]["brandKey"] == "target"
    assert ids["atp:target_us:3430"]["name"] == "Target (Pentagon City)"
    assert ids["atp:target_us:3430"]["address"] == "900 Army Navy Dr, Arlington, VA 20000"
    assert ids["atp:walmart_us:1860"]["brandKey"] == "walmart"
    assert ids["atp:walmart_us:1860"]["name"] == "Walmart (Elkton Supercenter)"


def test_walmart_neighborhood_market_is_walmart(seed):
    record = by_id(seed)["atp:walmart_us:3622"]
    assert record["brandKey"] == "walmart"
    assert record["name"] == "Walmart (Roanoke Neighborhood Market)"


def test_keeps_target_and_walmart_outside_the_region_out(seed):
    ids = by_id(seed)
    assert "atp:target_us:1800" not in ids  # Pennsylvania
    assert "atp:walmart_us:2662" not in ids  # West Virginia


def test_keeps_different_brands_at_the_same_spot(seed):
    ids = by_id(seed)
    assert "atp:target_us:3328" in ids
    assert "atp:walmart_us:5968" in ids  # about 20 m from Target 3328


def test_uses_the_newest_run_where_the_spider_finished():
    walmart = next(s for s in build_seed.SOURCES if s.brand_key == "walmart")
    runs = [{"run_id": "2026-01-31"}, {"run_id": "2026-10-10"}, {"run_id": "2026-10-17"}]
    counts = {"2026-01-31": walmart.min_features + 10, "2026-10-10": 1484, "2026-10-17": 540}
    run = build_seed.newest_complete_run(walmart, runs, lambda r: {walmart.spider: counts[r["run_id"]]})
    assert run["run_id"] == "2026-01-31"


def test_fails_when_no_run_has_a_complete_scrape():
    walmart = next(s for s in build_seed.SOURCES if s.brand_key == "walmart")
    with pytest.raises(SystemExit):
        build_seed.newest_complete_run(walmart, [{"run_id": "2026-10-17"}], lambda r: {walmart.spider: 540})


@pytest.mark.parametrize(
    "source_id, brand_key, name",
    [
        ("atp:wegmans_us:148", "wegmans", "Wegmans (Rockville)"),
        ("atp:giant_food_us:#0778", "giant", "Giant (Oaksprings Plaza)"),
        ("atp:safeway:1298", "safeway", "Safeway"),
        ("atp:whole_foods:10185", "whole_foods", "Whole Foods (Old Town)"),
        ("atp:publix_us:1720", "publix", "Publix (Embrey Mill Town Center)"),
        ("atp:lidl:US01001", "lidl", "Lidl (Mall Dr)"),
        ("atp:food_lion_us:901", "food_lion", "Food Lion"),
        ("atp:trader_joes_us:883", "trader_joes", "Trader Joe's (Baltimore - Anneslie)"),
        ("atp:aldi_sud_us:FF73", "aldi", "Aldi"),
        ("osm:node/577268783", "harris_teeter", "Harris Teeter (Woodland Park Crossing)"),
        ("osm:way/41000001", "weis", "Weis"),
    ],
)
def test_maps_grocery_chains_to_their_brands(seed, source_id, brand_key, name):
    record = by_id(seed)[source_id]
    assert record["brandKey"] == brand_key
    assert record["name"] == name


def test_keeps_only_the_supermarket_of_a_grocery_chain(seed):
    ids = by_id(seed)
    assert "atp:safeway:1298" in ids
    assert "atp:safeway:1298-P" not in ids  # pharmacy inside the store
    assert "atp:safeway:5832-F" not in ids  # fuel station 300 m away
    assert "atp:publix_us:1720-P" not in ids  # pharmacy listed 1 km away


def test_removes_duplicates_between_chains_with_the_same_parent_company(seed):
    ids = by_id(seed)
    assert "atp:food_lion_us:900" in ids
    assert "atp:giant_food_us:#0900" not in ids  # about 20 m from Food Lion 900, both Ahold Delhaize


def test_keeps_chains_with_different_parents_at_the_same_spot(seed):
    ids = by_id(seed)
    assert "atp:safeway:1298" in ids
    assert "atp:giant_food_us:#0901" in ids  # about 20 m from Safeway 1298


def test_skips_stores_outside_the_united_states(seed):
    assert "atp:lidl:IT0123" not in by_id(seed)  # Varese, Italy, province code VA


def test_reads_openstreetmap_nodes_and_ways(seed):
    ids = by_id(seed)
    assert ids["osm:node/577268783"] == {
        "sourceID": "osm:node/577268783",
        "brandKey": "harris_teeter",
        "name": "Harris Teeter (Woodland Park Crossing)",
        "latitude": 38.949539,
        "longitude": -77.394931,
        "address": "12960 Highland Crossing Drive, Herndon, VA 20171",
        "isOpen24Hours": False,
        "openingHours": "Mo-Su 06:00-23:00",
    }
    weis = ids["osm:way/41000001"]
    assert (weis["latitude"], weis["longitude"]) == (39.6418, -77.72)  # the way's center
    assert weis["isOpen24Hours"] is True


def test_takes_the_state_from_the_openstreetmap_query_area(seed):
    # The Weis way has no addr:state tag; it came back from the Maryland query.
    assert by_id(seed)["osm:way/41000001"]["address"] == "1700 Dual Highway, Hagerstown, MD"


def test_every_brand_is_in_the_app_brand_table():
    table = (build_seed.REPO_ROOT / "Pitstop" / "Pitstop" / "BrandProfile.swift").read_text()
    app_keys = set(re.findall(r'BrandProfile\(key: "(\w+)"', table))
    assert {s.brand_key for s in build_seed.SOURCES} <= app_keys


@pytest.mark.parametrize(
    "source_id, brand_key, name",
    [
        ("atp:wawa:6008", "wawa", "Wawa"),
        ("atp:sheetz:41", "sheetz", "Sheetz"),
        ("atp:royal_farms:2064", "royal_farms", "Royal Farms"),
        ("atp:seven_eleven_ca_us:40063_SHOP", "seven_eleven", "7-Eleven"),
        ("atp:shell:10014751", "shell", "Shell"),
        ("atp:exxon_mobil:200310061", "exxon", "Exxon"),
        ("atp:exxon_mobil:200331860", "mobil", "Mobil"),
        ("atp:bp:US-128668", "bp", "BP"),
        ("atp:bp:US-96582892290402109300100000000000", "amoco", "Amoco"),
        ("atp:sunoco_us:8003437401", "sunoco", "Sunoco"),
        ("atp:citgo:39433188", "citgo", "Citgo"),
        ("atp:speedway_us:46613", "speedway", "Speedway"),
        ("atp:valero:0000004059", "valero", "Valero"),
        ("atp:marathon_petroleum_us:11754", "marathon", "Marathon"),
        ("atp:chevron_us:207288", "chevron", "Chevron"),
    ],
)
def test_maps_gas_stations_to_their_brands(seed, source_id, brand_key, name):
    record = by_id(seed)[source_id]
    assert record["brandKey"] == brand_key
    assert record["name"] == name


def test_keeps_only_the_named_brand_of_a_spider_that_lists_several(seed):
    ids = by_id(seed)
    assert "atp:marathon_petroleum_us:13018" not in ids  # an Arco in the Marathon spider
    assert "atp:seven_eleven_ca_us:46613_SHOP" not in ids  # a Speedway in the 7-Eleven spider
    assert "atp:seven_eleven_ca_us:40063" not in ids  # the store's fuel pumps, listed without a brand


def test_drops_another_brands_fuel_sold_at_a_7_eleven(seed):
    ids = by_id(seed)
    assert "atp:seven_eleven_ca_us:40063_SHOP" in ids
    assert "atp:sunoco_us:8003437499" not in ids  # about 20 m from the 7-Eleven


def test_flags_24_hour_gas_stations(seed):
    ids = by_id(seed)
    for source_id in ["atp:wawa:6008", "atp:sheetz:41", "atp:shell:10014751", "atp:seven_eleven_ca_us:40063_SHOP"]:
        assert ids[source_id]["isOpen24Hours"] is True, source_id
    assert ids["atp:exxon_mobil:200310061"]["isOpen24Hours"] is False  # Mo-Sa 05:00-24:00; Su 06:00-24:00


@pytest.mark.parametrize(
    "hours",
    [
        "Fr-Mo 00:00-24:00; Tu-Th 00:00-24:00",  # a day range that wraps past Sunday
        "Sa-Fr 00:00-24:00",
        "Su-Sa 00:00-23:59",
    ],
)
def test_is_open_24_hours_wraps_day_ranges_past_sunday(hours):
    assert build_seed.is_open_24_hours(hours) is True


@pytest.mark.parametrize(
    "hours",
    [
        "Fr-Mo 00:00-24:00",  # wraps, but only covers four days
        "Mo-Xx 00:00-24:00",
        "Mo-Tu-We 00:00-24:00",
        "Mo-Su",
        "always open",
        "24/7; PH off",
        "Mo-Su 00:00-24:00 open",
        ";",
    ],
)
def test_is_open_24_hours_rejects_partial_and_malformed_hours(hours):
    assert build_seed.is_open_24_hours(hours) is False


@pytest.mark.parametrize(
    "props, address",
    [
        ({"addr:full": "Route 40, Hagerstown", "addr:postcode": "21740"}, "Route 40, Hagerstown"),
        ({"addr:postcode": "21740-1234"}, "MD 21740"),
        ({}, "MD"),
        ({"addr:city": "Hagerstown"}, "Hagerstown, MD"),
    ],
)
def test_address_falls_back_to_the_full_address_then_state_and_postcode(props, address):
    assert build_seed.format_address(props, "MD") == address


def add_nearby_feature(near_ref: str, ref: str, wikidata: str | None):
    """An edit that adds a copy of the fixture feature with near_ref, about 20 m north, as ref and wikidata."""

    def edit(data):
        near = next(f for f in features_of(near_ref) if f["properties"]["ref"] == near_ref)
        feature = json.loads(json.dumps(near))
        feature["properties"].update(ref=ref, **{"brand:wikidata": wikidata})
        feature["geometry"]["coordinates"][1] += 0.00018
        data["features"].append(feature)

    return edit


def features_of(ref: str) -> list[dict]:
    return [
        f
        for path in FIXTURES.glob("*.geojson")
        for f in json.loads(path.read_text())["features"]
        if (f.get("properties") or {}).get("ref") == ref
    ]


@pytest.mark.parametrize(
    "file, near_ref, ref, wikidata, kept, dropped",
    [
        ("exxon_mobil.geojson", "200310061", "200310062", "Q109676002", "atp:exxon_mobil:200310061", "atp:exxon_mobil:200310062"),
        ("bp.geojson", "US-128668", "US-128669", "Q465952", "atp:bp:US-128668", "atp:bp:US-128669"),
        ("speedway_us.geojson", "40063_SHOP", "1", "Q7575683", "atp:seven_eleven_ca_us:40063_SHOP", "atp:speedway_us:1"),
    ],
    ids=["exxon and mobil", "bp and amoco", "7-eleven and speedway"],
)
def test_removes_duplicates_between_sibling_brands(tmp_path, file, near_ref, ref, wikidata, kept, dropped):
    folder = edited_fixtures(tmp_path, file, add_nearby_feature(near_ref, ref, wikidata))
    ids = by_id(run(tmp_path / "seed.json", fixtures=folder))
    assert kept in ids
    assert dropped not in ids


def test_sibling_brands_far_apart_are_both_kept(tmp_path):
    ids = by_id(run(tmp_path / "seed.json"))
    assert "atp:exxon_mobil:200310061" in ids
    assert "atp:exxon_mobil:200331860" in ids  # a Mobil about 300 km away


def previous_with(records: list[dict], new_id: str, previous_id: str) -> dict:
    """A previous seed of these records, with new_id's record shipped as previous_id's brand and ID instead."""
    spider = previous_id.split(":")[1]
    brand_key = next(s.brand_key for s in build_seed.SOURCES if getattr(s, "spider", None) == spider)
    swapped = [{**r, "sourceID": previous_id, "brandKey": brand_key} if r["sourceID"] == new_id else r for r in records]
    return {"version": 1, "records": swapped}


@pytest.mark.parametrize(
    "previous_id, new_id",
    [
        ("atp:barnes_and_noble_us:104", "atp:barnes_and_noble_us:100"),  # same brand
        ("atp:giant_food_us:#0900", "atp:food_lion_us:900"),  # same parent company
        ("atp:sunoco_us:8003437499", "atp:seven_eleven_ca_us:40063_SHOP"),  # fuel sold at a 7-Eleven
    ],
    ids=["same brand", "same parent", "fuel at a 7-eleven"],
)
def test_a_record_from_the_previous_seed_keeps_winning_its_duplicate_cluster(tmp_path, bundled_seed, previous_id, new_id):
    output = tmp_path / "seed.json"
    first = by_id(run(output))
    assert new_id in first and previous_id not in first  # the lowest ID wins without a previous seed

    # The previous seed shipped previous_id; new_id is a listing that appeared since.
    bundled_seed.write_text(json.dumps(previous_with(list(first.values()), new_id, previous_id)))
    second = by_id(run(output))
    assert previous_id in second
    assert new_id not in second
    assert second.keys() - {previous_id} == first.keys() - {new_id}


def test_run_history_is_fetched_once_per_run(monkeypatch):
    history = [{"run_id": "2026-10-17", "stats_url": "stats", "output_url": "https://example/runs/x/output.zip"}]
    fetched = Counter()

    def fake_fetch(url, **_):
        fetched[url] += 1
        if url == build_seed.ATP_RUN_HISTORY:
            return history
        if url == "stats":
            return {"results": [{"spider": s.spider, "features": 10**6} for s in build_seed.SOURCES if isinstance(s, build_seed.AtpSource)]}
        return {"features": []}

    monkeypatch.setattr(build_seed, "fetch_json", fake_fetch)
    build_seed.run_history.cache_clear()
    build_seed.run_feature_counts.cache_clear()
    for source in build_seed.SOURCES[:3]:
        source.load(None)
    assert fetched[build_seed.ATP_RUN_HISTORY] == 1
    build_seed.run_history.cache_clear()
    build_seed.run_feature_counts.cache_clear()


class FakeResponse(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()


def fake_network(monkeypatch, answers: list):
    """Makes urlopen return or raise each answer in turn, and records sleeps instead of sleeping."""
    calls, sleeps = [], []

    def urlopen(request, timeout):
        calls.append(request.full_url)
        answer = answers[len(calls) - 1]
        if isinstance(answer, Exception):
            raise answer
        return FakeResponse(json.dumps(answer).encode())

    monkeypatch.setattr(build_seed.urllib.request, "urlopen", urlopen)
    monkeypatch.setattr(build_seed.time, "sleep", sleeps.append)
    return calls, sleeps


def http_error(code: int) -> urllib.error.HTTPError:
    return urllib.error.HTTPError("https://example/x", code, "error", {}, None)


def test_fetch_retries_transient_failures_with_backoff(monkeypatch):
    calls, sleeps = fake_network(monkeypatch, [http_error(503), urllib.error.URLError("reset"), http_error(429), {"ok": 1}])
    assert build_seed.fetch_json("https://example/x") == {"ok": 1}
    assert len(calls) == 4
    assert sleeps == sorted(sleeps) and len(sleeps) == 3 and sleeps[0] < sleeps[-1]


def test_fetch_retries_an_interrupted_download(monkeypatch):
    calls, _ = fake_network(monkeypatch, [http.client.IncompleteRead(b"{"), {"ok": 1}])
    assert build_seed.fetch_json("https://example/x") == {"ok": 1}
    assert len(calls) == 2


def test_fetch_retries_an_overpass_remark(monkeypatch):
    calls, _ = fake_network(monkeypatch, [{"remark": "runtime error: timeout", "elements": []}, {"elements": [1]}])
    assert build_seed.fetch_json("https://example/x", data=b"q") == {"elements": [1]}
    assert len(calls) == 2


def test_fetch_does_not_sleep_after_the_last_attempt(monkeypatch):
    calls, sleeps = fake_network(monkeypatch, [http_error(503)] * build_seed.FETCH_ATTEMPTS)
    with pytest.raises(SystemExit) as exit:
        build_seed.fetch_json("https://example/x")
    assert "https://example/x" in str(exit.value.code)
    assert len(calls) == build_seed.FETCH_ATTEMPTS
    assert len(sleeps) == build_seed.FETCH_ATTEMPTS - 1


@pytest.mark.parametrize("code", [400, 403, 404])
def test_fetch_does_not_retry_client_errors(monkeypatch, code):
    calls, sleeps = fake_network(monkeypatch, [http_error(code), {"ok": 1}])
    with pytest.raises(SystemExit):
        build_seed.fetch_json("https://example/x")
    assert len(calls) == 1
    assert sleeps == []
