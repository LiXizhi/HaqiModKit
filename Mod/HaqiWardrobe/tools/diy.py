"""Preview a model's recipe in the open boutique or publish a wearable PNG."""

import argparse
import hashlib
import json
import os
import urllib.request
from urllib.parse import quote
from pathlib import Path


def preview(path, port):
    raw = json.dumps(
        json.loads(path.read_text(encoding="utf-8")),
        ensure_ascii=False,
        separators=(",", ":"),
    )
    if len(raw.encode()) > 8192:
        raise ValueError("Recipe exceeds 8 KiB")
    # Quote each byte as Lua 5.1 data, including quotes, escapes and non-ASCII.
    literal = '"' + "".join("\\%03d" % b for b in raw.encode()) + '"'
    code = (
        'local d=commonlib.getfield("MyCompany.Aries.HaqiWardrobeDIY"); '
        'if not (d and d.Preview) then return {ok=false,message="Open the wardrobe first"} end; '
        "return d.Preview(" + literal + ")"
    )
    return call(port, code)


def call(port, code):
    body = json.dumps({"action": "run_npl_code", "params": {"code": code}}).encode()
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/ajax/paracraft_cli",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=15) as reply:
        data = json.load(reply)
    if not data.get("ok"):
        raise ValueError(data.get("error") or "CLI action failed")
    result = data["result"]["result"]
    if not isinstance(result, dict) or result.get("ok") is False:
        raise ValueError(str(result))
    return result


def upload_personal(blob, account, key, url):
    import getpass
    import requests

    api = "https://api.keepwork.com/core/v0"
    token = os.environ.get("KEEPWORK_TOKEN")
    if not token:
        password = getpass.getpass(f"Keepwork password for {account}: ")
        result = requests.post(
            api + "/users/login",
            json={"username": account, "password": password, "platform": "WEB"},
            timeout=20,
        )
        result.raise_for_status()
        response = result.json()
        token = (response.get("data") or response).get("token")
        if not token:
            raise ValueError(
                "Login did not return a token; use an authenticated KEEPWORK_TOKEN"
            )
    headers = {"Authorization": "Bearer " + token}
    profile = requests.get(api + "/users/profile", headers=headers, timeout=20)
    profile.raise_for_status()
    if (profile.json().get("data") or profile.json()).get("username") != account:
        raise ValueError("The signed-in Keepwork account differs from --account")
    grant = requests.get(
        api + "/steam/haqiUploadToken", headers=headers, params={"key": key}, timeout=20
    )
    grant.raise_for_status()
    reply = grant.json()
    grant_data = reply.get("data") or reply
    if not grant_data.get("token"):
        raise ValueError("Keepwork did not issue a personal CDN upload grant")
    filename = Path(key).name
    uploaded = requests.post(
        "https://upload-z2.qiniup.com/",
        data={
            "key": f"users/{account}/{key}",
            "token": grant_data["token"],
            "x:filename": filename,
        },
        files={"file": (filename, blob, "image/png")},
        timeout=40,
    )
    uploaded.raise_for_status()
    print(url)


def publish(path, confirm, account):
    from PIL import Image

    if path.stat().st_size > 200 * 1024:
        raise ValueError("PNG exceeds 204800 bytes")
    blob = path.read_bytes()
    if len(blob) > 200 * 1024:
        raise ValueError("PNG exceeds 204800 bytes")
    from io import BytesIO

    with Image.open(BytesIO(blob)) as image:
        if (image.format, image.size, image.mode) != (
            "PNG",
            (512, 512),
            "RGBA",
        ) or blob[24:26] != bytes([8, 6]):
            raise ValueError("Expected a 512×512 8-bit RGBA PNG")
        image.load()
    key = "wardrobe/" + hashlib.sha1(blob).hexdigest() + ".png"
    if (
        not account
        or account in (".", "..")
        or any(c in account for c in "/\\?#%")
        or any(c.isspace() for c in account)
    ):
        raise ValueError("Supply your Keepwork username")
    url = f"https://cdn.keepwork.com/users/{quote(account, safe='')}/{key}"
    if not confirm:
        print(f"{len(blob)} bytes; preview only")
        print(url)
    elif confirm != url:
        raise ValueError("Confirmation URL differs from the current image and account")
    else:
        upload_personal(blob, account, key, url)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subs = parser.add_subparsers(dest="action", required=True)
    p = subs.add_parser("preview")
    p.add_argument("file", type=Path)
    p.add_argument("--port", type=int, default=8099)
    p = subs.add_parser("publish")
    p.add_argument("file", type=Path)
    p.add_argument("--account", required=True)
    p.add_argument("--confirm-url")
    args = parser.parse_args()
    try:
        if args.action == "preview":
            print(json.dumps(preview(args.file, args.port), ensure_ascii=False))
        else:
            publish(args.file, args.confirm_url, args.account)
    except (OSError, ValueError) as err:
        parser.exit(1, f"{err}\n")


if __name__ == "__main__":
    main()
