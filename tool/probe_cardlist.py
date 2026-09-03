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
    root = "https://en.cf-vanguard.com/cardlist/"

    print("=== does a browser User-Agent change the answer?")
    for label, headers in (("bare", None), ("browser", BROWSER)):
        status, body = get(root, headers)
        print(f"    {label:8} http={status} bytes={len(body)}")

    status, body = get(root, BROWSER)
    if status != 200:
        print("    still refused; nothing more to learn here")
        return

    print("\n=== what does the card list link to?")
    for pattern in (r'expansion=\d+', r'cardsearch[^"\']*', r'/cardlist/[^"\']*'):
        found = sorted(set(re.findall(pattern, body)))
        print(f"    {pattern}: {len(found)} distinct")
        for item in found[:8]:
            print(f"      {item}")

    print("\n=== the highest expansion numbers offered")
    numbers = sorted({int(n) for n in re.findall(r'expansion=(\d+)', body)})
    print(f"    {len(numbers)} expansions, highest: {numbers[-12:]}")

    print("\n=== does a set page carry its cards without JavaScript?")
    for number in numbers[-3:]:
        url = f"https://en.cf-vanguard.com/cardlist/cardsearch/?expansion={number}"
        status, page = get(url, BROWSER)
        title = re.search(r"<title>([^<]*)</title>", page)
        cards = sorted(set(re.findall(r"[A-Z]{1,3}Z?-[A-Z]{2,4}\d+/\d+[A-Z]*", page)))
        print(
            f"    expansion={number} http={status} bytes={len(page)} "
            f"title={title.group(1).strip() if title else '?'}"
        )
        print(f"      card numbers in raw html: {len(cards)} {cards[:5]}")
        if not cards:
            for hint in re.findall(r'(?:src|href)="([^"]*\.(?:js|json)[^"]*)"', page)[:6]:
                print(f"      script: {hint}")


if __name__ == "__main__":
    sys.exit(main())
