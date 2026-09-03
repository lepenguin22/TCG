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


def strip_tags(html: str) -> str:
    text = re.sub(r"(?is)<(script|style)[^>]*>.*?</\1>", " ", html)
    text = re.sub(r"<[^>]+>", "\n", text)
    text = re.sub(r"&nbsp;?", " ", text)
    text = re.sub(r"[ \t]+", " ", text)
    return "\n".join(
        line.strip() for line in text.splitlines() if line.strip()
    )


def main() -> None:
    _, listing = get(
        "https://en.cf-vanguard.com/cardlist/cardsearch/?expansion=257", BROWSER
    )
    _, detail = get(
        "https://en.cf-vanguard.com/cardlist/?cardno=DZ-BT15/002EN&view=text",
        BROWSER,
    )

    print("=== ONE ENTRY ON THE SET PAGE (raw) ===")
    anchor = listing.find("DZ-BT15/002EN")
    chunk = listing[max(0, anchor - 1200) : anchor + 400]
    opening = chunk.find("<li")
    print(chunk[opening if opening >= 0 else 0 :][:1400])

    print("\n=== THE CARD'S OWN PAGE (text only) ===")
    text = strip_tags(detail)
    where = text.find("DZ-BT15/002EN")
    print(text[max(0, where - 300) : where + 1200])


if __name__ == "__main__":
    sys.exit(main())
