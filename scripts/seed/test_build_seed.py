import json
import re
from pathlib import Path

import pytest

import build_seed

FIXTURES = Path(__file__).parent / "fixtures"


def run(output: Path) -> dict:
    build_seed.main(["--fixtures", str(FIXTURES), "--output", str(output)])
    return json.loads(output.read_text())


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


def test_version_bumps_only_when_records_change(tmp_path):
    output = tmp_path / "seed.json"
    first = run(output)
    assert first["version"] == 1
    assert run(output)["version"] == 1

    stale = json.loads(output.read_text())
    stale["records"] = stale["records"][1:]
    output.write_text(json.dumps(stale))
    assert run(output)["version"] == 2


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
