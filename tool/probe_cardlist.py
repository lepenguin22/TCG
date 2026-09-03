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
    import pathlib

    out = pathlib.Path("probe-out")
    out.mkdir(exist_ok=True)

    # A set page, so the entry markup can be parsed offline.
    for page in (1, 2):
        url = (
            "https://en.cf-vanguard.com/cardlist/cardsearch/"
            f"?expansion=257&page={page}"
        )
        status, body = get(url, BROWSER)
        (out / f"set-257-page{page}.html").write_text(body, encoding="utf-8")
        print(f"    set page {page}: http={status} bytes={len(body)}")

    # A card's own page, which is where the fields live.
    for number in ("DZ-BT15/002EN", "DZ-BT15/012EN"):
        url = f"https://en.cf-vanguard.com/cardlist/?cardno={number}&view=text"
        status, body = get(url, BROWSER)
        name = number.replace("/", "_")
        (out / f"card-{name}.html").write_text(body, encoding="utf-8")
        print(f"    card {number}: http={status} bytes={len(body)}")

    # The index, for how sets are enumerated.
    status, body = get("https://en.cf-vanguard.com/cardlist/", BROWSER)
    (out / "index.html").write_text(body, encoding="utf-8")
    print(f"    index: http={status} bytes={len(body)}")

    # How many pages a set runs to.
    seen: set[str] = set()
    for page in range(1, 10):
        _, html = get(
            "https://en.cf-vanguard.com/cardlist/cardsearch/"
            f"?expansion=257&page={page}",
            BROWSER,
        )
        found = set(re.findall(r"DZ-BT15/\d+EN", html))
        fresh = found - seen
        seen |= found
        print(f"    page={page}: {len(found)} numbers, {len(fresh)} new")
        if not fresh:
            break
    print(f"    DZ-BT15 has {len(seen)} cards across those pages")


if __name__ == "__main__":
    sys.exit(main())
