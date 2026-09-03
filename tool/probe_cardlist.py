"""Finds out how the official card list can be read from a CI runner.

The card database is generated from a community mirror that stopped scraping
at DZ-BT09. The official list is the real source, but a plain request to it
answered 404 -- including from a runner, so it is not this sandbox's egress
blocking. This checks whether that 404 is really bot filtering, and if the
site can be read, what shape its pages are in.

One-off diagnostic; deleted once the scraper it informs is written.
"""

import gzip
import io
import re
import sys
import urllib.error
import urllib.request

BROWSER = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
    ),
    "Accept": (
        "text/html,application/xhtml+xml,application/xml;q=0.9,"
        "image/avif,image/webp,*/*;q=0.8"
    ),
    "Accept-Language": "en-US,en;q=0.9",
    "Accept-Encoding": "gzip, deflate",
}


def get(url: str, headers: dict[str, str] | None = None) -> tuple[int, str]:
    request = urllib.request.Request(url, headers=headers or {})
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            raw = response.read()
            if response.headers.get("Content-Encoding") == "gzip":
                raw = gzip.GzipFile(fileobj=io.BytesIO(raw)).read()
            return response.status, raw.decode("utf-8", "replace")
    except urllib.error.HTTPError as error:
        return error.code, ""
    except Exception as error:  # noqa: BLE001 - a probe wants every reason
        print(f"    {type(error).__name__}: {error}")
        return 0, ""


def main() -> None:
    latest = "https://en.cf-vanguard.com/cardlist/cardsearch/?expansion=257"

    print("=== how many cards does a set page render, and is there more?")
    status, body = get(latest, BROWSER)
    numbers = sorted(set(re.findall(r"DZ-BT15/\d+EN", body)))
    print(f"    http={status} bytes={len(body)} distinct numbers={len(numbers)}")
    print(f"    {numbers[:3]} ... {numbers[-3:]}")

    print("\n=== pagination hints")
    for pattern in (
        r'page=\d+', r'"[^"]*page[^"]*"', r'data-[a-z-]+="[^"]{0,60}"',
    ):
        found = sorted(set(re.findall(pattern, body)))[:10]
        print(f"    {pattern}: {found}")

    print("\n=== scripts and anything endpoint shaped")
    for hint in sorted(set(re.findall(r'(?:src|href)="([^"]*\.js[^"]*)"', body))):
        print(f"    script: {hint}")
    for hint in sorted(set(re.findall(r'["\'](/[^"\']*(?:ajax|api|json|php)[^"\']*)["\']', body)))[:15]:
        print(f"    path: {hint}")

    print("\n=== try asking for a later page")
    for extra in ("&page=2", "&p=2", "&offset=20"):
        status, page = get(latest + extra, BROWSER)
        found = sorted(set(re.findall(r"DZ-BT15/\d+EN", page)))
        overlap = set(found) & set(numbers)
        print(
            f"    {extra:10} http={status} numbers={len(found)} "
            f"new={len(set(found) - set(numbers))}"
        )

    print("\n=== does a single card page carry its details?")
    card = "https://en.cf-vanguard.com/cardlist/?cardno=DZ-BT15/001EN&view=text"
    status, page = get(card, BROWSER)
    print(f"    http={status} bytes={len(page)}")
    text = re.sub(r"<[^>]+>", " ", page)
    text = re.sub(r"\s+", " ", text)
    for label in ("Grade", "Power", "Shield", "Nation", "Card Type", "Trigger"):
        found = re.search(rf"{label}[^A-Za-z0-9]{{0,8}}([^ ]{{0,40}})", text)
        print(f"    {label}: {found.group(1) if found else 'not found'}")
    print(f"    excerpt: {text[:400]}")


if __name__ == "__main__":
    sys.exit(main())
