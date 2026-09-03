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
    for key in ("title", "deck_param1", "deck_param2", "game_title_id"):
        if key in payload:
            print(f"    {key}: {json.dumps(payload[key], ensure_ascii=False)}")

    sections = {
        key: value for key, value in payload.items() if isinstance(value, list)
    }
    numbers_in = {
        key: {str(e.get("card_number")) for e in value if isinstance(e, dict)}
        for key, value in sections.items()
    }
    for key, value in sections.items():
        rows = [e for e in value if isinstance(e, dict)]
        copies = sum(int(e.get("num") or 0) for e in rows)
        kinds = sorted({str(e.get("type")) for e in rows})
        slots = sorted({str(e.get("slot")) for e in rows})
        grades = sorted({str(e.get("grade")) for e in rows})
        print(
            f"    {key}: {len(rows)} rows, {copies} copies, "
            f"type={kinds} slot={slots} grade={grades}"
        )
        # Does this section repeat cards that are already in another one?
        for other, numbers in numbers_in.items():
            if other == key or not numbers:
                continue
            shared = numbers_in[key] & numbers
            if shared:
                print(f"      shares {len(shared)} card numbers with {other}")
        fields = sorted({field for e in rows for field in e})
        print(f"      fields: {fields}")
        for entry in rows[:1]:
            print(f"      sample: {json.dumps(entry, ensure_ascii=False)[:500]}")

    # Anything that looks like it could name a trigger icon.
    for key, value in sections.items():
        for entry in value:
            if not isinstance(entry, dict):
                continue
            interesting = {
                f: v
                for f, v in entry.items()
                if f in ("card_kind", "is_over", "rare", "type", "slot")
            }
            print(f"    {key} markers sample: {interesting}")
            break
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
