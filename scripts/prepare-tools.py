#!/usr/bin/env python3
"""Build-time only. Package verified standalone tools; end users run no installer."""
import hashlib
import json
import os
import shutil
import subprocess
import tarfile
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / ".tool-build"
HELPERS = ROOT / "dist/YT2DL.app/Contents/Helpers"
NOTICES = ROOT / "dist/YT2DL.app/Contents/Resources/ThirdParty"
SOURCES = NOTICES / "Sources"
PREFIX = WORK / "prefix"
for p in [WORK, HELPERS, NOTICES, SOURCES, PREFIX]:
    p.mkdir(parents=True, exist_ok=True)

def fetch(url, path):
    print("Downloading", url, flush=True)
    req = urllib.request.Request(url, headers={"User-Agent": "YT2DL-build/1.1"})
    with urllib.request.urlopen(req, timeout=180) as source, open(path, "wb") as target:
        shutil.copyfileobj(source, target)
    return path

def verified(url, path, sha):
    if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != sha:
        fetch(url, path)
    if hashlib.sha256(path.read_bytes()).hexdigest() != sha:
        raise RuntimeError("SHA256 mismatch: " + str(path))
    return path

def run(args, cwd=None, env=None):
    print("+", " ".join(map(str, args)), flush=True)
    subprocess.run(list(map(str, args)), cwd=cwd, env=env, check=True)

yt_version = "2026.10.26"
yt_base = f"https://github.com/yt-dlp/yt-dlp/releases/download/{yt_version}"
sums = fetch(yt_base + "/SHA2-256SUMS", WORK / "yt-SHA256SUMS").read_text()
yt_sha = next(line.split()[0] for line in sums.splitlines() if line.split()[-1].lstrip("*") == "yt-dlp_macos")
verified(yt_base + "/yt-dlp_macos", HELPERS / "yt-dlp", yt_sha)
fetch(f"https://raw.githubusercontent.com/yt-dlp/yt-dlp/{yt_version}/THIRD_PARTY_LICENSES.txt", NOTICES / "yt-dlp-THIRD_PARTY_LICENSES.txt")
fetch(f"https://raw.githubusercontent.com/yt-dlp/yt-dlp/{yt_version}/LICENSE", NOTICES / "yt-dlp-LICENSE")
fetch(yt_base + "/yt-dlp.tar.gz", SOURCES / f"yt-dlp-{yt_version}.tar.gz")

deno_version = "v2.9.8"
deno_arch = "aarch64" if os.uname().machine == "arm64" else "x86_64"
asset = f"deno-{deno_arch}-apple-darwin.zip"
base = f"https://github.com/denoland/deno/releases/download/{deno_version}"
deno_sha = fetch(base + "/" + asset + ".sha256sum", WORK / "deno-SHA256SUMS").read_text().split()[0]
archive = verified(base + "/" + asset, WORK / asset, deno_sha)
with zipfile.ZipFile(archive) as z:
    with z.open("deno") as source, open(HELPERS / "deno", "wb") as target:
        shutil.copyfileobj(source, target)
fetch(f"https://raw.githubusercontent.com/denoland/deno/{deno_version}/LICENSE.md", NOTICES / "deno-LICENSE.md")

# Build a small, standalone LGPL FFmpeg. No Homebrew dylibs in the deliverable.
# Homebrew is used on the build machine only for source URLs and SHA256 metadata.
formulae = json.loads(subprocess.check_output(["brew", "info", "--json=v2", "lame", "opus", "ffmpeg"]))["formulae"]
manifest = {"yt-dlp": yt_version, "deno": deno_version, "sources": []}
env = dict(os.environ, MACOSX_DEPLOYMENT_TARGET="14.0")
env["PKG_CONFIG_PATH"] = str(PREFIX / "lib/pkgconfig")
env["PKG_CONFIG_LIBDIR"] = str(PREFIX / "lib/pkgconfig")
jobs = str(min(os.cpu_count() or 2, 4))
for name in ["lame", "opus", "ffmpeg"]:
    formula = next(f for f in formulae if f["name"] == name)
    stable = formula["urls"]["stable"]
    source = verified(stable["url"], WORK / Path(stable["url"]).name, stable["checksum"])
    shutil.copy2(source, SOURCES / source.name)
    dest = WORK / ("src-" + name)
    if not dest.exists():
        dest.mkdir()
        with tarfile.open(source) as tar:
            # All tar inputs are public, checksummed source archives.
            tar.extractall(dest, filter="data")
    src = next(p for p in dest.iterdir() if p.is_dir())
    manifest["sources"].append({"name": name, "version": formula["versions"]["stable"], "url": stable["url"], "sha256": stable["checksum"], "license": formula["license"]})
    if name == "lame":
        run(["./configure", "--prefix=" + str(PREFIX), "--disable-shared", "--enable-static", "--disable-frontend"], src, env)
    elif name == "opus":
        run(["./configure", "--prefix=" + str(PREFIX), "--disable-shared", "--enable-static", "--disable-extra-programs", "--disable-doc"], src, env)
    else:
        run(["./configure", "--prefix=" + str(PREFIX), "--disable-autodetect", "--disable-shared", "--enable-static",
             "--disable-gpl", "--disable-nonfree", "--disable-doc", "--disable-debug", "--disable-network",
             "--disable-avdevice", "--disable-ffplay", "--enable-libmp3lame", "--enable-libopus",
             "--pkg-config-flags=--static", "--extra-cflags=-I" + str(PREFIX / "include"),
             "--extra-ldflags=-L" + str(PREFIX / "lib"),
             "--disable-encoders", "--enable-encoder=aac,alac,flac,libmp3lame,libopus,pcm_s16le,pcm_s24le,pcm_s32le,pcm_f32le",
             "--disable-decoders", "--enable-decoder=aac,aac_fixed,aac_latm,alac,flac,mp3,mp3float,opus,vorbis,pcm_s16le,pcm_s24le,pcm_s32le,pcm_f32le"], src, env)
    run(["make", "-j" + jobs], src, env)
    run(["make", "install"], src, env)
    for pattern in ["COPYING*", "LICENSE*", "AUTHORS"]:
        for file in src.glob(pattern):
            if file.is_file():
                shutil.copy2(file, NOTICES / (name + "-" + file.name))
for name in ["ffmpeg", "ffprobe"]:
    shutil.copy2(PREFIX / "bin" / name, HELPERS / name)

(NOTICES / "versions.json").write_text(json.dumps(manifest, indent=2))
shutil.copy2(__file__, NOTICES / "prepare-tools.py")
(NOTICES / "README.txt").write_text(
    "YT2DL All-in-One bundles independent helper executables.\n"
    "yt-dlp macOS executable: GPLv3+ combined distribution; see upstream third-party notices.\n"
    "Deno: MIT; https://github.com/denoland/deno/tree/" + deno_version + "\n"
    "FFmpeg: LGPL build, GPL/nonfree disabled; LAME and Opus statically linked.\n"
    "Corresponding FFmpeg/LAME/Opus source archives and exact build recipe are in this directory.\n"
    "Build tools required only by developers, never by end users.\n")
for p in HELPERS.iterdir():
    p.chmod(0o755)
    deps = subprocess.check_output(["otool", "-L", str(p)], text=True)
    if "/opt/homebrew/" in deps or "/usr/local/" in deps:
        raise RuntimeError("External library in helper: " + deps)
    run(["codesign", "--force", "--sign", "-", "--preserve-metadata=entitlements", p])
print("Bundled standalone tools ready", flush=True)
