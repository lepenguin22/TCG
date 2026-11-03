"""Prints a set off the Japanese card list, for translating by hand.

A set Japan has and the English card list does not yet -- a start deck a few
months ahead of its English release -- can only be added from the Japanese
pages. This does not parse or write anything: it prints what the Japanese
card list says, card by card, for a person to translate. It runs where the
English refresh runs, on GitHub Actions, since the site is not reachable from
everywhere.

The Japanese card list's pages fill themselves in from a JSON feed under
/manage/card-list-user/, so this reads that feed rather than the pages:

    python3 tool/read_jp_set.py --products SS19       # sets whose name matches
    python3 tool/read_jp_set.py --list expansion=123  # the cards a query finds
    python3 tool/read_jp_set.py --cards expansion=123 # those cards in full
    python3 tool/read_jp_set.py --get detail?cardno=DZ-SS19/001  # any address
"""

import argparse
import json
import sys
import urllib.parse

import scrape_cardlist as site

API = "https://cf-vanguard.com/manage/card-list-user"


def use_japanese_site() -> None:
    site.HEADERS["Accept-Language"] = "ja,en;q=0.5"
    site.HEADERS["Accept"] = "application/json,text/plain,*/*"
    site.HEADERS["Referer"] = "https://cf-vanguard.com/cardlist/"


def get(path: str) -> object:
    """One answer from the feed, as JSON."""
    text = site.fetch(f"{API}/{path.lstrip('/')}", missing_ok=True)
    if text is None:
        raise SystemExit(f"{path}: not found")
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        raise SystemExit(f"{path}: not JSON: {text[:300]!r}")


def show(value: object, limit: int = 4000) -> str:
    return json.dumps(value, ensure_ascii=False)[:limit]


def lean(value: object) -> object:
    """A card with its empty fields and its image addresses left out."""
    if isinstance(value, dict):
        return {
            key: lean(item)
            for key, item in value.items()
            if item not in (None, "", [], {})
            and not any(word in key for word in ("image", "picture", "img"))
        }
    if isinstance(value, list):
        return [lean(item) for item in value]
    return value


def list_cards(query: str) -> list[dict]:
    """Every card a list query finds, across its pages."""
    cards: list[dict] = []
    for page in range(1, 40):
        params = urllib.parse.parse_qs(query)
        params.update({"page": [str(page)], "per_page": ["100"], "sort": ["no"]})
        data = get(f"list?{urllib.parse.urlencode(params, doseq=True)}")
        items = (data.get("items") or []) if isinstance(data, dict) else []
        if page == 1:
            total = data.get("total") if isinstance(data, dict) else None
            print(f"{total} cards for {query}")
            if items:
                print(f"first item: {show(items[0], 1500)}")
            else:
                print(f"answer: {show(data, 1500)}")
        if not items:
            break
        cards.extend(items)
        if isinstance(data, dict) and data.get("total") and len(cards) >= data["total"]:
            break
    return cards


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--products", default=None)
    parser.add_argument("--list", default="")
    parser.add_argument("--cards", default="")
    parser.add_argument("--get", default="")
    args = parser.parse_args()
    use_japanese_site()

    if args.get:
        print(show(get(args.get), 20000))
        return 0

    if args.products is not None:
        data = get("products")
        if isinstance(data, dict):
            items = data.get("items") or data.get("products") or []
        else:
            items = data
        print(f"{len(items)} products; the first: {show(items[0] if items else data, 1500)}")
        for item in items:
            if args.products.lower() in show(item, 100000).lower():
                print(f"  {show(lean(item), 600)}")
        return 0

    if args.list or args.cards:
        cards = list_cards(args.list or args.cards)
        for card in cards:
            number = card.get("card_number") or card.get("cardno") or ""
            print(f"  {number}  {card.get('card_name') or card.get('name') or ''}")
        if args.cards:
            for card in cards:
                number = card.get("card_number") or card.get("cardno") or ""
                detail = get(f"detail?cardno={urllib.parse.quote(str(number))}")
                card = detail.get("card", detail) if isinstance(detail, dict) else detail
                # The card alone: its rulings and the decks that ran it are
                # read on the site, and the text comes twice, once as HTML.
                if isinstance(card, dict):
                    card = {
                        key: value
                        for key, value in card.items()
                        if key not in ("text_html", "update_time", "disp_flg", "priority", "id")
                    }
                print(f"=== {number}")
                print(show(lean(card), 6000))
                print(flush=True)
        return 0

    parser.error("give --products, --list, --cards or --get")
    return 1


if __name__ == "__main__":
    sys.exit(main())
