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
    # A spread across one set, to see how the field block varies by card type
    # -- and above all whether a trigger unit's page names its trigger, which
    # no source used so far has.
    for number in (
        "DZ-BT15/001EN",
        "DZ-BT15/020EN",
        "DZ-BT15/035EN",
        "DZ-BT15/045EN",
        "DZ-BT15/055EN",
        "DZ-BT15/065EN",
        "DZ-BT15/070EN",
        "DZ-BT15/075EN",
    ):
        _, html = get(
            f"https://en.cf-vanguard.com/cardlist/?cardno={number}&view=text",
            BROWSER,
        )
        text = strip_tags(html)
        start_at = text.find("[VGE-")
        end_at = text.find("[CONT]", start_at)
        if end_at < 0:
            end_at = text.find("[AUTO]", start_at)
        if end_at < 0:
            end_at = start_at + 400
        block = text[start_at:end_at].splitlines()[1:12]
        print(f"=== {number}")
        for line in block:
            print(f"    {line[:70]}")


if __name__ == "__main__":
    sys.exit(main())
