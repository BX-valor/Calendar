#!/usr/bin/env python3
"""
Fetch CCF conference deadlines from paperswithcode/ai-deadlines and generate
Sources/ConferenceDeadline/Resources/conferences.json.

You must verify the generated dates against each conference's official website,
especially finalDecisionDate and rebuttalDeadline, which are not provided by
ai-deadlines.
"""

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import urlopen

try:
    import yaml
except ImportError:
    print("Error: PyYAML is required. Install it with:")
    print("  pip3 install pyyaml")
    sys.exit(1)

TARGET_CONFERENCES = {
    # CCF-A
    "NeurIPS",
    "ICML",
    "ICLR",
    "CVPR",
    "ICCV",
    "ECCV",
    "ACL",
    "EMNLP",
    "NAACL",
    "MM",
    "ACM MM",
    "ACMMM",
    "AAAI",
    "IJCAI",
    "KDD",
    "WWW",
    "SIGIR",
    # CCF-B
    "WACV",
    "BMVC",
    "COLING",
    "CIKM",
}

# CCF rating tags for target conferences (based on CCF 2022 directory).
CCF_RATINGS = {
    # CCF-A (AI)
    "NeurIPS": "CCF-A",
    "ICML": "CCF-A",
    "ICLR": "CCF-A",
    "CVPR": "CCF-A",
    "ICCV": "CCF-A",
    "ACL": "CCF-A",
    "EMNLP": "CCF-A",
    "ACM MM": "CCF-A",
    "AAAI": "CCF-A",
    "ACM MM": "CCF-A",
    "KDD": "CCF-A",
    "WWW": "CCF-A",
    "SIGIR": "CCF-A",
    # CCF-B (AI)
    "ECCV": "CCF-B",
    "NAACL": "CCF-B",
    "IJCAI": "CCF-B",
    "WACV": "CCF-B",
    "BMVC": "CCF-B",
    "COLING": "CCF-B",
    "CIKM": "CCF-B",
}

DATA_SOURCE = (
    "https://raw.githubusercontent.com/paperswithcode/ai-deadlines/gh-pages/"
    "_data/conferences.yml"
)

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_PATH = (
    REPO_ROOT
    / "Sources"
    / "ConferenceDeadline"
    / "Resources"
    / "conferences.json"
)
REPORT_PATH = REPO_ROOT / "scripts" / "fetch_deadlines_report.md"


def normalize_title(title: str) -> str:
    """Return a canonical short name for matching."""
    title = title.strip()
    # Common aliases
    if title.upper() in {"MM", "ACMMM", "ACM MM", "ACM MULTIMEDIA"}:
        return "ACM MM"
    return title


def matches_target(conf: dict) -> bool:
    title = normalize_title(conf.get("title", ""))
    if title in TARGET_CONFERENCES:
        return True
    # Also match by substring for ECCV, ACL, etc.
    for target in TARGET_CONFERENCES:
        if title.upper() == target.upper():
            return True
    return False


def parse_datetime(value, timezone_str: str | None) -> datetime | None:
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None

    # Common formats in ai-deadlines: "2024-11-15 06:59:59" or "2024-11-15 06:59"
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M"):
        try:
            dt = datetime.strptime(text, fmt)
        except ValueError:
            continue

        tz = _parse_timezone(timezone_str)
        return dt.replace(tzinfo=tz)

    return None


def _parse_timezone(tz_str: str | None) -> timezone:
    if not tz_str:
        return timezone.utc

    tz_str = tz_str.strip().upper()

    # AoE = UTC-12
    if tz_str == "UTC-12":
        return timezone(offset=-__hours(12))
    if tz_str == "UTC-11":
        return timezone(offset=-__hours(11))
    if tz_str == "UTC-10":
        return timezone(offset=-__hours(10))
    if tz_str == "UTC-9":
        return timezone(offset=-__hours(9))
    if tz_str == "UTC-8":
        return timezone(offset=-__hours(8))
    if tz_str == "UTC-7":
        return timezone(offset=-__hours(7))
    if tz_str == "UTC-6":
        return timezone(offset=-__hours(6))
    if tz_str == "UTC-5":
        return timezone(offset=-__hours(5))
    if tz_str == "UTC-4":
        return timezone(offset=-__hours(4))
    if tz_str == "UTC-3":
        return timezone(offset=-__hours(3))
    if tz_str == "UTC-2":
        return timezone(offset=-__hours(2))
    if tz_str == "UTC-1":
        return timezone(offset=-__hours(1))
    if tz_str in {"UTC", "UTC+0", "GMT", "UTC0"}:
        return timezone.utc
    if tz_str == "UTC+1":
        return timezone(offset=__hours(1))
    if tz_str == "UTC+2":
        return timezone(offset=__hours(2))
    if tz_str == "UTC+3":
        return timezone(offset=__hours(3))
    if tz_str == "UTC+4":
        return timezone(offset=__hours(4))
    if tz_str == "UTC+5":
        return timezone(offset=__hours(5))
    if tz_str == "UTC+6":
        return timezone(offset=__hours(6))
    if tz_str == "UTC+7":
        return timezone(offset=__hours(7))
    if tz_str == "UTC+8":
        return timezone(offset=__hours(8))
    if tz_str == "UTC+9":
        return timezone(offset=__hours(9))
    if tz_str == "UTC+10":
        return timezone(offset=__hours(10))
    if tz_str == "UTC+11":
        return timezone(offset=__hours(11))
    if tz_str == "UTC+12":
        return timezone(offset=__hours(12))

    # PDT/PST style
    if tz_str in {"PDT"}:
        return timezone(offset=-__hours(7))
    if tz_str in {"PST"}:
        return timezone(offset=-__hours(8))

    return timezone.utc


def __hours(h: int):
    from datetime import timedelta
    return timedelta(hours=h)


def parse_date(value) -> datetime | None:
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    try:
        dt = datetime.strptime(text, "%Y-%m-%d")
        return dt.replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def iso_format(dt: datetime | None) -> str | None:
    if dt is None:
        return None
    return dt.isoformat()


def build_id(name: str, year: int) -> str:
    clean = re.sub(r"[^a-zA-Z0-9]", "", name).lower()
    return f"{clean}{year}"


def transform(conf: dict) -> dict | None:
    title = normalize_title(conf.get("title", ""))
    year = conf.get("year")
    if not year:
        return None

    tz = conf.get("timezone")
    abstract_dt = parse_datetime(conf.get("abstract_deadline"), tz)
    paper_dt = parse_datetime(conf.get("deadline"), tz)
    if not paper_dt:
        return None

    # Fallback: if abstract_deadline is missing, use paper deadline minus 7 days.
    if not abstract_dt:
        abstract_dt = paper_dt

    conference_start = parse_date(conf.get("start"))
    conference_end = parse_date(conf.get("end"))
    conference_date = conference_start

    tags = [CCF_RATINGS.get(title, "CCF-C")]
    location = _location(conf.get("place"))

    result = {
        "id": build_id(title, year),
        "name": title,
        "year": year,
        "category": _category(conf.get("sub")),
        "abstractDeadline": iso_format(abstract_dt),
        "paperDeadline": iso_format(paper_dt),
        "rebuttalDeadline": None,
        "finalDecisionDate": None,
        "conferenceDate": iso_format(conference_date),
        "location": location,
        "venue": None,
        "website": conf.get("link"),
        "timezone": tz,
        "tags": tags,
    }
    return result


def _category(sub) -> str | None:
    if isinstance(sub, list):
        return sub[0] if sub else None
    if isinstance(sub, str):
        return sub
    return None


def _location(place) -> str | None:
    if not place:
        return None
    text = str(place).strip()
    if not text or text.lower() in {"tbd", "to be determined", "online", "virtual"}:
        return None
    return text


def deduplicate(conferences: list[dict]) -> list[dict]:
    """Keep only the most recent year for each conference name."""
    by_name: dict[str, dict] = {}
    for conf in conferences:
        name = conf["name"]
        if name not in by_name or conf["year"] > by_name[name]["year"]:
            by_name[name] = conf
    return sorted(by_name.values(), key=lambda c: (c["name"], c["year"]))


def main() -> int:
    print(f"Fetching {DATA_SOURCE} ...")
    with urlopen(DATA_SOURCE) as response:
        raw = response.read().decode("utf-8")

    data = yaml.safe_load(raw)
    if not isinstance(data, list):
        print("Unexpected YAML structure.")
        return 1

    matched = [transform(conf) for conf in data if matches_target(conf)]
    matched = [m for m in matched if m is not None]
    matched = deduplicate(matched)

    if not matched:
        print("No target conferences found.")
        return 1

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT_PATH.open("w", encoding="utf-8") as f:
        json.dump(matched, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"Wrote {len(matched)} conferences to {OUTPUT_PATH}")

    report_lines = [
        "# Conference Deadline Fetch Report\n",
        f"Source: {DATA_SOURCE}\n",
        f"Generated: {datetime.now(timezone.utc).isoformat()}\n\n",
        "## Fetched conferences\n",
    ]
    for conf in matched:
        report_lines.append(
            f"- **{conf['name']} {conf['year']}**: "
            f"abstract={conf['abstractDeadline']}, "
            f"paper={conf['paperDeadline']}\n"
        )

    report_lines.extend([
        "\n## Manual verification required\n",
        "ai-deadlines does not provide rebuttal or final decision dates. "
        "Please visit each conference's official website and update the JSON:\n\n",
    ])
    for conf in matched:
        report_lines.append(
            f"- [{conf['name']} {conf['year']}]({conf['website']}): "
            f"verify `rebuttalDeadline` and `finalDecisionDate`\n"
        )

    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with REPORT_PATH.open("w", encoding="utf-8") as f:
        f.writelines(report_lines)

    print(f"Wrote verification report to {REPORT_PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
