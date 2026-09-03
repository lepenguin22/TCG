"""Prints the shape of a Deck Log payload.

Every field the importer reads has been inferred from other projects rather
than observed, because the Deck Log domains are blocked from the environment
the importer was written in. A CI runner can reach them, so this fetches a
public deck and describes what actually comes back.

One-off diagnostic; deleted once it has answered.
"""

import json
import sys
import urllib.error
import urllib.request

HOSTS = ["decklog.bushiroad.com", "decklog-en.bushiroad.com"]


def fetch(host: str, code: str, method: str) -> bytes | None:
    url = f"https://{host}/system/app/api/view/{code}"
    request = urllib.request.Request(url, method=method)
    request.add_header("Accept", "application/json, text/plain, */*")
    request.add_header("Referer", f"https://{host}/view/{code}")
    request.add_header("Origin", f"https://{host}")
    request.add_header("X-Requested-With", "XMLHttpRequest")
    request.add_header("User-Agent", "Mozilla/5.0 (Android) TCGDecks")
    if method == "POST":
        request.data = b""
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.read()
    except urllib.error.HTTPError as error:
        print(f"    HTTP {error.code}")
    except Exception as error:  # noqa: BLE001 - a probe wants every reason
        print(f"    {type(error).__name__}: {error}")
    return None


def describe(body: bytes) -> bool:
    try:
        payload = json.loads(body)
    except ValueError:
        print(f"    not JSON: {body[:200]!r}")
        return False
    if not isinstance(payload, dict):
        print(f"    top level is {type(payload).__name__}")
        return False

    print(f"    keys: {sorted(payload)}")
    for key, value in payload.items():
        if isinstance(value, list):
            print(f"    {key}: list of {len(value)}")
            for entry in value[:2]:
                print(f"      {json.dumps(entry, ensure_ascii=False)[:700]}")
        else:
            print(f"    {key}: {json.dumps(value, ensure_ascii=False)[:150]}")
    return True


def main() -> None:
    code = sys.argv[1] if len(sys.argv) > 1 else "19RVZ6"
    for host in HOSTS:
        for method in ("POST", "GET"):
            print(f"=== {method} {host} /{code}")
            body = fetch(host, code, method)
            if body is None:
                continue
            print(f"    {len(body)} bytes")
            if describe(body):
                # One good answer per host is enough.
                break


if __name__ == "__main__":
    main()
