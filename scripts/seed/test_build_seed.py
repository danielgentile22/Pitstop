import json
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
