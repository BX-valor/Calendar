#!/usr/bin/env python3
"""
Fetch CCF conference deadlines from paperswithcode/ai-deadlines and generate
Sources/ConferenceDeadline/Resources/conferences.json.

This script uses the CCF 7th edition (2026) AI and Database/Data Mining/Content
Retrieval conference lists as the authoritative source for names, ratings and
categories. It then tries to obtain the latest deadline for each conference from
ai-deadlines, falling back to the existing conferences.json for conferences not
listed by ai-deadlines. Conferences without any known deadline are omitted.

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

# ---------------------------------------------------------------------------
# CCF 7th edition (2026) conference directory
# ---------------------------------------------------------------------------
# Maps canonical short name -> {full_name, rating, category, aliases}
#
# Categories:
#   AI       General artificial intelligence / planning / reasoning / agents
#   ML       Machine learning / neural networks / learning theory
#   CV       Computer vision / pattern recognition
#   NLP      Natural language processing / computational linguistics
#   Robotics Robotics conferences
#   DM       Data mining
#   IR       Information retrieval / recommender systems / semantic web
#   DB       Database systems
#
# Aliases are used to match entries in the ai-deadlines dataset.
CCF_CONFERENCES: dict[str, dict] = {
    # ---- A 类 ----
    "AAAI": {
        "full_name": "AAAI Conference on Artificial Intelligence",
        "rating": "CCF-A",
        "category": "AI",
        "aliases": {"AAAI"},
    },
    "NeurIPS": {
        "full_name": "Conference on Neural Information Processing Systems",
        "rating": "CCF-A",
        "category": "ML",
        "aliases": {"NeurIPS", "NIPS"},
    },
    "ACL": {
        "full_name": "Annual Meeting of the Association for Computational Linguistics",
        "rating": "CCF-A",
        "category": "NLP",
        "aliases": {"ACL"},
    },
    "CVPR": {
        "full_name": "IEEE/CVF Computer Vision and Pattern Recognition Conference",
        "rating": "CCF-A",
        "category": "CV",
        "aliases": {"CVPR"},
    },
    "ICCV": {
        "full_name": "International Conference on Computer Vision",
        "rating": "CCF-A",
        "category": "CV",
        "aliases": {"ICCV"},
    },
    "ICML": {
        "full_name": "International Conference on Machine Learning",
        "rating": "CCF-A",
        "category": "ML",
        "aliases": {"ICML"},
    },
    "ICLR": {
        "full_name": "International Conference on Learning Representations",
        "rating": "CCF-A",
        "category": "ML",
        "aliases": {"ICLR"},
    },

    # ---- B 类 ----
    "COLT": {
        "full_name": "Annual Conference on Computational Learning Theory",
        "rating": "CCF-B",
        "category": "ML",
        "aliases": {"COLT"},
    },
    "EMNLP": {
        "full_name": "Conference on Empirical Methods in Natural Language Processing",
        "rating": "CCF-B",
        "category": "NLP",
        "aliases": {"EMNLP"},
    },
    "ECAI": {
        "full_name": "European Conference on Artificial Intelligence",
        "rating": "CCF-B",
        "category": "AI",
        "aliases": {"ECAI"},
    },
    "ECCV": {
        "full_name": "European Conference on Computer Vision",
        "rating": "CCF-B",
        "category": "CV",
        "aliases": {"ECCV"},
    },
    "ICRA": {
        "full_name": "IEEE International Conference on Robotics and Automation",
        "rating": "CCF-B",
        "category": "Robotics",
        "aliases": {"ICRA"},
    },
    "ICAPS": {
        "full_name": "International Conference on Automated Planning and Scheduling",
        "rating": "CCF-B",
        "category": "AI",
        "aliases": {"ICAPS"},
    },
    "ICCBR": {
        "full_name": "International Conference on Case-Based Reasoning",
        "rating": "CCF-B",
        "category": "AI",
        "aliases": {"ICCBR"},
    },
    "COLING": {
        "full_name": "International Conference on Computational Linguistics",
        "rating": "CCF-B",
        "category": "NLP",
        "aliases": {"COLING", "LREC-COLING"},
    },
    "KR": {
        "full_name": "International Conference on Principles of Knowledge Representation and Reasoning",
        "rating": "CCF-B",
        "category": "AI",
        "aliases": {"KR"},
    },
    "UAI": {
        "full_name": "Conference on Uncertainty in Artificial Intelligence",
        "rating": "CCF-B",
        "category": "ML",
        "aliases": {"UAI"},
    },
    "AAMAS": {
        "full_name": "International Joint Conference on Autonomous Agents and Multi-agent Systems",
        "rating": "CCF-B",
        "category": "AI",
        "aliases": {"AAMAS"},
    },
    "PPSN": {
        "full_name": "Parallel Problem Solving from Nature",
        "rating": "CCF-B",
        "category": "ML",
        "aliases": {"PPSN"},
    },
    "NAACL": {
        "full_name": "North American Chapter of the Association for Computational Linguistics",
        "rating": "CCF-B",
        "category": "NLP",
        "aliases": {"NAACL"},
    },
    "IJCAI": {
        "full_name": "International Joint Conference on Artificial Intelligence",
        "rating": "CCF-B",
        "category": "AI",
        "aliases": {"IJCAI", "IJCAI-ECAI"},
    },

    # ---- C 类 ----
    "AISTATS": {
        "full_name": "International Conference on Artificial Intelligence and Statistics",
        "rating": "CCF-C",
        "category": "ML",
        "aliases": {"AISTATS"},
    },
    "ACCV": {
        "full_name": "Asian Conference on Computer Vision",
        "rating": "CCF-C",
        "category": "CV",
        "aliases": {"ACCV"},
    },
    "ACML": {
        "full_name": "Asian Conference on Machine Learning",
        "rating": "CCF-C",
        "category": "ML",
        "aliases": {"ACML"},
    },
    "BMVC": {
        "full_name": "British Machine Vision Conference",
        "rating": "CCF-C",
        "category": "CV",
        "aliases": {"BMVC"},
    },
    "NLPCC": {
        "full_name": "CCF International Conference on Natural Language Processing and Chinese Computing",
        "rating": "CCF-C",
        "category": "NLP",
        "aliases": {"NLPCC"},
    },
    "CoNLL": {
        "full_name": "Conference on Computational Natural Language Learning",
        "rating": "CCF-C",
        "category": "NLP",
        "aliases": {"CoNLL"},
    },
    "GECCO": {
        "full_name": "Genetic and Evolutionary Computation Conference",
        "rating": "CCF-C",
        "category": "ML",
        "aliases": {"GECCO"},
    },
    "ICTAI": {
        "full_name": "IEEE International Conference on Tools with Artificial Intelligence",
        "rating": "CCF-C",
        "category": "AI",
        "aliases": {"ICTAI"},
    },
    "IROS": {
        "full_name": "IEEE/RSJ International Conference on Intelligent Robots and Systems",
        "rating": "CCF-C",
        "category": "Robotics",
        "aliases": {"IROS"},
    },
    "ALT": {
        "full_name": "International Conference on Algorithmic Learning Theory",
        "rating": "CCF-C",
        "category": "ML",
        "aliases": {"ALT"},
    },
    "ICANN": {
        "full_name": "International Conference on Artificial Neural Networks",
        "rating": "CCF-C",
        "category": "ML",
        "aliases": {"ICANN"},
    },
    "FG": {
        "full_name": "IEEE International Conference on Automatic Face and Gesture Recognition",
        "rating": "CCF-C",
        "category": "CV",
        "aliases": {"FG", "IEEE FG"},
    },
    "ICDAR": {
        "full_name": "International Conference on Document Analysis and Recognition",
        "rating": "CCF-C",
        "category": "CV",
        "aliases": {"ICDAR"},
    },
    "ILP": {
        "full_name": "International Conference on Inductive Logic Programming",
        "rating": "CCF-C",
        "category": "AI",
        "aliases": {"ILP"},
    },
    "KSEM": {
        "full_name": "International Conference on Knowledge Science, Engineering and Management",
        "rating": "CCF-C",
        "category": "AI",
        "aliases": {"KSEM"},
    },
    "ICONIP": {
        "full_name": "International Conference on Neural Information Processing",
        "rating": "CCF-C",
        "category": "ML",
        "aliases": {"ICONIP"},
    },
    "ICPR": {
        "full_name": "International Conference on Pattern Recognition",
        "rating": "CCF-C",
        "category": "CV",
        "aliases": {"ICPR"},
    },
    "IJCB": {
        "full_name": "International Joint Conference on Biometrics",
        "rating": "CCF-C",
        "category": "CV",
        "aliases": {"IJCB"},
    },
    "IJCNN": {
        "full_name": "International Joint Conference on Neural Networks",
        "rating": "CCF-C",
        "category": "ML",
        "aliases": {"IJCNN"},
    },
    "PRICAI": {
        "full_name": "Pacific Rim International Conference on Artificial Intelligence",
        "rating": "CCF-C",
        "category": "AI",
        "aliases": {"PRICAI"},
    },
    "IEEE CEC": {
        "full_name": "Congress on Evolutionary Computation",
        "rating": "CCF-C",
        "category": "ML",
        "aliases": {"IEEE CEC", "CEC"},
    },
    "DAI": {
        "full_name": "International Conference on Distributed Artificial Intelligence",
        "rating": "CCF-C",
        "category": "AI",
        "aliases": {"DAI"},
    },

    # ---- 计算机图形学与多媒体（额外保留） ----
    "ACM MM": {
        "full_name": "ACM International Conference on Multimedia",
        "rating": "CCF-A",
        "category": "MM",
        "aliases": {"ACM MM", "MM", "ACMMM", "ACM MULTIMEDIA"},
    },

    # ---- 数据库/数据挖掘/内容检索 ----
    # A 类
    "SIGMOD": {
        "full_name": "ACM SIGMOD Conference",
        "rating": "CCF-A",
        "category": "DB",
        "aliases": {"SIGMOD"},
    },
    "KDD": {
        "full_name": "ACM SIGKDD Conference on Knowledge Discovery and Data Mining",
        "rating": "CCF-A",
        "category": "DM",
        "aliases": {"KDD", "SIGKDD"},
    },
    "ICDE": {
        "full_name": "IEEE International Conference on Data Engineering",
        "rating": "CCF-A",
        "category": "DB",
        "aliases": {"ICDE"},
    },
    "SIGIR": {
        "full_name": "International ACM SIGIR Conference on Research and Development in Information Retrieval",
        "rating": "CCF-A",
        "category": "IR",
        "aliases": {"SIGIR", "SIGIR-AP"},
    },
    "VLDB": {
        "full_name": "International Conference on Very Large Data Bases",
        "rating": "CCF-A",
        "category": "DB",
        "aliases": {"VLDB"},
    },

    # B 类
    "CIKM": {
        "full_name": "ACM International Conference on Information and Knowledge Management",
        "rating": "CCF-B",
        "category": "IR",
        "aliases": {"CIKM"},
    },
    "WSDM": {
        "full_name": "ACM International Conference on Web Search and Data Mining",
        "rating": "CCF-B",
        "category": "IR",
        "aliases": {"WSDM"},
    },
    "PODS": {
        "full_name": "ACM SIGMOD-SIGACT-SIGAI Symposium on Principles of Database Systems",
        "rating": "CCF-B",
        "category": "DB",
        "aliases": {"PODS"},
    },
    "DASFAA": {
        "full_name": "International Conference on Database Systems for Advanced Applications",
        "rating": "CCF-B",
        "category": "DB",
        "aliases": {"DASFAA"},
    },
    "ECML-PKDD": {
        "full_name": "European Conference on Machine Learning and Principles and Practice of Knowledge Discovery in Databases",
        "rating": "CCF-B",
        "category": "DM",
        "aliases": {"ECML-PKDD", "ECML PKDD", "ECML/PKDD"},
    },
    "ISWC": {
        "full_name": "IEEE International Semantic Web Conference",
        "rating": "CCF-B",
        "category": "IR",
        "aliases": {"ISWC"},
    },
    "ICDM": {
        "full_name": "IEEE International Conference on Data Mining",
        "rating": "CCF-B",
        "category": "DM",
        "aliases": {"ICDM"},
    },
    "ICDT": {
        "full_name": "International Conference on Database Theory",
        "rating": "CCF-B",
        "category": "DB",
        "aliases": {"ICDT"},
    },
    "EDBT": {
        "full_name": "International Conference on Extending Database Technology",
        "rating": "CCF-B",
        "category": "DB",
        "aliases": {"EDBT"},
    },
    "CIDR": {
        "full_name": "Conference on Innovative Data Systems Research",
        "rating": "CCF-B",
        "category": "DB",
        "aliases": {"CIDR"},
    },
    "SDM": {
        "full_name": "SIAM International Conference on Data Mining",
        "rating": "CCF-B",
        "category": "DM",
        "aliases": {"SDM"},
    },
    "RecSys": {
        "full_name": "ACM Conference on Recommender Systems",
        "rating": "CCF-B",
        "category": "IR",
        "aliases": {"RecSys"},
    },
    "WISE": {
        "full_name": "Web Information Systems Engineering Conference",
        "rating": "CCF-B",
        "category": "IR",
        "aliases": {"WISE"},
    },

    # C 类
    "APWeb": {
        "full_name": "Asia Pacific Web Conference",
        "rating": "CCF-C",
        "category": "DB",
        "aliases": {"APWeb"},
    },
    "DEXA": {
        "full_name": "International Conference on Database and Expert System Applications",
        "rating": "CCF-C",
        "category": "DB",
        "aliases": {"DEXA"},
    },
    "ECIR": {
        "full_name": "European Conference on Information Retrieval",
        "rating": "CCF-C",
        "category": "IR",
        "aliases": {"ECIR"},
    },
    "ESWC": {
        "full_name": "Extended Semantic Web Conference",
        "rating": "CCF-C",
        "category": "IR",
        "aliases": {"ESWC"},
    },
    "WebDB": {
        "full_name": "International Workshop on Web and Databases",
        "rating": "CCF-C",
        "category": "IR",
        "aliases": {"WebDB"},
    },
    "ER": {
        "full_name": "International Conference on Conceptual Modeling",
        "rating": "CCF-C",
        "category": "DB",
        "aliases": {"ER"},
    },
    "MDM": {
        "full_name": "International Conference on Mobile Data Management",
        "rating": "CCF-C",
        "category": "DB",
        "aliases": {"MDM"},
    },
    "SSDBM": {
        "full_name": "International Conference on Scientific and Statistical Database Management",
        "rating": "CCF-C",
        "category": "DB",
        "aliases": {"SSDBM"},
    },
    "WAIM": {
        "full_name": "International Conference on Web Age Information Management",
        "rating": "CCF-C",
        "category": "DB",
        "aliases": {"WAIM"},
    },
    "SSTD": {
        "full_name": "International Symposium on Spatial and Temporal Databases",
        "rating": "CCF-C",
        "category": "DB",
        "aliases": {"SSTD"},
    },
    "PAKDD": {
        "full_name": "Pacific-Asia Conference on Knowledge Discovery and Data Mining",
        "rating": "CCF-C",
        "category": "DM",
        "aliases": {"PAKDD"},
    },
    "ADMA": {
        "full_name": "International Conference on Advanced Data Mining and Applications",
        "rating": "CCF-C",
        "category": "DM",
        "aliases": {"ADMA"},
    },
    "WISA": {
        "full_name": "Web Information Systems and Applications",
        "rating": "CCF-C",
        "category": "IR",
        "aliases": {"WISA"},
    },
}

# Only keep conference entries whose year is >= MIN_YEAR. This avoids polluting
# the app with stale deadlines for conferences that have already taken place.
MIN_YEAR = 2025

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


def _build_alias_map() -> dict[str, str]:
    """Return a map from every alias to the canonical CCF short name."""
    alias_map: dict[str, str] = {}
    for canonical, info in CCF_CONFERENCES.items():
        for alias in info.get("aliases", {canonical}):
            alias_map[alias.upper()] = canonical
        alias_map[canonical.upper()] = canonical
    return alias_map


ALIAS_MAP = _build_alias_map()


def normalize_title(title: str) -> str | None:
    """Map an ai-deadlines or existing-json title to a canonical CCF name."""
    if not title:
        return None

    # Remove bracketed sub-tracks, e.g. "NeurIPS [Dataset and Benchmarks Track]"
    cleaned = re.split(r"\s*[\[(]", title.strip())[0].strip()
    # Remove trailing year numbers
    cleaned = re.sub(r"\s+20\d{2}$", "", cleaned)

    # Direct alias match (case-insensitive)
    upper = cleaned.upper()
    if upper in ALIAS_MAP:
        return ALIAS_MAP[upper]

    # Strip common prefixes/suffixes and retry
    stripped = re.sub(r"^(IEEE|ACM|SIAM|International)\s+", "", cleaned, flags=re.I)
    upper2 = stripped.upper()
    if upper2 in ALIAS_MAP:
        return ALIAS_MAP[upper2]

    return None


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
    if tz_str == "UTC-12" or tz_str == "AOE":
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


def _location(place) -> str | None:
    if not place:
        return None
    text = str(place).strip()
    if not text or text.lower() in {"tbd", "to be determined", "online", "virtual"}:
        return None
    return text


def transform_ai_deadline(conf: dict, canonical_name: str) -> dict | None:
    """Convert an ai-deadlines entry to the app's conference JSON format."""
    year = conf.get("year")
    if not year:
        return None

    tz = conf.get("timezone")
    abstract_dt = parse_datetime(conf.get("abstract_deadline"), tz)
    paper_dt = parse_datetime(conf.get("deadline"), tz)
    if not paper_dt:
        return None

    # Fallback: if abstract_deadline is missing, use paper deadline.
    if not abstract_dt:
        abstract_dt = paper_dt

    conference_start = parse_date(conf.get("start"))
    ccf_info = CCF_CONFERENCES[canonical_name]

    return {
        "id": build_id(canonical_name, year),
        "name": canonical_name,
        "year": year,
        "category": ccf_info["category"],
        "abstractDeadline": iso_format(abstract_dt),
        "paperDeadline": iso_format(paper_dt),
        "rebuttalDeadline": None,
        "finalDecisionDate": None,
        "conferenceDate": iso_format(conference_start),
        "location": _location(conf.get("place")),
        "venue": None,
        "website": conf.get("link"),
        "timezone": tz,
        "tags": [ccf_info["rating"]],
    }


def normalize_existing_entry(entry: dict) -> dict | None:
    """Re-tag an existing conferences.json entry using the CCF directory."""
    name = entry.get("name", "")
    canonical = normalize_title(name)
    if canonical is None:
        return None

    ccf_info = CCF_CONFERENCES[canonical]
    entry = dict(entry)
    entry["name"] = canonical
    entry["category"] = ccf_info["category"]
    entry["tags"] = [ccf_info["rating"]]
    # Rebuild id to match the canonical name/year
    entry["id"] = build_id(canonical, entry.get("year", 0))
    return entry


def fetch_ai_deadlines() -> dict[str, dict]:
    """Fetch ai-deadlines and return the latest entry per canonical CCF name."""
    print(f"Fetching {DATA_SOURCE} ...")
    with urlopen(DATA_SOURCE) as response:
        raw = response.read().decode("utf-8")
    data = yaml.safe_load(raw)

    latest_by_name: dict[str, dict] = {}
    for conf in data:
        title = conf.get("title", "")
        canonical = normalize_title(title)
        if canonical is None:
            continue

        year = conf.get("year")
        if not year:
            continue

        paper_dt = parse_datetime(conf.get("deadline"), conf.get("timezone"))
        if not paper_dt:
            continue

        current = latest_by_name.get(canonical)
        if current is None or year > current["year"]:
            latest_by_name[canonical] = conf

    return latest_by_name


def load_existing_conferences() -> dict[str, dict]:
    """Load existing conferences.json, re-tag by CCF directory, keyed by name."""
    if not OUTPUT_PATH.exists():
        return {}

    with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)

    by_name: dict[str, dict] = {}
    for entry in data:
        normalized = normalize_existing_entry(entry)
        if normalized is None:
            continue
        name = normalized["name"]
        current = by_name.get(name)
        if current is None or normalized.get("year", 0) > current.get("year", 0):
            by_name[name] = normalized

    return by_name


def generate_report(
    fetched: dict[str, dict],
    used_existing_count: int,
    merged: list[dict],
    missing: list[str],
) -> str:
    lines = [
        "# Conference Deadline Fetch Report",
        "",
        f"Generated: {datetime.now(timezone.utc).isoformat()}",
        "",
        "## Summary",
        "",
        f"- Total CCF AI + DM/IR conferences: {len(CCF_CONFERENCES)}",
        f"- Matched from ai-deadlines: {len(fetched)}",
        f"- Backfilled from existing JSON: {used_existing_count}",
        f"- Final conferences with deadlines: {len(merged)}",
        f"- Missing deadlines (omitted): {len(missing)}",
        "",
        "## Conferences with deadlines",
        "",
    ]
    for conf in sorted(merged, key=lambda c: (c["category"], c["name"])):
        deadline = conf.get("paperDeadline") or "N/A"
        lines.append(
            f"- **{conf['name']}** ({conf['year']}) — {conf['category']} — "
            f"{conf['tags'][0]} — deadline: {deadline}"
        )

    lines += ["", "## Conferences without known deadlines (omitted)", ""]
    for name in sorted(missing):
        info = CCF_CONFERENCES[name]
        lines.append(f"- {name} — {info['category']} — {info['rating']}")

    return "\n".join(lines) + "\n"


def main() -> int:
    latest_fetched = fetch_ai_deadlines()
    existing_by_name = load_existing_conferences()

    merged_by_name: dict[str, dict] = {}
    missing: list[str] = []
    used_existing_count = 0

    for canonical, info in CCF_CONFERENCES.items():
        fetched_entry = None
        if canonical in latest_fetched:
            fetched_entry = transform_ai_deadline(latest_fetched[canonical], canonical)

        existing_entry = existing_by_name.get(canonical)

        chosen = None
        if fetched_entry and existing_entry:
            # Prefer the entry with the latest year (i.e. the most recent deadline).
            if fetched_entry["year"] >= existing_entry["year"]:
                chosen = fetched_entry
            else:
                chosen = existing_entry
                used_existing_count += 1
        elif fetched_entry:
            chosen = fetched_entry
        elif existing_entry:
            chosen = existing_entry
            used_existing_count += 1
        else:
            missing.append(canonical)
            continue

        # Drop stale entries for conferences that already took place before MIN_YEAR.
        if chosen["year"] < MIN_YEAR:
            missing.append(canonical)
            continue

        merged_by_name[canonical] = chosen

    merged = sorted(
        merged_by_name.values(),
        key=lambda c: (c["category"], c["name"], c["year"]),
    )

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(merged, f, ensure_ascii=False, indent=2)
    print(f"Wrote {len(merged)} conferences to {OUTPUT_PATH}")

    report = generate_report(
        latest_fetched, used_existing_count, merged, missing
    )
    with open(REPORT_PATH, "w", encoding="utf-8") as f:
        f.write(report)
    print(f"Wrote report to {REPORT_PATH}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
