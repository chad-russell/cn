import importlib.util
import json
import os
from pathlib import Path


def load_app(tmp_path):
    pages = tmp_path / "pages.json"
    pages.write_text(json.dumps([
        {"slug": "javanese", "title": "Javanese"},
        {"slug": "amharic", "title": "Amharic"},
    ]))
    os.environ.update({
        "DATABASE": str(tmp_path / "qa.sqlite3"),
        "PAGES_FILE": str(pages),
        "PAGES_API_URL": "http://127.0.0.1:1/unavailable",
    })
    module_path = Path(__file__).with_name("app.py")
    spec = importlib.util.spec_from_file_location("qrcode_qa_app", module_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.app.config.update(TESTING=True)
    return module.app


def test_pages_fall_back_to_generated_inventory(tmp_path):
    client = load_app(tmp_path).test_client()
    response = client.get("/api/pages?reviewer=reviewer-1234567890")
    assert response.status_code == 200
    pages = response.get_json()["pages"]
    assert [page["slug"] for page in pages] == ["amharic", "javanese"]
    assert pages[1]["oldUrl"] == "https://www.qrcode.bible/javanese/"
    assert pages[1]["newUrl"] == "https://qr-dev.qrcode.bible/javanese"


def test_vote_is_idempotent_per_browser_and_builds_reject_queue(tmp_path):
    client = load_app(tmp_path).test_client()
    vote = {"reviewerId": "reviewer-1234567890", "slug": "javanese", "verdict": "reject"}
    assert client.post("/api/votes", json=vote).get_json()["rejections"] == 1
    assert client.post("/api/votes", json=vote).get_json()["rejections"] == 1
    vote["verdict"] = "approve"
    result = client.post("/api/votes", json=vote).get_json()
    assert result == {"ok": True, "approvals": 1, "rejections": 0}
    page = client.get("/api/pages?reviewer=reviewer-1234567890").get_json()["pages"][1]
    assert page["vote"] == "approve"
    assert page["approvals"] == 1
    assert page["rejections"] == 0


def test_unknown_page_cannot_be_voted_on(tmp_path):
    client = load_app(tmp_path).test_client()
    response = client.post("/api/votes", json={
        "reviewerId": "reviewer-1234567890",
        "slug": "not-real",
        "verdict": "approve",
    })
    assert response.status_code == 404
