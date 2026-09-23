#!/usr/bin/env python3
import json
import os
import sqlite3
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from flask import Flask, g, jsonify, render_template, request

APP_DIR = Path(__file__).resolve().parent
DATABASE = Path(os.environ.get("DATABASE", "/var/lib/qrcode-qa/qa.sqlite3"))
PAGES_FILE = Path(os.environ.get("PAGES_FILE", APP_DIR / "pages.json"))
OLD_BASE_URL = os.environ.get("OLD_BASE_URL", "https://www.qrcode.bible").rstrip("/")
NEW_BASE_URL = os.environ.get("NEW_BASE_URL", "https://qr-dev.qrcode.bible").rstrip("/")
PAGES_API_URL = os.environ.get(
    "PAGES_API_URL",
    f"{NEW_BASE_URL}/api/bible-landing-pages?limit=500&depth=0&draft=false",
)
REFRESH_SECONDS = int(os.environ.get("REFRESH_SECONDS", "300"))
MAX_REQUESTS_PER_MINUTE = int(os.environ.get("MAX_REQUESTS_PER_MINUTE", "120"))

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 4096
_rate_limits = {}
_pages_cache = {"at": 0.0, "pages": []}


def get_db():
    if "db" not in g:
        DATABASE.parent.mkdir(parents=True, exist_ok=True)
        db = sqlite3.connect(DATABASE)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA journal_mode=WAL")
        db.execute("PRAGMA foreign_keys=ON")
        db.executescript(
            """
            CREATE TABLE IF NOT EXISTS votes (
              reviewer_id TEXT NOT NULL,
              slug TEXT NOT NULL,
              verdict TEXT NOT NULL CHECK(verdict IN ('approve', 'reject')),
              created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
              updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
              PRIMARY KEY (reviewer_id, slug)
            );
            CREATE INDEX IF NOT EXISTS votes_slug_verdict ON votes(slug, verdict);
            """
        )
        g.db = db
    return g.db


@app.teardown_appcontext
def close_db(_error):
    db = g.pop("db", None)
    if db is not None:
        db.close()


def normalize_pages(documents):
    pages = {}
    for document in documents:
        slug = str(document.get("slug", "")).strip().strip("/")
        if not slug or "/" in slug:
            continue
        title = (
            document.get("languageName")
            or document.get("localizedTitle")
            or document.get("title")
            or slug
        )
        pages[slug] = {"slug": slug, "title": str(title).strip() or slug}
    return sorted(pages.values(), key=lambda page: (page["title"].casefold(), page["slug"]))


def load_seed_pages():
    with PAGES_FILE.open(encoding="utf-8") as handle:
        return normalize_pages(json.load(handle))


def fetch_pages():
    url = f"{PAGES_API_URL}{'&' if '?' in PAGES_API_URL else '?'}cb={int(time.time())}"
    req = urllib.request.Request(url, headers={"User-Agent": "QRCodeBible-QA/1.0"})
    with urllib.request.urlopen(req, timeout=10) as response:
        payload = json.load(response)
    pages = normalize_pages(payload.get("docs", []))
    if not pages:
        raise ValueError("landing-page API returned no published pages")
    return pages


def get_pages(force=False):
    now = time.monotonic()
    if not force and _pages_cache["pages"] and now - _pages_cache["at"] < REFRESH_SECONDS:
        return _pages_cache["pages"]
    try:
        pages = fetch_pages()
    except (OSError, ValueError, urllib.error.URLError, json.JSONDecodeError):
        pages = load_seed_pages()
    _pages_cache.update({"at": now, "pages": pages})
    return pages


def allow_vote_request():
    client = request.headers.get("X-Forwarded-For", request.remote_addr or "unknown").split(",")[0]
    minute = int(time.time() // 60)
    key = (client, minute)
    _rate_limits[key] = _rate_limits.get(key, 0) + 1
    for stale in [item for item in _rate_limits if item[1] < minute - 1]:
        _rate_limits.pop(stale, None)
    return _rate_limits[key] <= MAX_REQUESTS_PER_MINUTE


def vote_counts(db):
    rows = db.execute(
        """SELECT slug,
                  SUM(verdict = 'approve') AS approvals,
                  SUM(verdict = 'reject') AS rejections
             FROM votes GROUP BY slug"""
    ).fetchall()
    return {
        row["slug"]: {"approvals": row["approvals"], "rejections": row["rejections"]}
        for row in rows
    }


@app.get("/")
def index():
    return render_template(
        "index.html",
        old_base_url=OLD_BASE_URL,
        new_base_url=NEW_BASE_URL,
    )


@app.get("/healthz")
def health():
    get_db().execute("SELECT 1").fetchone()
    return jsonify(ok=True, pages=len(get_pages()))


@app.get("/api/pages")
def pages_api():
    reviewer_id = request.args.get("reviewer", "")[:128]
    pages = get_pages(force=request.args.get("refresh") == "1")
    db = get_db()
    counts = vote_counts(db)
    reviewer_votes = {}
    if reviewer_id:
        reviewer_votes = {
            row["slug"]: row["verdict"]
            for row in db.execute(
                "SELECT slug, verdict FROM votes WHERE reviewer_id = ?", (reviewer_id,)
            )
        }
    result = []
    for page in pages:
        result.append(
            {
                **page,
                "oldUrl": f"{OLD_BASE_URL}/{urllib.parse.quote(page['slug'])}/",
                "newUrl": f"{NEW_BASE_URL}/{urllib.parse.quote(page['slug'])}",
                "vote": reviewer_votes.get(page["slug"]),
                **counts.get(page["slug"], {"approvals": 0, "rejections": 0}),
            }
        )
    return jsonify(pages=result)


@app.post("/api/votes")
def save_vote():
    if not allow_vote_request():
        return jsonify(error="too many votes"), 429
    payload = request.get_json(silent=True) or {}
    reviewer_id = str(payload.get("reviewerId", ""))[:128]
    slug = str(payload.get("slug", "")).strip()[:200]
    verdict = payload.get("verdict")
    if len(reviewer_id) < 16 or verdict not in {"approve", "reject"}:
        return jsonify(error="invalid vote"), 400
    if slug not in {page["slug"] for page in get_pages()}:
        return jsonify(error="unknown page"), 404
    db = get_db()
    db.execute(
        """INSERT INTO votes (reviewer_id, slug, verdict) VALUES (?, ?, ?)
           ON CONFLICT(reviewer_id, slug) DO UPDATE SET
             verdict = excluded.verdict, updated_at = CURRENT_TIMESTAMP""",
        (reviewer_id, slug, verdict),
    )
    db.commit()
    counts = vote_counts(db).get(slug, {"approvals": 0, "rejections": 0})
    return jsonify(ok=True, **counts)


if __name__ == "__main__":
    app.run(host=os.environ.get("HOST", "127.0.0.1"), port=int(os.environ.get("PORT", "7891")))
