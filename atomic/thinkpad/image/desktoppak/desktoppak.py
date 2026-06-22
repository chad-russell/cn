#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HOME = Path.home()
DATA_ROOT = Path(os.environ.get("DESKTOPPAK_DATA_ROOT", HOME / ".local/share/desktoppak"))
STATE_ROOT = Path(os.environ.get("DESKTOPPAK_STATE_ROOT", HOME / ".local/state/desktoppak"))
REPO_ROOT = Path(__file__).resolve().parents[1]
DESKTOPS_DIR = REPO_ROOT / "desktops"
LAUNCH_SCRIPT = DESKTOPS_DIR / "launch-bwrap-session.sh"
SESSIONS_DIR = Path("/usr/local/share/wayland-sessions")
WRAPPER_PATH = Path("/usr/local/bin/desktoppak")


def run(*args: str, check: bool = True, capture: bool = False, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        list(args),
        check=check,
        text=True,
        capture_output=capture,
        env=env,
    )


def pkg_root(name: str) -> Path:
    return DATA_ROOT / name


def install_root(name: str) -> Path:
    return pkg_root(name) / "install"


def config_root(name: str) -> Path:
    return pkg_root(name) / "config"


def runtime_state_root(name: str) -> Path:
    return pkg_root(name) / "state"


def rootfs_dir(name: str) -> Path:
    return install_root(name) / "rootfs"


def manifest_path(name: str) -> Path:
    return install_root(name) / "manifest.json"


def image_ref_path(name: str) -> Path:
    return install_root(name) / "image-ref"


def image_id_path(name: str) -> Path:
    return install_root(name) / "image-id"


def load_manifest(name: str) -> dict:
    return json.loads(manifest_path(name).read_text())


def ensure_dirs(name: str) -> None:
    install_root(name).mkdir(parents=True, exist_ok=True)
    config_root(name).mkdir(parents=True, exist_ok=True)
    runtime_state_root(name).mkdir(parents=True, exist_ok=True)


def ensure_image(ref: str) -> None:
    if ref.startswith("localhost/"):
        result = run("podman", "image", "exists", ref, check=False)
        if result.returncode != 0:
            raise SystemExit(f"local image not found: {ref}")
    else:
        run("podman", "pull", ref)


def image_id(ref: str) -> str:
    cp = run("podman", "image", "inspect", "--format", "{{.Id}}", ref, capture=True)
    return cp.stdout.strip()


def extract_rootfs(ref: str, dest: Path) -> None:
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True, exist_ok=True)
    container_name = f"desktoppak-{os.getpid()}"
    try:
        run("podman", "create", "--name", container_name, ref, "true")
        export = subprocess.Popen(["podman", "export", container_name], stdout=subprocess.PIPE, text=False)
        try:
            tar = subprocess.run(
                ["tar", "--extract", "--file", "-", "--directory", str(dest), "--no-same-owner", "--no-same-permissions"],
                stdin=export.stdout,
                check=True,
            )
            assert tar.returncode == 0
        finally:
            if export.stdout is not None:
                export.stdout.close()
            export.wait()
    finally:
        run("podman", "rm", "-f", container_name, check=False)


def cache_manifest(name: str) -> None:
    source = rootfs_dir(name) / "usr/share/desktoppak/manifest.json"
    if not source.is_file():
        raise SystemExit(f"missing manifest in rootfs: {source}")
    manifest_path(name).write_text(source.read_text())


def seed_config(name: str, overwrite: bool = False) -> None:
    manifest = load_manifest(name)
    for item in manifest.get("config", {}).get("seed", []):
        source = rootfs_dir(name) / item["source"].lstrip("/")
        target = item["target"]
        prefix = "/home/session/.config/"
        if not target.startswith(prefix):
            continue
        rel = target[len(prefix):]
        host_target = config_root(name) / rel
        if host_target.exists() and not overwrite:
            continue
        host_target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, host_target)


def install(args: argparse.Namespace) -> None:
    name = args.name
    ref = args.oci_ref
    root = pkg_root(name)
    if root.exists():
        manifest_ok = manifest_path(name).exists()
        if not manifest_ok:
            raise SystemExit(
                f"package already exists but appears incomplete: {name}\n"
                f"run: python3 image/desktoppak/desktoppak.py uninstall --force {name}"
            )
        raise SystemExit(f"package already exists: {name}")

    ensure_image(ref)
    tmp_root_parent = DATA_ROOT / f".{name}.tmp"
    if tmp_root_parent.exists():
        shutil.rmtree(tmp_root_parent)
    tmp_root_parent.mkdir(parents=True, exist_ok=True)
    try:
        (tmp_root_parent / "install").mkdir(parents=True, exist_ok=True)
        (tmp_root_parent / "config").mkdir(parents=True, exist_ok=True)
        (tmp_root_parent / "state").mkdir(parents=True, exist_ok=True)
        extract_rootfs(ref, tmp_root_parent / "install/rootfs")
        source_manifest = tmp_root_parent / "install/rootfs/usr/share/desktoppak/manifest.json"
        if not source_manifest.is_file():
            raise SystemExit(f"missing manifest in rootfs: {source_manifest}")
        (tmp_root_parent / "install/manifest.json").write_text(source_manifest.read_text())
        (tmp_root_parent / "install/image-ref").write_text(ref + "\n")
        (tmp_root_parent / "install/image-id").write_text(image_id(ref) + "\n")
        tmp_root_parent.rename(root)
        seed_config(name, overwrite=False)
    except Exception:
        if tmp_root_parent.exists():
            shutil.rmtree(tmp_root_parent, ignore_errors=True)
        raise
    print(f"installed {name} -> {root}")


def update(args: argparse.Namespace) -> None:
    name = args.name
    if not pkg_root(name).exists():
        raise SystemExit(f"not installed: {name}")
    ref = image_ref_path(name).read_text().strip()
    old_id = image_id_path(name).read_text().strip() if image_id_path(name).exists() else ""
    ensure_image(ref)
    new_id = image_id(ref)
    if new_id == old_id:
        print(f"{name} is already up to date")
        return
    with tempfile.TemporaryDirectory(prefix=f"desktoppak-{name}-") as td:
        tmp_rootfs = Path(td) / "rootfs"
        extract_rootfs(ref, tmp_rootfs)
        source_manifest = tmp_rootfs / "usr/share/desktoppak/manifest.json"
        if not source_manifest.is_file():
            raise SystemExit(f"missing manifest in rootfs: {source_manifest}")
        final_rootfs = rootfs_dir(name)
        backup = final_rootfs.with_name("rootfs.old")
        if backup.exists():
            shutil.rmtree(backup, ignore_errors=True)
        if final_rootfs.exists():
            final_rootfs.rename(backup)
        tmp_rootfs.rename(final_rootfs)
        if backup.exists():
            shutil.rmtree(backup, ignore_errors=True)
        manifest_path(name).write_text(source_manifest.read_text())
    image_id_path(name).write_text(new_id + "\n")
    print(f"updated {name}")


def uninstall(args: argparse.Namespace) -> None:
    name = args.name
    root = pkg_root(name)
    if not root.exists():
        raise SystemExit(f"not installed: {name}")
    desktop = SESSIONS_DIR / f"desktoppak-{name}.desktop"
    if desktop.exists() and not args.force:
        raise SystemExit(f"{name} is still registered; unregister first or use --force")
    try:
        shutil.rmtree(root)
    except PermissionError as e:
        raise SystemExit(
            f"failed to remove {root}: {e}\n"
            f"This usually means an older extract preserved root ownership.\n"
            f"Recovery:\n"
            f"  sudo rm -rf {root}"
        )
    print(f"uninstalled {name}")


def list_cmd(_: argparse.Namespace) -> None:
    DATA_ROOT.mkdir(parents=True, exist_ok=True)
    rows: list[tuple[str, str, str, str]] = []
    for child in sorted(DATA_ROOT.iterdir()):
        if not child.is_dir():
            continue
        name = child.name
        display = name
        ref = "?"
        registered = "no"
        mp = manifest_path(name)
        if mp.exists():
            try:
                display = json.loads(mp.read_text()).get("display_name", name)
            except Exception:
                pass
        rp = image_ref_path(name)
        if rp.exists():
            ref = rp.read_text().strip()
        if (SESSIONS_DIR / f"desktoppak-{name}.desktop").exists():
            registered = "yes"
        rows.append((name, display, ref, registered))
    if not rows:
        print("no packages installed")
        return
    print(f"{'NAME':<16} {'DISPLAY NAME':<24} {'OCI REF':<40} REGISTERED")
    for name, display, ref, registered in rows:
        print(f"{name:<16} {display:<24} {ref:<40} {registered}")


def register(args: argparse.Namespace) -> None:
    name = args.name
    if args.dm != "gdm":
        raise SystemExit("only --dm gdm is supported in v1")
    manifest = load_manifest(name)
    display_name = manifest.get("display_name", name)
    wrapper = f"#!/usr/bin/env bash\nexec {shlex_quote(sys.executable)} {shlex_quote(str(Path(__file__).resolve()))} \"$@\"\n"
    desktop = f"[Desktop Entry]\nName={display_name}\nGenericName=Wayland Compositor\nComment=desktoppak session: {name}\nExec=/usr/local/bin/desktoppak launch {name}\nTryExec=/usr/local/bin/desktoppak\nType=Application\nDesktopNames={manifest.get('name', name)}\n"
    run("sudo", "install", "-d", str(WRAPPER_PATH.parent), str(SESSIONS_DIR))
    subprocess.run(["sudo", "tee", str(WRAPPER_PATH)], input=wrapper, text=True, check=True, stdout=subprocess.DEVNULL)
    run("sudo", "chmod", "0755", str(WRAPPER_PATH))
    desktop_path = SESSIONS_DIR / f"desktoppak-{name}.desktop"
    subprocess.run(["sudo", "tee", str(desktop_path)], input=desktop, text=True, check=True, stdout=subprocess.DEVNULL)
    run("sudo", "chmod", "0644", str(desktop_path))
    print(f"registered {name} for {args.dm}")


def unregister(args: argparse.Namespace) -> None:
    name = args.name
    if args.dm != "gdm":
        raise SystemExit("only --dm gdm is supported in v1")
    desktop_path = SESSIONS_DIR / f"desktoppak-{name}.desktop"
    run("sudo", "rm", "-f", str(desktop_path))
    print(f"unregistered {name} for {args.dm}")


def launch(args: argparse.Namespace) -> None:
    name = args.name
    if not pkg_root(name).exists():
        raise SystemExit(f"not installed: {name}")
    env = os.environ.copy()
    env["DESKTOP_BLUEPRINT_ROOTFS_DIR"] = str(rootfs_dir(name))
    env["DESKTOP_BLUEPRINT_STATE_ROOT"] = str(runtime_state_root(name))
    env["DESKTOPPAK_CONFIG_ROOT"] = str(config_root(name))
    os.execvpe(str(LAUNCH_SCRIPT), [str(LAUNCH_SCRIPT)], env)


def shlex_quote(s: str) -> str:
    import shlex
    return shlex.quote(s)


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="desktoppak")
    sp = p.add_subparsers(dest="cmd", required=True)

    a = sp.add_parser("install")
    a.add_argument("name")
    a.add_argument("oci_ref")
    a.set_defaults(func=install)

    a = sp.add_parser("update")
    a.add_argument("name")
    a.set_defaults(func=update)

    a = sp.add_parser("uninstall")
    a.add_argument("name")
    a.add_argument("--force", action="store_true")
    a.set_defaults(func=uninstall)

    a = sp.add_parser("list")
    a.set_defaults(func=list_cmd)

    a = sp.add_parser("register")
    a.add_argument("name")
    a.add_argument("--dm", required=True)
    a.set_defaults(func=register)

    a = sp.add_parser("unregister")
    a.add_argument("name")
    a.add_argument("--dm", required=True)
    a.set_defaults(func=unregister)

    a = sp.add_parser("launch")
    a.add_argument("name")
    a.set_defaults(func=launch)

    return p


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    DATA_ROOT.mkdir(parents=True, exist_ok=True)
    STATE_ROOT.mkdir(parents=True, exist_ok=True)
    args.func(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
