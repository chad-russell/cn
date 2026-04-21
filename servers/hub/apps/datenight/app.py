import json
import os
import random
from datetime import date
from flask import Flask, jsonify, request, send_from_directory

app = Flask(__name__, static_folder="static", static_url_path="")
DATA_FILE = os.environ.get("DATA_FILE", "/data/restaurants.json")

CATEGORIES = ["bfast", "lunch", "pizza", "indian"]
META_LISTS = ["eaten", "future_ideas"]
ALL_LISTS = CATEGORIES + META_LISTS


def read_data():
    with open(DATA_FILE, "r") as f:
        return json.load(f)


def write_data(data):
    with open(DATA_FILE, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)


def _rename_in_urls(data, old_name, new_name):
    urls = data.get("urls", {})
    if old_name in urls:
        urls[new_name] = urls.pop(old_name)


def _rename_in_visits(data, old_name, new_name):
    visits = data.get("visits", {})
    if old_name in visits:
        visits[new_name] = visits.pop(old_name)


def _remove_from_urls(data, name):
    data.get("urls", {}).pop(name, None)


def _remove_from_visits(data, name):
    data.get("visits", {}).pop(name, None)


def _update_tonight_on_rename(data, old_name, new_name):
    tonight = data.get("tonight")
    if tonight and tonight.get("name") == old_name:
        tonight["name"] = new_name


def _update_tonight_on_delete(data, name):
    tonight = data.get("tonight")
    if tonight and tonight.get("name") == name:
        data["tonight"] = None


@app.route("/")
def index():
    return send_from_directory("static", "index.html")


@app.route("/api/data", methods=["GET"])
def get_data():
    return jsonify(read_data())


@app.route("/api/restaurants", methods=["POST"])
def add_restaurant():
    body = request.json
    category = body.get("category")
    name = body.get("name", "").strip()
    url = body.get("url", "").strip()
    if category not in ALL_LISTS or not name:
        return jsonify({"error": "invalid category or name"}), 400
    data = read_data()
    if name not in data[category]:
        data[category].append(name)
        if category in CATEGORIES and name not in data["future_ideas"] and name not in data["eaten"]:
            data["future_ideas"].append(name)
    if url:
        data.setdefault("urls", {})[name] = url
    write_data(data)
    return jsonify(data)


@app.route("/api/restaurants", methods=["PUT"])
def update_restaurant():
    body = request.json
    category = body.get("category")
    old_name = body.get("old_name", "").strip()
    new_name = body.get("new_name", "").strip()
    url = body.get("url")
    if category not in ALL_LISTS or not old_name or not new_name:
        return jsonify({"error": "invalid request"}), 400
    data = read_data()
    if old_name in data[category]:
        idx = data[category].index(old_name)
        data[category][idx] = new_name
        for meta in META_LISTS:
            if old_name in data[meta]:
                data[meta][data[meta].index(old_name)] = new_name
        _rename_in_urls(data, old_name, new_name)
        _rename_in_visits(data, old_name, new_name)
        _update_tonight_on_rename(data, old_name, new_name)
    if url is not None:
        data.setdefault("urls", {})[new_name] = url.strip()
    write_data(data)
    return jsonify(data)


@app.route("/api/restaurants", methods=["DELETE"])
def delete_restaurant():
    body = request.json
    category = body.get("category")
    name = body.get("name", "").strip()
    if category not in ALL_LISTS or not name:
        return jsonify({"error": "invalid request"}), 400
    data = read_data()
    for lst in [category] + META_LISTS:
        if name in data[lst]:
            data[lst].remove(name)
    _remove_from_urls(data, name)
    _remove_from_visits(data, name)
    _update_tonight_on_delete(data, name)
    write_data(data)
    return jsonify(data)


@app.route("/api/url", methods=["POST"])
def set_url():
    body = request.json
    name = body.get("name", "").strip()
    url = body.get("url", "").strip()
    if not name:
        return jsonify({"error": "name required"}), 400
    data = read_data()
    data.setdefault("urls", {})[name] = url
    write_data(data)
    return jsonify(data)


@app.route("/api/tonight", methods=["POST"])
def set_tonight():
    body = request.json
    name = body.get("name", "").strip()
    if not name:
        data = read_data()
        data["tonight"] = None
        write_data(data)
        return jsonify(data)
    data = read_data()
    data["tonight"] = {"name": name, "date": date.today().isoformat()}
    write_data(data)
    return jsonify(data)


@app.route("/api/tonight", methods=["DELETE"])
def clear_tonight():
    data = read_data()
    data["tonight"] = None
    write_data(data)
    return jsonify(data)


@app.route("/api/mark-eaten", methods=["POST"])
def mark_eaten():
    body = request.json
    name = body.get("name", "").strip()
    if not name:
        return jsonify({"error": "name required"}), 400
    data = read_data()
    if name not in data["eaten"]:
        data["eaten"].append(name)
    if name in data["future_ideas"]:
        data["future_ideas"].remove(name)
    write_data(data)
    return jsonify(data)


@app.route("/api/mark-unvisited", methods=["POST"])
def mark_unvisited():
    body = request.json
    name = body.get("name", "").strip()
    if not name:
        return jsonify({"error": "name required"}), 400
    data = read_data()
    if name in data["eaten"]:
        data["eaten"].remove(name)
    if name not in data["future_ideas"]:
        data["future_ideas"].append(name)
    write_data(data)
    return jsonify(data)


@app.route("/api/pick", methods=["POST"])
def pick_random():
    body = request.json or {}
    category = body.get("category")
    data = read_data()
    if category == "future":
        pool = data.get("future_ideas", [])
    elif category in CATEGORIES:
        pool = [r for r in data.get(category, []) if r in data.get("future_ideas", [])]
        if not pool:
            pool = data.get(category, [])
    elif category == "all":
        pool = data.get("future_ideas", [])
    else:
        pool = data.get("future_ideas", [])
    if not pool:
        return jsonify({"error": "no restaurants to pick from"}), 400
    return jsonify({"pick": random.choice(pool), "pool_size": len(pool)})


@app.route("/api/visit", methods=["POST"])
def add_visit():
    body = request.json
    name = body.get("name", "").strip()
    visit_date = body.get("date", "").strip() or date.today().isoformat()
    if not name:
        return jsonify({"error": "name required"}), 400
    try:
        date.fromisoformat(visit_date)
    except ValueError:
        return jsonify({"error": "invalid date format, use YYYY-MM-DD"}), 400
    data = read_data()
    data.setdefault("visits", {}).setdefault(name, [])
    if visit_date not in data["visits"][name]:
        data["visits"][name].append(visit_date)
        data["visits"][name].sort()
    if name not in data["eaten"]:
        data["eaten"].append(name)
    if name in data.get("future_ideas", []):
        data["future_ideas"].remove(name)
    write_data(data)
    return jsonify(data)


@app.route("/api/visit", methods=["DELETE"])
def remove_visit():
    body = request.json
    name = body.get("name", "").strip()
    visit_date = body.get("date", "").strip()
    if not name or not visit_date:
        return jsonify({"error": "name and date required"}), 400
    data = read_data()
    visits = data.get("visits", {})
    if name in visits and visit_date in visits[name]:
        visits[name].remove(visit_date)
        if not visits[name]:
            del visits[name]
    write_data(data)
    return jsonify(data)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=7890)
