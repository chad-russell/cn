#!/usr/bin/env python3
"""artifacts-server — static file server + tiny JSON API for ~/artifacts.

Serves GET/HEAD like python -m http.server, plus:
  POST /-/delete   body: slug=<slug> (form or {"slug": ...}) — removes the
                   artifact + its meta sidecar, then reindexes
  POST /-/reindex  rescan ~/artifacts → rewrite manifest.json
  GET  /-/health   {"ok": true, ...}

Deliberately stdlib-only. Nebula-bound; the trust boundary is the overlay
(see cn AGENTS.md). Slug validation is strict and protected paths are not
deletable. Replaces the hermes-era `python -m http.server` user unit
(2026-09-07) now that the catalog needs delete/reindex.
"""
import argparse
import html
import json
import os
import re
import shutil
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

PROTECTED = {"index.html", "manifest.json", "assets", ".meta"}
SLUG_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
TITLE_RE = re.compile(r"<title[^>]*>(.*?)</title>", re.IGNORECASE | re.DOTALL)
SKIP_PREFIXES = (".",)  # dotfiles/dirs (incl. .meta, .staging-*, *.trash-)

ROOT = os.path.expanduser("~/artifacts")
_lock = threading.Lock()


def scan() -> list:
    metas = {}
    meta_dir = os.path.join(ROOT, ".meta")
    if os.path.isdir(meta_dir):
        for f in os.listdir(meta_dir):
            if f.endswith(".json"):
                try:
                    with open(os.path.join(meta_dir, f)) as fh:
                        metas[f[:-5]] = json.load(fh)
                except (ValueError, OSError):
                    pass
    out = []
    for name in sorted(os.listdir(ROOT)):
        path = os.path.join(ROOT, name)
        if name in PROTECTED or name.startswith(SKIP_PREFIXES):
            continue
        if name == "index.html" or name == "manifest.json":
            continue
        if ".trash-" in name or name.endswith(".meta.json"):
            continue
        is_dir = os.path.isdir(path)
        slug = name if not is_dir else name
        meta = metas.get(slug, {})
        title = meta.get("title") or slug
        if not meta.get("title") and not is_dir:
            try:
                head = open(path, "rb").read(65536).decode("utf-8", "ignore")
                m = TITLE_RE.search(head)
                if m:
                    title = html.unescape(m.group(1).strip())[:120]
            except OSError:
                pass
        st = os.stat(path)
        out.append({
            "slug": slug,
            "type": "dir" if is_dir else "file",
            "title": title,
            "lane": meta.get("lane", ""),
            "created": meta.get("created") or time.strftime(
                "%Y-%m-%dT%H:%M:%S", time.localtime(st.st_mtime)),
            "modified": time.strftime(
                "%Y-%m-%dT%H:%M:%S", time.localtime(st.st_mtime)),
            "source": meta.get("source", ""),
            "supersedes": meta.get("supersedes", ""),
            "url": f"/{slug}/" if is_dir else f"/{slug}",
            "size": st.st_size if not is_dir else sum(
                os.path.getsize(os.path.join(r, f))
                for r, _, fs in os.walk(path) for f in fs),
        })
    out.sort(key=lambda a: a["created"], reverse=True)
    return out


def reindex() -> dict:
    with _lock:
        manifest = {"generated": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                    "artifacts": scan()}
        tmp = os.path.join(ROOT, ".manifest.tmp")
        with open(tmp, "w") as fh:
            json.dump(manifest, fh, indent=1)
        os.replace(tmp, os.path.join(ROOT, "manifest.json"))
    return manifest


class Handler(SimpleHTTPRequestHandler):
    server_version = "ArtifactsServer/1.0"

    def log_message(self, fmt, *args):  # journald-friendly one-liners
        print("%s - %s" % (self.address_string(), fmt % args))

    # -- JSON API --------------------------------------------------------
    def _json(self, code: int, obj: dict):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # noqa: N802
        if self.path == "/-/health":
            self._json(200, {"ok": True, "root": ROOT,
                             "generated": time.strftime("%H:%M:%S")})
        else:
            super().do_GET()

    def do_POST(self):  # noqa: N802
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length).decode("utf-8", "replace") if length else ""
        if self.headers.get("Content-Type", "").startswith("application/json"):
            try:
                data = json.loads(raw or "{}")
            except ValueError:
                return self._json(400, {"ok": False, "error": "bad json"})
        else:
            data = {k: v[0] for k, v in parse_qs(raw).items()}

        if self.path == "/-/reindex":
            m = reindex()
            return self._json(200, {"ok": True, "count": len(m["artifacts"])})

        if self.path == "/-/delete":
            slug = str(data.get("slug", ""))
            if not SLUG_RE.match(slug) or slug in PROTECTED:
                return self._json(400, {"ok": False, "error": "bad slug"})
            target = os.path.join(ROOT, slug)
            real = os.path.realpath(target)
            if not real.startswith(os.path.realpath(ROOT) + os.sep):
                return self._json(400, {"ok": False, "error": "escape"})
            if not os.path.lexists(target):
                return self._json(404, {"ok": False, "error": "no such artifact"})
            shutil.rmtree(target, ignore_errors=True) \
                if os.path.isdir(target) else os.remove(target)
            meta = os.path.join(ROOT, ".meta", f"{slug}.json")
            if os.path.exists(meta):
                os.remove(meta)
            m = reindex()
            return self._json(200, {"ok": True, "slug": slug,
                                    "remaining": len(m["artifacts"])})

        self._json(404, {"ok": False, "error": "unknown endpoint"})


def main():
    global ROOT
    ap = argparse.ArgumentParser()
    ap.add_argument("--bind", default="10.10.0.12")
    ap.add_argument("--port", type=int, default=8910)
    ap.add_argument("--root", default=ROOT)
    args = ap.parse_args()
    ROOT = os.path.realpath(args.root)
    os.chdir(ROOT)
    os.makedirs(os.path.join(ROOT, ".meta"), exist_ok=True)
    reindex()
    httpd = ThreadingHTTPServer((args.bind, args.port), Handler)
    print(f"artifacts-server: serving {ROOT} on {args.bind}:{args.port}")
    httpd.serve_forever()


if __name__ == "__main__":
    main()
