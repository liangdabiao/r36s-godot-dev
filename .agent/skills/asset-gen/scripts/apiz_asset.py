#!/usr/bin/env python3
"""apiz-first asset generation with resumable tasks and JSON output."""

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import tomllib
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

DEFAULT_IMAGE_MODEL = "apiz/gpt-image-2.6-flare"
DEFAULT_VIDEO_MODEL = "minimax/h3"
SEEDANCE_VIDEO_MODEL = "st-ai/super-seed2"
DEFAULT_MUSIC_MODEL = "minimax/music-gen"
DEFAULT_TTS_MODEL = "speech-2.8-hd"
DEFAULT_WAIT_TIMEOUT = 3600
TERMINAL = {"completed", "failed"}
IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".svg"}
VIDEO_SUFFIXES = {".mp4", ".webm", ".mov"}
AUDIO_SUFFIXES = {".mp3", ".wav", ".ogg", ".flac", ".m4a"}
MEDIA_SUFFIXES = IMAGE_SUFFIXES | VIDEO_SUFFIXES | AUDIO_SUFFIXES
H3_UPLOAD_TYPES = {
    "first_frame": ("image_url", "first_frame"),
    "last_frame": ("image_url", "last_frame"),
    "reference_image": ("image_url", "reference_image"),
    "reference_video": ("video_url", "reference_video"),
    "reference_audio": ("audio_url", "reference_audio"),
    "image_url": ("image_url", "reference_image"),
    "video_url": ("video_url", "reference_video"),
    "audio_url": ("audio_url", "reference_audio"),
}


class ApizError(RuntimeError):
    pass


def emit(ok, **data):
    print(json.dumps({"ok": ok, **data}, ensure_ascii=False))


def json_hash(value):
    raw = json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(raw.encode()).hexdigest()


def find_apiz(explicit=None):
    candidates = [explicit, os.environ.get("APIZ_BIN"), shutil.which("apiz"), shutil.which("apiz-cli")]
    home_candidates = [Path.home() / ".local/bin/apiz.exe", Path.home() / ".local/bin/apiz"]
    for item in [*candidates, *home_candidates]:
        if not item:
            continue
        path = Path(item).expanduser()
        if path.is_file():
            return path.resolve()
    raise ApizError("apiz executable not found; set APIZ_BIN or install from https://apiz.ai/cli")


def profile_settings(args):
    config = Path(args.config).expanduser() if args.config else Path.home() / ".config/apiz/config.toml"
    data = tomllib.loads(config.read_text(encoding="utf-8")) if config.exists() else {}
    name = args.profile or data.get("default_profile", "default")
    profile = data.get("profile", {}).get(name, {})
    key = profile.get("api_key") or os.environ.get("APIZ_API_KEY")
    base = args.base_url or profile.get("base_url") or os.environ.get("APIZ_BASE_URL") or "https://api.apiz.ai"
    return key, base.rstrip("/")


def run_apiz(apiz, args, cli_args, timeout=180, allow_text=False):
    command = [str(apiz), "--json"]
    for key, flag in (("profile", "--profile"), ("config", "--config"), ("base_url", "--base-url")):
        value = getattr(args, key, None)
        if value:
            command += [flag, str(value)]
    if timeout > 180:
        command += ["--timeout", f"{timeout}s"]
    command += cli_args
    try:
        proc = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        raise ApizError(f"apiz command timed out after {timeout}s") from exc
    except OSError as exc:
        raise ApizError(f"cannot run apiz: {exc}") from exc
    if proc.returncode:
        message = proc.stderr.strip() or proc.stdout.strip() or f"apiz exited {proc.returncode}"
        raise ApizError(message)
    text = proc.stdout.strip()
    if not text:
        return "" if allow_text else {}
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        for line in reversed(text.splitlines()):
            try:
                return json.loads(line)
            except json.JSONDecodeError:
                pass
    if allow_text:
        return text
    raise ApizError("apiz returned invalid JSON")


def upload_file(apiz, args, path):
    source = Path(path).expanduser()
    if not source.is_file():
        raise ApizError(f"upload file not found: {source}")
    data = run_apiz(apiz, args, ["upload", str(source), "--folder", args.folder], timeout=300)
    url = data.get("public_url")
    if not url:
        raise ApizError(f"upload returned no public_url for {source}")
    return url


def task_id(task):
    value = task.get("task_id") if isinstance(task, dict) else None
    if not value:
        raise ApizError("apiz returned no task_id")
    return str(value)


def sidecar_path(output):
    return output.with_name(output.name + ".apiz.json")


def read_sidecar(output):
    path = sidecar_path(output)
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else None


def write_sidecar(output, data):
    output.parent.mkdir(parents=True, exist_ok=True)
    path = sidecar_path(output)
    temp = path.with_name(path.name + ".tmp")
    temp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(temp, path)


def media_urls(value):
    found = []

    def walk(item):
        if isinstance(item, str):
            if item.startswith(("http://", "https://")):
                found.append(item)
        elif isinstance(item, dict):
            for child in item.values():
                walk(child)
        elif isinstance(item, list):
            for child in item:
                walk(child)

    walk(value)
    unique = list(dict.fromkeys(found))
    return sorted(unique, key=lambda url: Path(urllib.parse.urlparse(url).path).suffix.lower() not in MEDIA_SUFFIXES)


def voice_id_from(value):
    if isinstance(value, dict):
        direct = value.get("voice_id")
        if direct:
            return str(direct)
        for child in value.values():
            found = voice_id_from(child)
            if found:
                return found
    elif isinstance(value, list):
        for child in value:
            found = voice_id_from(child)
            if found:
                return found
    return None


def cost_fields(task):
    price = task.get("price") if isinstance(task, dict) else None
    return {"price_credits": price, "cost_cents": price, "cost_unit": "credits; 100 credits = 1 yuan"}


def download_file(url, output):
    output.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": "apiz-asset-wrapper/1"})
    temp = output.with_name(output.name + ".part")
    try:
        with urllib.request.urlopen(request, timeout=300) as response, temp.open("wb") as handle:
            shutil.copyfileobj(response, handle)
        if not temp.exists() or temp.stat().st_size == 0:
            raise ApizError(f"downloaded empty file: {url}")
        os.replace(temp, output)
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        temp.unlink(missing_ok=True)
        raise ApizError(f"download failed: {exc}") from exc
    return output


def convert_audio(source, output):
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise ApizError("ffmpeg is required for .ogg/.wav/.flac output")
    codec = {".ogg": ["-c:a", "libvorbis", "-q:a", "6"], ".wav": ["-c:a", "pcm_s16le"], ".flac": ["-c:a", "flac"]}[output.suffix.lower()]
    proc = subprocess.run([ffmpeg, "-v", "error", "-y", "-i", str(source), *codec, str(output)], capture_output=True, text=True)
    if proc.returncode:
        raise ApizError(f"ffmpeg conversion failed: {proc.stderr.strip()}")


def save_task_results(task, output, kind):
    result = task.get("result") or {}
    urls = media_urls(result)
    allowed = {"image": IMAGE_SUFFIXES, "video": VIDEO_SUFFIXES, "audio": AUDIO_SUFFIXES}[kind]
    matching = [url for url in urls if Path(urllib.parse.urlparse(url).path).suffix.lower() in allowed]
    if matching:
        urls = matching
    else:
        unknown = [url for url in urls if Path(urllib.parse.urlparse(url).path).suffix.lower() not in MEDIA_SUFFIXES]
        urls = unknown or urls
    if not urls:
        raise ApizError("completed task returned no downloadable media URL")
    paths = []
    for index, url in enumerate(urls):
        target = output if index == 0 else output.with_name(f"{output.stem}_{index + 1}{output.suffix}")
        if kind == "audio" and output.suffix.lower() != ".mp3":
            with tempfile.TemporaryDirectory() as tmp:
                source = download_file(url, Path(tmp) / "audio.mp3")
                convert_audio(source, target)
        else:
            download_file(url, target)
        paths.append(str(target))
    return paths


def poll_task(apiz, args, identifier, initial=None, quiet=False):
    if args.wait_timeout < 0:
        raise ApizError("--wait-timeout must be zero or positive")
    if args.poll <= 0:
        raise ApizError("--poll must be positive")
    current = initial or run_apiz(apiz, args, ["tasks", "get", identifier])
    last = None
    deadline = time.monotonic() + args.wait_timeout
    while current.get("status") not in TERMINAL:
        status = current.get("status", "unknown")
        progress = current.get("progress")
        marker = f"{status} {progress}%" if progress is not None else status
        if not quiet and marker != last:
            print(f"task {identifier}: {marker}", file=sys.stderr)
            last = marker
        if time.monotonic() >= deadline:
            raise ApizError(f"task {identifier} still {status} after {args.wait_timeout}s; rerun to resume")
        time.sleep(args.poll)
        current = run_apiz(apiz, args, ["tasks", "get", identifier])
    return current


def task_result(output, task, paths=None, note=None):
    data = {
        "path": str(output) if paths is None else paths[0],
        "files": paths,
        "task_id": task.get("task_id"),
        "status": task.get("status"),
        "model": task.get("model"),
        **cost_fields(task),
    }
    voice = voice_id_from(task.get("result"))
    if voice:
        data["voice_id"] = voice
    if task.get("error"):
        data["error"] = task["error"]
    if note:
        data["note"] = note
    return data


def generate_asset(apiz, args, model, prompt, output, params, kind, uploads=None, content_uploads=None):
    output = Path(output).expanduser().resolve()
    uploads = uploads or {}
    if content_uploads is not None:
        content_uploads = [
            {**item, "path": str(Path(item["path"]).expanduser().resolve())}
            for item in content_uploads
        ]
    request = {
        "model": model,
        "prompt": prompt,
        "params": params,
        "uploads": {key: [str(Path(value).expanduser().resolve()) for value in values] for key, values in uploads.items()},
        "output": str(output),
        "kind": kind,
    }
    if content_uploads is not None:
        request["content_uploads"] = content_uploads
    request_hash = json_hash(request)
    state = read_sidecar(output)
    if state and not args.force:
        if state.get("request_hash") != request_hash:
            raise ApizError(f"existing task state does not match this request: {sidecar_path(output)}")
        identifier = state.get("task_id")
        if not identifier:
            raise ApizError(f"existing task state has no task_id: {sidecar_path(output)}")
        current = poll_task(apiz, args, identifier, initial=state.get("task") or None)
        merged = {**state.get("submitted", {}), **current}
        state.update(task=merged, status=merged.get("status"))
        write_sidecar(output, state)
        if merged.get("status") == "failed":
            raise ApizError(f"task {identifier} failed: {merged.get('error') or 'unknown error'}")
        if output.exists():
            return task_result(output, merged, state.get("files") or [str(output)], note="already downloaded")
        paths = save_task_results(merged, output, kind)
        state.update(files=paths, status="completed")
        write_sidecar(output, state)
        return task_result(output, merged, paths)

    if output.exists() and not args.force:
        raise ApizError(f"output exists: {output}; use --force for a new paid task")
    final_params = dict(params)
    if content_uploads is not None:
        final_params.pop("prompt", None)
        content = [{"type": "text", "text": prompt}]
        for item in content_uploads:
            url = upload_file(apiz, args, item["path"])
            media = {"type": item["type"], item["type"]: {"url": url}}
            if item.get("role"):
                media["role"] = item["role"]
            content.append(media)
        final_params["content"] = content
    elif "content" in final_params:
        final_params.pop("prompt", None)
    else:
        final_params["prompt"] = prompt
    for key, values in uploads.items():
        final_params[key] = [upload_file(apiz, args, value) for value in values]
    submitted = run_apiz(apiz, args, ["generate", prompt, "--model", model, "--params", json.dumps(final_params, ensure_ascii=False)], timeout=300)
    identifier = task_id(submitted)
    state = {
        "schema_version": 1,
        "request_hash": request_hash,
        "model": model,
        "prompt": prompt,
        "params": final_params,
        "task_id": identifier,
        "submitted": submitted,
        "task": submitted,
        "status": submitted.get("status"),
        "output": str(output),
        "kind": kind,
        "created_at": submitted.get("created_at"),
    }
    write_sidecar(output, state)
    if args.no_wait:
        return {"path": str(output), "state": str(sidecar_path(output)), **task_result(output, submitted), "note": "submitted; rerun the same command or use task TASK_ID -o OUTPUT"}
    current = poll_task(apiz, args, identifier, initial=submitted)
    merged = {**submitted, **current}
    state.update(task=merged, status=merged.get("status"), completed_at=merged.get("completed_at"))
    write_sidecar(output, state)
    if merged.get("status") == "failed":
        raise ApizError(f"task {identifier} failed: {merged.get('error') or 'unknown error'}; state: {sidecar_path(output)}")
    paths = save_task_results(merged, output, kind)
    state.update(files=paths, status="completed")
    write_sidecar(output, state)
    return task_result(output, merged, paths)


def parse_extra(value):
    if not value:
        return {}
    if isinstance(value, dict):
        return value
    if not isinstance(value, str):
        raise ApizError("--params must be a JSON object")
    try:
        data = json.loads(value)
    except json.JSONDecodeError as exc:
        raise ApizError(f"--params must be a JSON object: {exc}") from exc
    if not isinstance(data, dict):
        raise ApizError("--params must be a JSON object")
    return data


def path_list(value):
    if not value:
        return []
    return [value] if isinstance(value, str) else list(value)


def image_job(job, args):
    prompt = job.get("prompt")
    output = job.get("o") or job.get("output")
    if not prompt or not output:
        raise ApizError("image job needs prompt and o")
    output = Path(output)
    suffix = output.suffix.lower()
    formats = {".png": "png", ".jpg": "jpeg", ".jpeg": "jpeg", ".webp": "webp", ".gif": "gif", ".svg": "svg"}
    if suffix not in formats:
        raise ApizError("image output must be .png .jpg .jpeg .webp .gif or .svg")
    refs = job.get("image") or job.get("references") or []
    if isinstance(refs, str):
        refs = [refs]
    if len(refs) > 16:
        raise ApizError("Flare accepts at most 16 reference images")
    transparent = bool(job.get("transparent", False))
    if transparent and suffix != ".png":
        raise ApizError("--transparent requires .png output")
    params = {
        "quality": job.get("quality", "medium"),
        "aspect_ratio": job.get("aspect_ratio", "1:1"),
        "size": job.get("size", "1K"),
        "output_format": formats[suffix],
        "complexity": job.get("complexity", "high"),
    }
    size = str(params["size"])
    if re.fullmatch(r"\d+x\d+", size, re.IGNORECASE):
        width, height = size.lower().split("x")
        params.pop("aspect_ratio")
        params.pop("size")
        params["width"], params["height"] = int(width), int(height)
    if transparent:
        params["transparency"] = True
    if suffix == ".gif":
        if refs:
            raise ApizError("GIF generation is text-to-image only; do not pass references")
        params["frame_count"] = job.get("frames", 9)
        params["frame_duration_ms"] = job.get("frame_ms", 200)
    if suffix == ".svg" and refs:
        raise ApizError("SVG generation is text-to-image only; do not pass references")
    params.update(parse_extra(job.get("params")))
    params["output_format"] = formats[suffix]
    if suffix == ".gif":
        if not 2 <= int(params["frame_count"]) <= 9:
            raise ApizError("GIF frame_count must be 2-9 in the current schema")
        if not 20 <= int(params["frame_duration_ms"]) <= 2000:
            raise ApizError("GIF frame_duration_ms must be 20-2000")
    params["prompt"] = prompt
    uploads = {"reference_image_urls": refs} if refs else {}
    return generate_asset(find_apiz(args.apiz), args, job.get("model", DEFAULT_IMAGE_MODEL), prompt, output, params, "image", uploads)


def h3_params(prompt, options, content_uploads):
    if len(prompt) > 7000:
        raise ApizError("H3 text content must contain at most 7000 characters")
    params = {
        "resolution": options.get("resolution") or "768P",
        "duration": options.get("duration") if options.get("duration") is not None else 5,
        "ratio": options.get("aspect_ratio") or options.get("ratio") or ("adaptive" if content_uploads else "16:9"),
    }
    extra = parse_extra(options.get("params"))
    if "prompt" in extra or "content" in extra:
        raise ApizError("H3 uses content; set the prompt and media with the dedicated options, not --params")
    if any(key in extra for key in ("model", "functionMode", "filePaths", "image_files", "video_files", "audio_files")):
        raise ApizError("Seedance-only params cannot be used with H3")
    params.update(extra)
    if params.get("resolution") not in {"480p", "768P", "1080p", "2K"}:
        raise ApizError("H3 resolution must be 480p, 768P, 1080p or 2K")
    duration = params.get("duration")
    if isinstance(duration, bool) or not isinstance(duration, int):
        raise ApizError("H3 duration must be an integer from 4 to 15 seconds")
    if not 4 <= duration <= 15:
        raise ApizError("H3 duration must be 4-15 seconds")
    params["duration"] = duration
    if params.get("ratio") not in {"adaptive", "21:9", "16:9", "4:3", "1:1", "3:4", "9:16"}:
        raise ApizError("H3 ratio must be adaptive, 21:9, 16:9, 4:3, 1:1, 3:4 or 9:16")
    if params["ratio"] == "adaptive" and not content_uploads:
        raise ApizError("H3 text-to-video cannot use adaptive ratio; choose an explicit ratio")
    return params


def h3_content_uploads(job):
    first = path_list(job.get("first_frame"))
    last = path_list(job.get("last_frame"))
    images = path_list(job.get("image"))
    if images:
        if first or last:
            raise ApizError("use either --image or --first-frame/--last-frame, not both")
        if len(images) > 2:
            raise ApizError("--image accepts at most two H3 frames; use --reference-image for extra references")
        first, last = images[:1], images[1:2]
    if len(first) > 1 or len(last) > 1:
        raise ApizError("H3 first_frame and last_frame each accept one image")
    content = []
    if first:
        content.append({"type": "image_url", "role": "first_frame", "path": first[0]})
    if last:
        content.append({"type": "image_url", "role": "last_frame", "path": last[0]})
    for singular, plural, media_type, role in (
        ("reference_image", "reference_images", "image_url", "reference_image"),
        ("reference_video", "reference_videos", "video_url", "reference_video"),
        ("reference_audio", "reference_audios", "audio_url", "reference_audio"),
    ):
        for path in path_list(job.get(singular)) + path_list(job.get(plural)):
            content.append({"type": media_type, "role": role, "path": path})
    return content


def h3_video_job(job, args, prompt, output):
    if job.get("variant"):
        raise ApizError("--variant is Seedance-only; H3 uses --resolution")
    content_uploads = h3_content_uploads(job)
    params = h3_params(prompt, job, content_uploads)
    return generate_asset(find_apiz(args.apiz), args, DEFAULT_VIDEO_MODEL, prompt, output, params, "video", content_uploads=content_uploads)


def seedance_video_job(job, args, prompt, output):
    h3_keys = ("first_frame", "last_frame", "reference_image", "reference_images", "reference_video", "reference_videos", "reference_audio", "reference_audios", "resolution")
    if any(job.get(key) for key in h3_keys):
        raise ApizError("H3 frame, reference and resolution options require --model minimax/h3")
    refs = path_list(job.get("image"))
    if len(refs) > 2:
        raise ApizError("Seedance first/last-frame mode accepts at most 2 images; use generate --upload for Omni references")
    duration = int(job.get("duration", 5))
    if not 4 <= duration <= 15:
        raise ApizError("Seedance 2 duration must be 4-15 seconds")
    variant = job.get("variant") or "fast"
    variants = {"fast": "seedance_2.0_fast", "fast_vip": "seedance_2.0_fast_vip", "standard": "seedance_2.0", "standard_vip": "seedance_2.0_vip"}
    if variant not in variants:
        raise ApizError(f"unknown Seedance variant: {variant}")
    params = {"model": variants[variant], "functionMode": "first_last_frames", "ratio": job.get("aspect_ratio") or job.get("ratio") or "16:9", "duration": duration}
    extra = parse_extra(job.get("params"))
    if extra.get("functionMode", "first_last_frames") != "first_last_frames":
        raise ApizError("Seedance video helper supports first_last_frames only; use generate for Omni references")
    if any(key in extra for key in ("image_files", "video_files", "audio_files")):
        raise ApizError("Seedance Omni reference arrays require generate --upload, not video --params")
    params.update(extra)
    if params.get("ratio") not in {"21:9", "16:9", "4:3", "1:1", "3:4", "9:16"}:
        raise ApizError("Seedance 2 ratio must be 21:9, 16:9, 4:3, 1:1, 3:4 or 9:16")
    if not 4 <= int(params["duration"]) <= 15:
        raise ApizError("Seedance 2 duration must be 4-15 seconds")
    params["prompt"] = prompt
    return generate_asset(find_apiz(args.apiz), args, SEEDANCE_VIDEO_MODEL, prompt, output, params, "video", {"filePaths": refs} if refs else {})


def video_job(job, args):
    prompt = job.get("prompt")
    output = job.get("o") or job.get("output")
    if not prompt or not output:
        raise ApizError("video job needs prompt and o")
    output = Path(output)
    if output.suffix.lower() != ".mp4":
        raise ApizError("video output must be .mp4")
    model = job.get("model") or DEFAULT_VIDEO_MODEL
    if model == DEFAULT_VIDEO_MODEL:
        return h3_video_job(job, args, prompt, output)
    if model == SEEDANCE_VIDEO_MODEL:
        return seedance_video_job(job, args, prompt, output)
    raise ApizError(f"unsupported video helper model: {model}; use minimax/h3, st-ai/super-seed2 or generate")


def music_job(job, args):
    prompt = job.get("prompt")
    output = job.get("o") or job.get("output")
    if not prompt or not output:
        raise ApizError("music job needs prompt and o")
    output = Path(output)
    if output.suffix.lower() not in {".mp3", ".ogg", ".wav", ".flac"}:
        raise ApizError("music output must be .mp3 .ogg .wav or .flac")
    lyrics = job.get("lyrics", "[Inst]\nInstrumental")
    if len(prompt) > 2000:
        raise ApizError("music style prompt must contain at most 2000 characters")
    params = {"lyrics": lyrics, "model": job.get("music_model", "music-2.5"), "stream": False, "output_format": "url"}
    params.update(parse_extra(job.get("params")))
    params["stream"] = False
    params["output_format"] = "url"
    lyrics = params.get("lyrics")
    if not isinstance(lyrics, str) or not lyrics.strip() or len(lyrics) > 3500:
        raise ApizError("music lyrics must contain 1-3500 characters")
    params["prompt"] = prompt
    return generate_asset(find_apiz(args.apiz), args, job.get("model", DEFAULT_MUSIC_MODEL), prompt, output, params, "audio")


def cmd_doctor(args):
    apiz = find_apiz(args.apiz)
    version = run_apiz(apiz, args, ["--version"], allow_text=True)
    key, _ = profile_settings(args)
    balance = run_apiz(apiz, args, ["account", "balance"]) if key else None
    emit(True, apiz=str(apiz), version=version, configured=bool(key), balance=balance, ffmpeg=bool(shutil.which("ffmpeg")), defaults={"image": DEFAULT_IMAGE_MODEL, "video": DEFAULT_VIDEO_MODEL, "music": DEFAULT_MUSIC_MODEL, "speech": DEFAULT_TTS_MODEL})


def cmd_models(args):
    apiz = find_apiz(args.apiz)
    command = ["models", "list"]
    if args.category:
        command += ["--category", args.category]
    data = run_apiz(apiz, args, command)
    models = data if isinstance(data, list) else data.get("models", [])
    if args.search:
        needle = args.search.casefold()
        models = [m for m in models if needle in f"{m.get('id', '')} {m.get('name', '')}".casefold()]
    emit(True, models=models)


def cmd_docs(args):
    key, base = profile_settings(args)
    if not key:
        raise ApizError("no apiz API key found; run apiz auth login")
    url = f"{base}/api/v3/models/{urllib.parse.quote(args.model, safe='/')}/docs?lang=en"
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {key}", "User-Agent": "apiz-asset-wrapper/1", "Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            payload = json.load(response)
    except (urllib.error.URLError, TimeoutError) as exc:
        raise ApizError(f"model docs request failed: {exc}") from exc
    emit(True, docs=payload.get("data", payload))


def cmd_upload(args):
    emit(True, path=str(Path(args.file).expanduser()), url=upload_file(find_apiz(args.apiz), args, args.file))


def cmd_image(args):
    emit(True, **image_job(vars(args), args))


def cmd_video(args):
    emit(True, **video_job(vars(args), args))


def cmd_music(args):
    emit(True, **music_job(vars(args), args))


def cmd_generate(args):
    output = Path(args.output)
    if args.kind == "image" and output.suffix.lower() not in IMAGE_SUFFIXES:
        raise ApizError("unsupported image output extension")
    if args.kind == "video" and output.suffix.lower() != ".mp4":
        raise ApizError("video output must be .mp4")
    if args.kind == "audio" and output.suffix.lower() not in {".mp3", ".ogg", ".wav", ".flac"}:
        raise ApizError("audio output must be .mp3 .ogg .wav or .flac")
    uploads = {}
    for item in args.upload or []:
        if "=" not in item:
            raise ApizError("--upload takes KEY=PATH")
        key, value = item.split("=", 1)
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key) or not value:
            raise ApizError("--upload takes KEY=PATH with a valid parameter key")
        uploads.setdefault(key, []).append(value)
    if args.model == DEFAULT_VIDEO_MODEL and args.kind == "video":
        content_uploads = []
        for key, values in uploads.items():
            if key not in H3_UPLOAD_TYPES:
                raise ApizError(f"unsupported H3 upload key: {key}; use first_frame, last_frame, reference_image, reference_video or reference_audio")
            if key in {"first_frame", "last_frame"} and len(values) > 1:
                raise ApizError(f"H3 {key} accepts one file")
            media_type, role = H3_UPLOAD_TYPES[key]
            content_uploads.extend({"type": media_type, "role": role, "path": value} for value in values)
        params = h3_params(args.prompt, {"params": args.params}, content_uploads)
        emit(True, **generate_asset(find_apiz(args.apiz), args, args.model, args.prompt, output, params, args.kind, content_uploads=content_uploads))
        return
    params = parse_extra(args.params)
    params["prompt"] = args.prompt
    emit(True, **generate_asset(find_apiz(args.apiz), args, args.model, args.prompt, output, params, args.kind, uploads))


def cmd_speech(args):
    apiz = find_apiz(args.apiz)
    output = Path(args.output).expanduser().resolve()
    if output.suffix.lower() not in {".mp3", ".ogg", ".wav", ".flac"}:
        raise ApizError("speech output must be .mp3 .ogg .wav or .flac")
    if output.suffix.lower() != ".mp3" and not shutil.which("ffmpeg"):
        raise ApizError("ffmpeg is required for .ogg/.wav/.flac output")
    text = Path(args.text_file).read_text(encoding="utf-8") if args.text_file else args.text
    if not text or not text.strip():
        raise ApizError("empty speech text")
    if not 0.5 <= args.speed <= 2.0:
        raise ApizError("speech speed must be 0.5-2.0")
    request_hash = json_hash({"text": text, "voice": args.voice, "model": args.model, "speed": args.speed, "output": str(output)})
    state = read_sidecar(output)
    if state and not args.force:
        if state.get("request_hash") != request_hash:
            raise ApizError(f"existing speech state does not match: {sidecar_path(output)}")
        if output.exists():
            return emit(True, **task_result(output, state.get("task", {}), state.get("files") or [str(output)], note="already downloaded"))
        url = (state.get("task") or {}).get("audio_url")
        if not url:
            raise ApizError("saved speech state has no audio_url; use --force for a new paid call")
        with tempfile.TemporaryDirectory() as tmp:
            source = download_file(url, Path(tmp) / "speech.mp3")
            if output.suffix.lower() == ".mp3":
                os.replace(source, output)
            else:
                convert_audio(source, output)
        state["files"] = [str(output)]
        write_sidecar(output, state)
        return emit(True, **task_result(output, state["task"], state["files"]))
    if output.exists():
        raise ApizError(f"output exists: {output}; use --force for a new paid call")
    command = ["speak", text, "--model", args.model, "--speed", str(args.speed)]
    if args.voice:
        command += ["--voice", args.voice]
    task = run_apiz(apiz, args, command, timeout=300)
    url = task.get("audio_url")
    if not url:
        raise ApizError("speech returned no audio_url")
    state = {"schema_version": 1, "request_hash": request_hash, "task_id": task.get("task_id"), "task": task, "status": task.get("status", "completed"), "output": str(output), "kind": "speech"}
    write_sidecar(output, state)
    with tempfile.TemporaryDirectory() as tmp:
        source = download_file(url, Path(tmp) / "speech.mp3")
        if output.suffix.lower() == ".mp3":
            os.replace(source, output)
        else:
            convert_audio(source, output)
    state["files"] = [str(output)]
    write_sidecar(output, state)
    emit(True, **task_result(output, task, state["files"]), seconds=task.get("duration"))


def cmd_voice_design(args):
    output = Path(args.output)
    if output.suffix.lower() not in {".mp3", ".ogg", ".wav", ".flac"}:
        raise ApizError("voice audition output must be .mp3 .ogg .wav or .flac")
    if args.voice_id and not re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]{7,255}", args.voice_id):
        raise ApizError("voice_id must start with a letter and contain 8-256 letters, digits, underscores or hyphens")
    params = {"prompt": args.prompt, "preview_text": args.preview_text, "aigc_watermark": False}
    if args.voice_id:
        params["voice_id"] = args.voice_id
    result = generate_asset(find_apiz(args.apiz), args, "minimax/voice-design", args.prompt, output, params, "audio")
    result["note"] = "Minimax designed voices are temporary; record voice_id and use it before expiry."
    emit(True, **result)


def cmd_voices(args):
    if args.limit < 0:
        raise ApizError("--limit must be zero or positive")
    data = run_apiz(find_apiz(args.apiz), args, ["voices", "list", "--status", args.status])
    statistics = None
    if isinstance(data, dict) and ("user_voices" in data or "public_voices" in data):
        user_voices = data.get("user_voices") or []
        public_voices = data.get("public_voices") or []
        voices = [{"source": "user", **voice} for voice in user_voices] + [{"source": "public", **voice} for voice in public_voices]
        statistics = data.get("statistics")
    else:
        voices = data if isinstance(data, list) else data.get("voices") or data.get("items") or []
    if args.search:
        needle = args.search.casefold()
        voices = [voice for voice in voices if needle in json.dumps(voice, ensure_ascii=False).casefold()]
    total = len(voices)
    shown = voices if args.limit == 0 else voices[:args.limit]
    result = {"voices": shown, "total": total, "returned": len(shown), "truncated": len(shown) < total}
    if statistics is not None:
        result["statistics"] = statistics
    emit(True, **result)


def cmd_task(args):
    apiz = find_apiz(args.apiz)
    task = poll_task(apiz, args, args.task_id)
    if task.get("status") == "failed":
        result = task_result(Path(args.output) if args.output else Path("."), task)
        result["error"] = task.get("error") or "task failed"
        emit(False, **result)
        raise SystemExit(1)
    if not args.output:
        emit(True, **task_result(Path("."), task))
        return
    output = Path(args.output).expanduser().resolve()
    if args.kind == "image" and output.suffix.lower() not in IMAGE_SUFFIXES:
        raise ApizError("image task output must be .png .jpg .jpeg .webp .gif or .svg")
    if args.kind == "video" and output.suffix.lower() != ".mp4":
        raise ApizError("video task output must be .mp4")
    if args.kind == "audio" and output.suffix.lower() not in {".mp3", ".ogg", ".wav", ".flac"}:
        raise ApizError("audio task output must be .mp3 .ogg .wav or .flac")
    state = read_sidecar(output) or {"schema_version": 1, "output": str(output)}
    if output.exists() and not args.force:
        if state.get("task_id") != args.task_id:
            raise ApizError(f"output exists without matching task state: {output}; choose a new path or use --force")
        result = task_result(output, task, state.get("files") or [str(output)], note="already downloaded")
        emit(True, **result)
        return
    state.update(task=task, task_id=args.task_id, status=task.get("status"))
    write_sidecar(output, state)
    paths = save_task_results(task, output, args.kind)
    state.update(files=paths)
    write_sidecar(output, state)
    emit(True, **task_result(output, task, paths))


def cmd_batch(args):
    apiz = find_apiz(args.apiz)
    jobs_path = Path(args.jobs)
    jobs = [json.loads(line) for line in jobs_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    results = []
    for index, job in enumerate(jobs, 1):
        if not isinstance(job, dict):
            results.append({"job": index, "ok": False, "path": None, "error": "job must be a JSON object"})
            continue
        try:
            results.append({"job": index, "ok": True, **image_job(job, args)})
        except (ApizError, ValueError, KeyError, TypeError) as exc:
            results.append({"job": index, "ok": False, "path": job.get("o"), "error": str(exc)})
    ok = all(item["ok"] for item in results)
    emit(ok, images=results, cost_cents=sum(item.get("cost_cents") or 0 for item in results))
    if not ok:
        raise SystemExit(1)


def add_common(parser):
    parser.add_argument("--apiz", default=None, help="apiz executable path (or APIZ_BIN)")
    parser.add_argument("--profile", default=None)
    parser.add_argument("--config", default=None)
    parser.add_argument("--base-url", default=None)
    parser.add_argument("--folder", default="cli-uploads")
    parser.add_argument("--no-wait", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--poll", type=float, default=5.0)
    parser.add_argument("--wait-timeout", type=int, default=DEFAULT_WAIT_TIMEOUT, help="local polling timeout in seconds; remote task remains resumable")


def build_parser():
    parser = argparse.ArgumentParser(description="Generate images, MiniMax-H3/Seedance video, speech and music through apiz")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("doctor"); add_common(p); p.set_defaults(func=cmd_doctor)
    p = sub.add_parser("models"); add_common(p); p.add_argument("--category", choices=["image", "video", "audio"]); p.add_argument("--search"); p.set_defaults(func=cmd_models)
    p = sub.add_parser("docs"); add_common(p); p.add_argument("model"); p.set_defaults(func=cmd_docs)
    p = sub.add_parser("upload"); add_common(p); p.add_argument("file"); p.set_defaults(func=cmd_upload)

    p = sub.add_parser("image"); add_common(p)
    p.add_argument("--prompt", required=True); p.add_argument("-o", "--output", required=True)
    p.add_argument("--model", default=DEFAULT_IMAGE_MODEL); p.add_argument("--image", action="append")
    p.add_argument("--quality", choices=["low", "medium", "high", "xhigh", "max"], default="medium")
    p.add_argument("--size", default="1K", help="1K/2K/4K or WIDTHxHEIGHT")
    p.add_argument("--aspect-ratio", default="1:1"); p.add_argument("--transparent", action="store_true")
    p.add_argument("--complexity", choices=["low", "medium", "high"], default="high")
    p.add_argument("--frames", type=int); p.add_argument("--frame-ms", type=int); p.add_argument("--params")
    p.set_defaults(func=cmd_image)

    p = sub.add_parser("video"); add_common(p)
    p.add_argument("--prompt", required=True); p.add_argument("-o", "--output", required=True)
    p.add_argument("--model", default=DEFAULT_VIDEO_MODEL, help="minimax/h3 (default) or st-ai/super-seed2")
    p.add_argument("--image", action="append", help="H3 first/last frame alias, or Seedance first/last frames")
    p.add_argument("--first-frame", help="H3 first-frame image")
    p.add_argument("--last-frame", help="H3 last-frame image")
    p.add_argument("--reference-image", action="append", help="H3 reference image; repeatable")
    p.add_argument("--reference-video", action="append", help="H3 reference video; repeatable")
    p.add_argument("--reference-audio", action="append", help="H3 reference audio; repeatable")
    p.add_argument("--duration", type=int, default=5)
    p.add_argument("--aspect-ratio", help="H3 also accepts adaptive when media is supplied")
    p.add_argument("--resolution", choices=["480p", "768P", "1080p", "2K"], help="H3 output resolution; default 768P")
    p.add_argument("--variant", choices=["fast", "fast_vip", "standard", "standard_vip"], help="Seedance only; default fast")
    p.add_argument("--params"); p.set_defaults(func=cmd_video)

    p = sub.add_parser("speech"); add_common(p)
    source = p.add_mutually_exclusive_group(required=True); source.add_argument("--text"); source.add_argument("--text-file")
    p.add_argument("--voice"); p.add_argument("--model", default=DEFAULT_TTS_MODEL)
    p.add_argument("--speed", type=float, default=1.0); p.add_argument("-o", "--output", required=True)
    p.set_defaults(func=cmd_speech)

    p = sub.add_parser("music"); add_common(p)
    p.add_argument("--prompt", required=True); p.add_argument("--lyrics", default="[Inst]\nInstrumental")
    p.add_argument("--music-model", choices=["music-2.5", "music-2.0"], default="music-2.5")
    p.add_argument("--model", default=DEFAULT_MUSIC_MODEL); p.add_argument("--params")
    p.add_argument("-o", "--output", required=True); p.set_defaults(func=cmd_music)

    p = sub.add_parser("voice-design"); add_common(p)
    p.add_argument("--prompt", required=True); p.add_argument("--preview-text", default="你好，这是这个角色的声音试听。")
    p.add_argument("--voice-id"); p.add_argument("-o", "--output", required=True); p.set_defaults(func=cmd_voice_design)

    p = sub.add_parser("voices"); add_common(p); p.add_argument("--status", choices=["active", "expired", "all"], default="active"); p.add_argument("--search"); p.add_argument("--limit", type=int, default=25, help="maximum voices to print; 0 prints all"); p.set_defaults(func=cmd_voices)
    p = sub.add_parser("generate"); add_common(p)
    p.add_argument("--model", required=True); p.add_argument("--prompt", required=True); p.add_argument("-o", "--output", required=True)
    p.add_argument("--kind", choices=["image", "video", "audio"], required=True); p.add_argument("--params")
    p.add_argument("--upload", action="append", metavar="KEY=PATH"); p.set_defaults(func=cmd_generate)
    p = sub.add_parser("task"); add_common(p); p.add_argument("task_id"); p.add_argument("-o", "--output"); p.add_argument("--kind", choices=["image", "video", "audio"], default="video"); p.set_defaults(func=cmd_task)
    p = sub.add_parser("batch"); add_common(p); p.add_argument("jobs"); p.set_defaults(func=cmd_batch)
    return parser


def main():
    args = build_parser().parse_args()
    try:
        args.func(args)
    except ApizError as exc:
        emit(False, error=str(exc))
        raise SystemExit(1)
    except (OSError, ValueError, KeyError) as exc:
        emit(False, error=str(exc))
        raise SystemExit(1)
    except KeyboardInterrupt:
        emit(False, error="interrupted; rerun to resume the saved task")
        raise SystemExit(130)


if __name__ == "__main__":
    main()
