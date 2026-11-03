"""Prints a set off the Japanese card list, for translating by hand.

A set Japan has and the English card list does not yet -- a start deck a few
months ahead of its English release -- can only be added from the Japanese
pages. This does not parse or write anything: it prints what those pages say,
card by card, for a person to translate. It runs where the English refresh
runs, on GitHub Actions, since the site is not reachable from everywhere.

    python3 tool/read_jp_set.py --find ごーすと      # sets whose name matches
    python3 tool/read_jp_set.py --expansion 123      # every card in a set
    python3 tool/read_jp_set.py --search DZ-SS19     # cards a keyword finds
    python3 tool/read_jp_set.py --raw /cardlist/      # a page's links and text
"""

import argparse
import re
import sys

import scrape_cardlist as site

JP = "https://cf-vanguard.com"


def use_japanese_site() -> None:
    """Points the English scraper's fetching and listing at the Japanese site.

    Its functions build their URLs from these at call time, so the same
    listing and retry code reads either.
    """
    site.SITE = JP
    site.INDEX = f"{JP}/cardlist/"
    site.HEADERS["Accept-Language"] = "ja,en;q=0.5"


def card_page_url(number: str) -> str:
    # The Japanese pages take the same query as the English ones.
    return site.card_url(number)


def dump(number: str, name: str) -> None:
    """Prints the part of a card's page that holds the card."""
    page = site.fetch(card_page_url(number), missing_ok=True) or ""
    lines = site.strip_tags(page)
    # The card's block starts at its name and ends at its number; the menus
    # around it say nothing about the card.
    start = next((i for i, line in enumerate(lines) if line == name), None)
    if start is None:
        start = next((i for i, line in enumerate(lines) if name in line), 0)
    end = next(
        (i for i in range(start, len(lines)) if number in lines[i]),
        min(start + 40, len(lines) - 1),
    )
    print(f"=== {number} | {name}")
    for line in lines[max(start - 3, 0) : end + 2]:
        print(f"    {line}")
    print(flush=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--find", default="")
    parser.add_argument("--expansion", type=int, default=0)
    parser.add_argument("--search", default="")
    # A page as it comes, for working out how the Japanese site lays out its
    # lists: the links on it that lead into the card list, and its text.
    parser.add_argument("--raw", default="")
    args = parser.parse_args()
    use_japanese_site()

    if args.raw:
        url = args.raw if args.raw.startswith("http") else f"{JP}{args.raw}"
        page = site.fetch(url, missing_ok=True) or ""
        print(f"{url}: {len(page)} characters")
        # The Japanese card pages fill themselves in from a script, so what
        # matters is where that script gets the card from.
        scripts = re.findall(r'<script[^>]+src="([^"]+)"', page)
        print(f"{len(scripts)} scripts:")
        for src in scripts:
            print(f"  {src}")
        endpoints = set(
            re.findall(r'["\']([^"\'\s]*(?:api|json|ajax|search)[^"\'\s]*)["\']', page)
        )
        print(f"{len(endpoints)} likely data addresses in the page:")
        for endpoint in sorted(endpoints)[:60]:
            print(f"  {endpoint}")
        # And in the site's own scripts, which is where a fetch would be.
        for src in scripts:
            if "cf-vanguard" not in src and not src.startswith("/"):
                continue
            full = src if src.startswith("http") else f"{JP}{src}"
            code = site.fetch(full, missing_ok=True) or ""
            found = sorted(set(re.findall(
                r'["\'`]([^"\'`\s]*(?:api|json|ajax|cardlist|cardsearch)[^"\'`\s]*)["\'`]',
                code,
            )))
            if found:
                print(f"in {src}:")
                for item in found[:40]:
                    print(f"  {item}")
        return 0

    if args.find:
        found = site.expansions()
        print(f"{len(found)} sets on the Japanese card list")
        for number, name in sorted(found.items()):
            if args.find.lower() in name.lower():
                print(f"  expansion={number}  {name}")
        return 0

    if args.expansion:
        cards = site.card_numbers(args.expansion)
    elif args.search:
        cards = site.search(args.search)
    else:
        parser.error("give --find, --expansion or --search")
    print(f"{len(cards)} cards")
    for number, name, _ in cards:
        dump(number, name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
