"""Reads sets from Bushiroad's official English card list.

The card database is generated from a community mirror whose scrape stopped
at DZ-BT09, so every card from a newer set is missing -- which is what an
imported deck reports as cards it cannot match or check. This fetches the
sets the mirror does not have, straight from the source, and writes them in
the same shape the mirror uses so the generator can read both.

The site answers 404 to a bare request; it wants a browser's headers. That is
the whole reason it looked as though it had moved.

Run from CI, where the site is reachable:
    python3 tool/scrape_cardlist.py [--limit N] [--expansion N] [--card NO]
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

# Every card type the site prints. The card type is what the block is found
# by: a card from a set is under a "[VGE-...]" product line, but a promo is
# under "PR cards", and anchoring on the product meant every promo page read
# as an unparseable one.
CARD_TYPES = {
    "Normal Unit",
    "Trigger Unit",
    "G Unit",
    "Normal Order",
    "Blitz Order",
    "Set Order",
    "Ride Deck Crest",
    "Token",
}


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


CARD_IMAGE = re.compile(r'src="(/wordpress/wp-content/images/cardlist/[^"]+)"')


def card_image(html: str) -> str:
    """The card's own art, off its page.

    A card read through a set listing brings its image with it. One asked for
    by number has no listing to bring anything, so it comes off the page.
    """
    match = CARD_IMAGE.search(html)
    return match.group(1) if match else ""


LISTING = re.compile(
    r'href="/cardlist/\?cardno=([^"&]+)[^"]*"[^>]*>\s*'
    r'<img src="([^"]+)"[^>]*alt="([^"]*)"'
)


def search(term: str) -> list[tuple[str, str, str]]:
    """Cards whose page the site's own search turns up for [term].

    A card asked for by a number the site does not know gives back the card
    list index rather than a 404, which reads as "did not parse" and says
    nothing about why. Searching for the name is how the number it is really
    filed under gets found.
    """
    found: dict[str, tuple[str, str, str]] = {}
    quoted = urllib.parse.quote(term)
    for page in range(1, 10):
        html = fetch(
            f"{SITE}/cardlist/cardsearch/?keyword={quoted}&page={page}",
            missing_ok=True,
        )
        if html is None:
            break
        fresh = 0
        for match in LISTING.finditer(html):
            number, image, name = (group.strip() for group in match.groups())
            if number and number not in found:
                found[number] = (number, name, image)
                fresh += 1
        if not fresh:
            break
    return list(found.values())


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

    # The end of the block: the format line the card's own number follows.
    ends_at = -1
    card_format = ""
    for index, line in enumerate(lines[:-1]):
        if re.fullmatch(r"Standard|Premium|V Premium", line) and (
            lines[index + 1] == number
        ):
            ends_at = index
            card_format = line
            break
    if ends_at < 3:
        return {}

    # The start of it: the card type, with the name above it and the product
    # above that. Read backwards from the end so the navigation above the
    # card cannot be mistaken for it, and matched whole so a card type named
    # inside a rules line is not mistaken for the card's own.
    type_at = -1
    for index in range(ends_at - 1, 1, -1):
        if lines[index] in CARD_TYPES:
            type_at = index
            break
    if type_at < 2:
        return {}

    product = lines[type_at - 2]
    block = lines[type_at - 1 :]
    end_at = ends_at - (type_at - 1)
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
    # Flavour text sits after the rules and carries neither a bracketed
    # marker nor a bullet, so everything past the last line that has one is
    # flavour. Popping a single line was not enough: a card with two lines of
    # it kept one, which is how two printings of one card ended up as two
    # cards -- they are identified by what they do, and one of them said
    # something about the sea.
    #
    # A card with no marked line anywhere has nothing to measure the end of
    # its rules by, so it keeps all but a plainly unmarked last line, which
    # is what this always did.
    marked = [
        index
        for index, line in enumerate(rules)
        if "[" in line or line.startswith("・")
    ]
    if marked:
        del rules[marked[-1] + 1 :]
    elif rules and "[" not in rules[-1]:
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
    # Named cards, for the promos that no set sweep reaches: the mirror's PR
    # set stopped where the mirror did, and a promo printed since is missing
    # from the database with nothing short of re-reading thousands of cards
    # to find it. Asking for the number is cheaper and repeatable.
    parser.add_argument("--card", action="append", default=[])
    # Look a card up by name and print what the site has, without writing
    # anything. For working out the number a card is filed under.
    parser.add_argument("--search", default="")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--from-expansion", type=int, default=243)
    parser.add_argument("--dump-type", default="")
    # A handful of odd pages -- promo variants, oddly laid out specials -- are
    # tolerated, because blocking six sets of updates over one card helps
    # nobody. A site redesign breaks hundreds at once, which still fails.
    parser.add_argument("--max-failures", type=int, default=5)
    args = parser.parse_args()

    if args.search:
        matches = search(args.search)
        print(f'{len(matches)} cards match "{args.search}":')
        for number, name, _ in matches:
            print(f"  {number}  {name}")
        return 0

    if args.card and not args.expansion:
        wanted = {}
    elif args.expansion:
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

    # Cards asked for by number, kept in a bucket of their own so a later set
    # sweep does not wipe them and they do not pretend to be a set.
    if args.card:
        bucket = sets.get("named", {"productName": "Named cards", "cards": []})
        existing = {card["number"]: card for card in bucket["cards"]}  # type: ignore[index]
        for number in args.card:
            try:
                page = fetch(card_url(number), missing_ok=True)
            except (RuntimeError, UnicodeError) as error:
                failures.append(f"{number}: {error}")
                continue
            if page is None:
                failures.append(f"{number}: no such card on the site")
                continue
            card = parse_card(number, "", card_image(page), page)
            if not card:
                # The page is the only thing that explains a failure here, so
                # it is printed rather than summarised. Whether the product
                # line the parser anchors on is even there is the first
                # question, so it is answered first.
                lines = strip_tags(page)
                anchored = any(line.startswith("[VGE-") for line in lines)
                failures.append(f"{number}: page did not parse")
                print(
                    f"    --- {number} did not parse "
                    f"(product line found: {anchored}); its page reads ---"
                )
                for line in lines[:70]:
                    print(f"      {line[:90]}")
                continue
            existing[number] = card
            print(f"  {number}: {card['name']} ({card['productName']})")
        bucket["cards"] = list(existing.values())  # type: ignore[index]
        sets["named"] = bucket

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
