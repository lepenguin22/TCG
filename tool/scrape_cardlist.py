"""Reads sets from Bushiroad's official English card list.

The card database is generated from a community mirror whose scrape stopped
at DZ-BT09, so every card from a newer set is missing -- which is what an
imported deck reports as cards it cannot match or check. This fetches the
sets the mirror does not have, straight from the source, and writes them in
the same shape the mirror uses so the generator can read both.

The site answers 404 to a bare request; it wants a browser's headers. That is
the whole reason it looked as though it had moved.

Run from CI, where the site is reachable:
    python3 tool/scrape_cardlist.py [--limit N] [--expansion N]
"""

from __future__ import annotations

import argparse
import collections
import gzip
import io
import json
import pathlib
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

SITE = "https://en.cf-vanguard.com"
INDEX = f"{SITE}/cardlist/"
# Deliberately not under assets/: pubspec bundles that whole directory into
# the app, and this is the scraper's working data, read by the generator and
# never by the app itself.
OUT = pathlib.Path("data/cardlist/extra_sets.json")

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "Accept-Encoding": "gzip, deflate",
}

# The six nations the D-series introduced. A card page lists its nation and
# its race on separate lines, and older cards carry a clan there instead, so
# knowing the nations is what tells the lines apart.
NATIONS = {
    "Dragon Empire",
    "Dark States",
    "Brandt Gate",
    "Keter Sanctuary",
    "Stoicheia",
    "Lyrical Monasterio",
}

# A stat line is a label and a number. The value has to be pinned down like
# that because "Critical Trigger +10000" begins with a stat's name without
# being one -- read as a Critical stat, it swallowed every critical trigger
# on the site.
STAT_LINE = re.compile(r"(Grade|Power|Critical|Shield)\s*([-\u2013\d][^A-Za-z]*)?")

# Lines that are an ability marker rather than a value, so a parser walking
# the block knows where the stats stop.
ABILITY_WORDS = ("Boost", "Intercept", "Twin Drive", "Triple Drive", "Sentinel")


def card_url(number: str) -> str:
    """A card's own page.

    Some card numbers carry characters a URL cannot take raw -- a full width
    plus among them -- so the number is encoded rather than pasted in.
    """
    quoted = urllib.parse.quote(number, safe="/-")
    return f"{SITE}/cardlist/?cardno={quoted}&view=text"


def fetch(url: str, attempts: int = 3, missing_ok: bool = False) -> str | None:
    """Fetches a page, retrying: a dropped request must not lose a whole set.

    With [missing_ok], a 404 comes back as None rather than an error. Asking
    for a page past the last one is how the end of a set is found, and that is
    an answer rather than a failure.
    """
    for attempt in range(attempts):
        try:
            request = urllib.request.Request(url, headers=HEADERS)
            with urllib.request.urlopen(request, timeout=45) as response:
                raw = response.read()
                if response.headers.get("Content-Encoding") == "gzip":
                    raw = gzip.GzipFile(fileobj=io.BytesIO(raw)).read()
                return raw.decode("utf-8", "replace")
        except urllib.error.HTTPError as error:
            if error.code == 404 and missing_ok:
                return None
            if attempt == attempts - 1:
                raise RuntimeError(f"could not read {url}: {error}") from error
            time.sleep(2 * (attempt + 1))
        except (urllib.error.URLError, OSError) as error:
            if attempt == attempts - 1:
                raise RuntimeError(f"could not read {url}: {error}") from error
            time.sleep(2 * (attempt + 1))
    raise AssertionError("unreachable")


def strip_tags(html: str) -> list[str]:
    text = re.sub(r"(?is)<(script|style)[^>]*>.*?</\1>", " ", html)
    text = re.sub(r"<[^>]+>", "\n", text)
    text = text.replace("&nbsp;", " ").replace("&amp;", "&")
    text = text.replace("&gt;", ">").replace("&lt;", "<").replace("&#038;", "&")
    text = re.sub(r"[ \t]+", " ", text)
    return [line.strip() for line in text.splitlines() if line.strip()]


def expansions() -> dict[int, str]:
    """Every set the card list offers, as {expansion number: product name}."""
    html = fetch(INDEX) or ""
    found: dict[int, str] = {}
    for match in re.finditer(
        r'href="[^"]*cardsearch/\?expansion=(\d+)"[^>]*>([^<]*)', html
    ):
        number = int(match.group(1))
        name = match.group(2).strip()
        if name and number not in found:
            found[number] = name
    for number in re.findall(r"expansion=(\d+)", html):
        found.setdefault(int(number), "")
    return found


def card_numbers(expansion: int) -> list[tuple[str, str, str]]:
    """The (number, name, image) of every card in a set, across its pages."""
    seen: dict[str, tuple[str, str, str]] = {}
    for page in range(1, 40):
        html = fetch(
            f"{SITE}/cardlist/cardsearch/?expansion={expansion}&page={page}",
            missing_ok=True,
        )
        if html is None:
            break
        fresh = 0
        for match in re.finditer(
            r'href="/cardlist/\?cardno=([^"&]+)[^"]*"[^>]*>\s*'
            r'<img src="([^"]+)"[^>]*alt="([^"]*)"',
            html,
        ):
            number, image, name = (group.strip() for group in match.groups())
            if number and number not in seen:
                seen[number] = (number, name, image)
                fresh += 1
        if not fresh:
            break
    return list(seen.values())


def parse_card(number: str, name: str, image: str, html: str) -> dict[str, object]:
    """Reads one card's own page.

    The block runs: product, name, card type, then a nation, a race and a clan
    in whatever combination the card has, then labelled stats, an ability
    marker, the rules text, the flavour text, and finally the format the card
    is legal in followed by its number.

    Anchoring on that format-and-number pair at the end, rather than on the
    stats, is what lets a ride deck crest through: a crest has no grade, no
    power and no shield, and anchoring on the grade dropped every one of them.
    """
    lines = strip_tags(html)
    start = next((i for i, line in enumerate(lines) if line.startswith("[VGE-")), -1)
    if start < 0:
        return {}
    product = lines[start]
    block = lines[start + 1 :]

    # The format line, identified by the card's own number following it.
    end_at = -1
    card_format = ""
    for index, line in enumerate(block[:-1]):
        if re.fullmatch(r"Standard|Premium|V Premium", line) and (
            block[index + 1] == number
        ):
            end_at = index
            card_format = line
            break
    if end_at < 2:
        return {}

    card_type = block[1]

    # The stats, wherever they start, and whatever subset the card has.
    values: dict[str, str] = {}
    stats_at = end_at
    for index in range(2, end_at):
        match = STAT_LINE.fullmatch(block[index])
        if match:
            stats_at = min(stats_at, index)
            values[match.group(1).lower()] = (match.group(2) or "").strip()

    # Between the card type and the stats sit the nation, the race and the
    # clan. Prose is not one of those, which is what bounds the region on a
    # card that has no stats at all.
    middle = [
        line
        for line in block[2:stats_at]
        if len(line) <= 40 and not line.startswith("[")
    ]
    nation = next((line for line in middle if line in NATIONS), "")
    rest = [line for line in middle if line != nation]
    clan = rest[1] if len(rest) > 1 else ""

    rules: list[str] = []
    trigger = ""
    for line in block[stats_at:end_at]:
        if STAT_LINE.fullmatch(line):
            continue
        if line.startswith(ABILITY_WORDS) or line.startswith("Persona Ride"):
            continue
        # "Critical Trigger +10000": the icon, then what it gives.
        match = re.match(r"(Critical|Draw|Front|Heal|Stand|Over) Trigger\b", line)
        if match:
            trigger = match.group(1).lower()
            continue
        rules.append(line)
    # The last line with no ability marker in it is flavour text, not rules.
    if rules and "[" not in rules[-1]:
        rules.pop()

    return {
        "name": name or block[0],
        "number": number,
        "url": card_url(number),
        "image_url": f"{SITE}{image}" if image.startswith("/") else image,
        "image_file_type": image.rsplit(".", 1)[-1] if "." in image else "",
        "effect": "\n".join(rules).strip(),
        "type": card_type,
        "clan": nation or clan,
        "nation": nation,
        "race": clan,
        "grade": values.get("grade", ""),
        "power": values.get("power", ""),
        "shield": values.get("shield", ""),
        "critical": values.get("critical", ""),
        "trigger": trigger,
        # The format the site says the card is legal in. Worth far more than
        # guessing an era from the card number: a D-numbered set can be a
        # collection of older cards for Premium, and this says so outright.
        "format": card_format,
        "productName": product,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--expansion", type=int, action="append")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--from-expansion", type=int, default=243)
    parser.add_argument("--dump-type", default="")
    # A handful of odd pages -- promo variants, oddly laid out specials -- are
    # tolerated, because blocking six sets of updates over one card helps
    # nobody. A site redesign breaks hundreds at once, which still fails.
    parser.add_argument("--max-failures", type=int, default=5)
    args = parser.parse_args()

    if args.expansion:
        wanted = {number: "" for number in args.expansion}
    else:
        wanted = {
            number: name
            for number, name in sorted(expansions().items())
            if number >= args.from_expansion
        }
    print(f"{len(wanted)} sets to read: {sorted(wanted)}")

    sets: dict[str, object] = {}
    if OUT.exists():
        sets = json.loads(OUT.read_text(encoding="utf-8"))

    types: dict[str, int] = {}
    triggers: dict[str, int] = {}
    failures: list[str] = []
    for number, product in sorted(wanted.items()):
        listing = card_numbers(number)
        if not listing:
            print(f"  expansion={number}: no cards found, skipping")
            continue
        cards = []
        for index, (cardno, name, image) in enumerate(listing):
            if args.limit and index >= args.limit:
                break
            try:
                page = fetch(card_url(cardno))
            except (RuntimeError, UnicodeError) as error:
                # One unreadable card should not cost the other few thousand,
                # but it must not pass unnoticed either: the run fails at the
                # end with every one of them listed.
                failures.append(f"{cardno}: {error}")
                continue
            card = parse_card(cardno, name, image, page or "")
            if args.dump_type and card.get("type") == args.dump_type:
                lines = strip_tags(page or "")
                at = next(
                    (i for i, l in enumerate(lines) if l.startswith("[VGE-")), 0
                )
                print(f"    --- {cardno} block ---")
                for line in lines[at : at + 22]:
                    print(f"      {line[:80]}")
                args.dump_type = ""
            if not card:
                failures.append(f"{cardno}: page did not parse")
                continue
            cards.append(card)
            types[str(card["type"])] = types.get(str(card["type"]), 0) + 1
            if card["trigger"]:
                triggers[str(card["trigger"])] = (
                    triggers.get(str(card["trigger"]), 0) + 1
                )
        sets[str(number)] = {
            "productName": (cards[0]["productName"] if cards else product),
            "cards": cards,
        }
        print(f"  expansion={number} {product[:50]}: {len(cards)} cards")
        sys.stdout.flush()

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(sets, ensure_ascii=False), encoding="utf-8")
    total = sum(len(entry["cards"]) for entry in sets.values())  # type: ignore[index]
    print(f"\n{total} cards written to {OUT} ({OUT.stat().st_size / 1024:.0f} KB)")
    print(f"card types: {sorted(types.items(), key=lambda kv: -kv[1])}")
    print(f"triggers:   {sorted(triggers.items(), key=lambda kv: -kv[1])}")

    # A field left empty is a parser that has drifted, so it is counted rather
    # than discovered later as a gap in the app.
    everything = [
        card for entry in sets.values() for card in entry["cards"]  # type: ignore[index]
    ]
    print("formats:", collections.Counter(c.get("format") for c in everything))
    for field in ("name", "type", "clan", "image_url", "format"):
        missing = [c for c in everything if not c.get(field)]
        print(f"  without {field}: {len(missing)}  {[c['number'] for c in missing][:5]}")
    if everything:
        sample = everything[len(everything) // 2]
        print("  sample:", json.dumps(sample, ensure_ascii=False)[:420])

    # Every trigger kind should turn up somewhere in a few thousand cards.
    # One missing entirely means the parser is eating it, which is exactly how
    # "Critical Trigger" was lost to the Critical stat.
    if any(card["type"] == "Trigger Unit" for card in everything):
        absent = {"critical", "draw", "front", "heal", "stand", "over"} - set(
            triggers
        )
        if absent:
            print(f"  no trigger unit of these kinds at all: {sorted(absent)}")

    if failures:
        print(f"\n{len(failures)} cards could not be read:")
        for failure in failures[:20]:
            print(f"  {failure}")
        if len(failures) > args.max_failures:
            print(
                f"that is more than {args.max_failures}, which means the "
                "parser has stopped matching the site rather than tripping "
                "over an odd card"
            )
            return 1
        print("tolerated; the sets are still written")
    return 0


if __name__ == "__main__":
    sys.exit(main())
