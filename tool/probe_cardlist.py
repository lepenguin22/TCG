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
    print("=== the shape of one entry on a set page")
    status, body = get(
        "https://en.cf-vanguard.com/cardlist/cardsearch/?expansion=257", BROWSER
    )
    print(f"    http={status} bytes={len(body)}")
    anchor = body.find("DZ-BT15/002EN")
    if anchor > 0:
        print("--- raw html around the second card ---")
        print(body[max(0, anchor - 1800) : anchor + 700])

    print("\n\n=== how many pages does a set have?")
    seen: set[str] = set()
    for page in range(1, 8):
        _, html = get(
            "https://en.cf-vanguard.com/cardlist/cardsearch/"
            f"?expansion=257&page={page}",
            BROWSER,
        )
        found = set(re.findall(r"DZ-BT15/\d+EN", html))
        fresh = found - seen
        seen |= found
        print(f"    page={page} numbers={len(found)} new={len(fresh)} total={len(seen)}")
        if not fresh:
            break

    print("\n=== everything a card's own page says")
    _, page = get(
        "https://en.cf-vanguard.com/cardlist/?cardno=DZ-BT15/002EN&view=text",
        BROWSER,
    )
    start_at = page.find("cardlist-Detail")
    if start_at < 0:
        start_at = page.find("DZ-BT15/002EN")
    print("--- raw html of the detail block ---")
    print(page[max(0, start_at - 200) : start_at + 3000])


if __name__ == "__main__":
    sys.exit(main())
