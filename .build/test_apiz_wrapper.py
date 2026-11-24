import contextlib
import importlib.util
import io
import json
import tempfile
from argparse import Namespace
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / ".agent/skills/asset-gen/scripts/apiz_asset.py"
spec = importlib.util.spec_from_file_location("apiz_asset", SCRIPT)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def test_defaults():
    video_args = mod.build_parser().parse_args(["video", "--prompt", "x", "-o", "x.mp4"])
    assert video_args.wait_timeout == 3600
    assert mod.DEFAULT_VIDEO_MODEL == "minimax/h3"
    assert video_args.model == "minimax/h3"
    image_args = mod.build_parser().parse_args(["image", "--prompt", "x", "-o", "x.png"])
    assert mod.DEFAULT_IMAGE_MODEL == "apiz/gpt-image-2.6-flare"
    assert image_args.model == "apiz/gpt-image-2.6-flare"


def test_run_apiz_timeout():
    calls = []
    args = Namespace(profile=None, config=None, base_url=None)

    def fake_run(command, **kwargs):
        calls.append(command)
        return Namespace(returncode=0, stdout="{}", stderr="")

    with patch.object(mod.subprocess, "run", side_effect=fake_run):
        assert mod.run_apiz(Path("apiz"), args, ["upload", "x.png"], timeout=300) == {}
    assert calls[0][-4:] == ["--timeout", "300s", "upload", "x.png"]


def test_poll_progress():
    args = Namespace(wait_timeout=10, poll=1, profile=None, config=None, base_url=None)
    responses = [
        {"status": "processing", "progress": 70},
        {"status": "completed", "progress": 100},
    ]
    stderr = io.StringIO()
    with patch.object(mod, "run_apiz", side_effect=responses), patch.object(mod.time, "sleep"), contextlib.redirect_stderr(stderr):
        result = mod.poll_task(Path("apiz"), args, "task", initial={"status": "processing", "progress": 10})
    assert result["status"] == "completed"
    assert "70%" in stderr.getvalue()


def test_doctor_without_key():
    emitted = []
    calls = []
    args = Namespace(apiz=None, profile=None, config=None, base_url=None)

    def fake_run(apiz, command_args, cli_args, timeout=180, allow_text=False):
        calls.append(cli_args)
        return "apiz version test"

    with patch.object(mod, "find_apiz", return_value=Path("apiz")), patch.object(mod, "profile_settings", return_value=(None, "https://example.test")), patch.object(mod, "run_apiz", side_effect=fake_run), patch.object(mod, "emit", side_effect=lambda ok, **kw: emitted.append((ok, kw))):
        mod.cmd_doctor(args)
    assert calls == [["--version"]]
    assert emitted[0][1]["configured"] is False and emitted[0][1]["balance"] is None


def test_voices():
    data = {
        "user_voices": [{"voice_id": "MyVoice", "voice_name": "Mine"}],
        "public_voices": [
            {"voice_id": "PublicOne", "voice_name": "One"},
            {"voice_id": "PublicTwo", "voice_name": "Two"},
        ],
        "statistics": {"active": 3},
    }
    emitted = []
    args = Namespace(apiz=None, profile=None, config=None, base_url=None, status="active", search=None, limit=2)
    with patch.object(mod, "find_apiz", return_value=Path("apiz")), patch.object(mod, "run_apiz", return_value=data), patch.object(mod, "emit", side_effect=lambda ok, **kw: emitted.append((ok, kw))):
        mod.cmd_voices(args)
    ok, result = emitted[0]
    assert ok and result["total"] == 3 and result["returned"] == 2 and result["truncated"]
    assert [item["source"] for item in result["voices"]] == ["user", "public"]
    assert result["statistics"] == {"active": 3}

    emitted.clear()
    args.search = "PublicTwo"
    args.limit = 0
    with patch.object(mod, "find_apiz", return_value=Path("apiz")), patch.object(mod, "run_apiz", return_value=data), patch.object(mod, "emit", side_effect=lambda ok, **kw: emitted.append((ok, kw))):
        mod.cmd_voices(args)
    assert emitted[0][1]["voices"][0]["voice_id"] == "PublicTwo"


def expect_apiz_error(call, message):
    try:
        call()
    except mod.ApizError as exc:
        assert message in str(exc), str(exc)
    else:
        raise AssertionError(f"expected ApizError containing {message!r}")


def test_h3_text_defaults():
    captured = {}
    args = Namespace(apiz=None)

    def fake_generate(apiz, command_args, model, prompt, output, params, kind, uploads=None, content_uploads=None):
        captured.update(model=model, params=params, kind=kind, uploads=uploads, content_uploads=content_uploads)
        return {"path": str(output)}

    with patch.object(mod, "find_apiz", return_value=Path("apiz")), patch.object(mod, "generate_asset", side_effect=fake_generate):
        mod.video_job({"prompt": "a robot waves", "o": "wave.mp4"}, args)
    assert captured["model"] == "minimax/h3"
    assert captured["params"] == {"resolution": "768P", "duration": 5, "ratio": "16:9"}
    assert captured["content_uploads"] == []
    assert captured["uploads"] is None


def test_h3_video_mapping():
    captured = {}
    args = Namespace(apiz=None)

    def fake_generate(apiz, command_args, model, prompt, output, params, kind, uploads=None, content_uploads=None):
        captured.update(model=model, params=params, kind=kind, uploads=uploads, content_uploads=content_uploads)
        return {"path": str(output)}

    job = {
        "prompt": "wave",
        "o": "wave.mp4",
        "duration": 4,
        "aspect_ratio": "1:1",
        "resolution": "1080p",
        "first_frame": "first.png",
        "last_frame": "last.png",
        "reference_image": ["hero.png", "prop.png"],
        "reference_video": "motion.mp4",
        "reference_audio": "beat.mp3",
    }
    with patch.object(mod, "find_apiz", return_value=Path("apiz")), patch.object(mod, "generate_asset", side_effect=fake_generate):
        mod.video_job(job, args)
    assert captured["model"] == "minimax/h3"
    assert captured["params"] == {"resolution": "1080p", "duration": 4, "ratio": "1:1"}
    assert captured["content_uploads"] == [
        {"type": "image_url", "role": "first_frame", "path": "first.png"},
        {"type": "image_url", "role": "last_frame", "path": "last.png"},
        {"type": "image_url", "role": "reference_image", "path": "hero.png"},
        {"type": "image_url", "role": "reference_image", "path": "prop.png"},
        {"type": "video_url", "role": "reference_video", "path": "motion.mp4"},
        {"type": "audio_url", "role": "reference_audio", "path": "beat.mp3"},
    ]


def test_h3_validation():
    args = Namespace(apiz=None)
    cases = [
        ({"prompt": "x", "o": "x.mp4", "aspect_ratio": "adaptive"}, "text-to-video"),
        ({"prompt": "x", "o": "x.mp4", "duration": 3}, "4-15"),
        ({"prompt": "x", "o": "x.mp4", "duration": 4.5}, "integer"),
        ({"prompt": "x", "o": "x.mp4", "params": {"resolution": "720p"}}, "resolution"),
        ({"prompt": "x", "o": "x.mp4", "params": {"functionMode": "omni_reference"}}, "Seedance-only"),
        ({"prompt": "x", "o": "x.mp4", "variant": "fast"}, "Seedance-only"),
        ({"prompt": "x", "o": "x.mp4", "image": "first.png", "first_frame": "other.png"}, "either --image"),
        ({"prompt": "x" * 7001, "o": "x.mp4"}, "7000"),
    ]
    with patch.object(mod, "find_apiz", return_value=Path("apiz")):
        for job, message in cases:
            expect_apiz_error(lambda job=job: mod.video_job(job, args), message)


def test_seedance_compatibility():
    captured = {}
    args = Namespace(apiz=None)

    def fake_generate(apiz, command_args, model, prompt, output, params, kind, uploads=None, content_uploads=None):
        captured.update(model=model, params=params, uploads=uploads, content_uploads=content_uploads)
        return {"path": str(output)}

    job = {"model": "st-ai/super-seed2", "prompt": "wave", "o": "wave.mp4", "duration": 4, "aspect_ratio": "1:1", "variant": "standard", "image": ["first.png", "last.png"]}
    with patch.object(mod, "find_apiz", return_value=Path("apiz")), patch.object(mod, "generate_asset", side_effect=fake_generate):
        mod.video_job(job, args)
    assert captured["model"] == "st-ai/super-seed2"
    assert captured["params"]["model"] == "seedance_2.0"
    assert captured["params"]["functionMode"] == "first_last_frames"
    assert captured["params"]["prompt"] == "wave"
    assert captured["uploads"] == {"filePaths": ["first.png", "last.png"]}
    assert captured["content_uploads"] is None


def test_seedance_mode_guard():
    args = Namespace(apiz=None)
    with patch.object(mod, "find_apiz", return_value=Path("apiz")):
        expect_apiz_error(lambda: mod.video_job({"model": "st-ai/super-seed2", "prompt": "x", "o": "x.mp4", "params": {"functionMode": "omni_reference"}}, args), "first_last_frames")
        expect_apiz_error(lambda: mod.video_job({"model": "st-ai/super-seed2", "prompt": "x", "o": "x.mp4", "resolution": "768P"}, args), "require --model minimax/h3")


def test_generate_asset_h3_content():
    calls = []
    args = Namespace(force=False, no_wait=True, profile=None, config=None, base_url=None)

    def fake_run(apiz, command_args, cli_args, timeout=180, allow_text=False):
        calls.append(cli_args)
        return {"task_id": "h3-task", "status": "pending", "price": 79}

    def fake_upload(apiz, command_args, path):
        return f"https://example.test/{Path(path).name}"

    content_uploads = [
        {"type": "image_url", "role": "first_frame", "path": "first.png"},
        {"type": "audio_url", "role": "reference_audio", "path": "beat.mp3"},
    ]
    with tempfile.TemporaryDirectory() as tmp:
        output = Path(tmp) / "wave.mp4"
        with patch.object(mod, "run_apiz", side_effect=fake_run), patch.object(mod, "upload_file", side_effect=fake_upload):
            mod.generate_asset(Path("apiz"), args, "minimax/h3", "wave", output, {"resolution": "768P", "duration": 4, "ratio": "1:1"}, "video", content_uploads=content_uploads)
        command = calls[0]
        params = json.loads(command[command.index("--params") + 1])
        assert "prompt" not in params
        assert params["content"] == [
            {"type": "text", "text": "wave"},
            {"type": "image_url", "image_url": {"url": "https://example.test/first.png"}, "role": "first_frame"},
            {"type": "audio_url", "audio_url": {"url": "https://example.test/beat.mp3"}, "role": "reference_audio"},
        ]
        state = json.loads(Path(str(output) + ".apiz.json").read_text(encoding="utf-8"))
        assert state["request_hash"] and state["task_id"] == "h3-task"
        changed = [content_uploads[0], {"type": "audio_url", "role": "reference_audio", "path": "other.mp3"}]
        with patch.object(mod, "run_apiz", side_effect=fake_run), patch.object(mod, "upload_file", side_effect=fake_upload):
            expect_apiz_error(lambda: mod.generate_asset(Path("apiz"), args, "minimax/h3", "wave", output, {"resolution": "768P", "duration": 4, "ratio": "1:1"}, "video", content_uploads=changed), "does not match")


def test_generate_asset_legacy_hash():
    args = Namespace(force=False, no_wait=True, profile=None, config=None, base_url=None)
    with tempfile.TemporaryDirectory() as tmp:
        output = Path(tmp) / "image.png"
        params = {"quality": "medium", "prompt": "x"}
        with patch.object(mod, "run_apiz", return_value={"task_id": "image-task", "status": "pending", "price": 1}):
            mod.generate_asset(Path("apiz"), args, "apiz/gpt-image-2.6-flare", "x", output, params, "image")
        state = json.loads(Path(str(output) + ".apiz.json").read_text(encoding="utf-8"))
        expected = mod.json_hash({"model": "apiz/gpt-image-2.6-flare", "prompt": "x", "params": params, "uploads": {}, "output": str(output.resolve()), "kind": "image"})
        assert state["request_hash"] == expected


def test_cmd_generate_h3_uploads():
    captured = {}
    args = mod.build_parser().parse_args([
        "generate", "--model", "minimax/h3", "--kind", "video", "--prompt", "wave", "-o", "wave.mp4",
        "--upload", "first_frame=first.png", "--upload", "reference_video=motion.mp4",
    ])

    def fake_generate(apiz, command_args, model, prompt, output, params, kind, uploads=None, content_uploads=None):
        captured.update(model=model, params=params, uploads=uploads, content_uploads=content_uploads)
        return {"path": str(output)}

    with patch.object(mod, "find_apiz", return_value=Path("apiz")), patch.object(mod, "generate_asset", side_effect=fake_generate), patch.object(mod, "emit"):
        mod.cmd_generate(args)
    assert captured["model"] == "minimax/h3"
    assert captured["uploads"] is None
    assert captured["content_uploads"] == [
        {"type": "image_url", "role": "first_frame", "path": "first.png"},
        {"type": "video_url", "role": "reference_video", "path": "motion.mp4"},
    ]
    assert captured["params"]["ratio"] == "adaptive"


def test_music_final_validation():
    args = Namespace(apiz=None)
    with patch.object(mod, "find_apiz", return_value=Path("apiz")):
        try:
            mod.music_job({"prompt": "calm", "o": "calm.mp3", "params": {"lyrics": ""}}, args)
        except mod.ApizError as exc:
            assert "lyrics" in str(exc)
        else:
            raise AssertionError("invalid lyrics override was accepted")


def test_media_filter():
    downloaded = []

    def fake_download(url, output):
        downloaded.append(url)
        output.write_bytes(b"media")
        return output

    task = {"result": {"images": [{"url": "https://example.test/frame.png"}], "videos": [{"url": "https://example.test/clip.mp4"}]}}
    with tempfile.TemporaryDirectory() as tmp, patch.object(mod, "download_file", side_effect=fake_download):
        output = Path(tmp) / "clip.mp4"
        paths = mod.save_task_results(task, output, "video")
    assert downloaded == ["https://example.test/clip.mp4"]
    assert paths == [str(output)]


def test_media_filter_unknown_suffix():
    downloaded = []

    def fake_download(url, output):
        downloaded.append(url)
        output.write_bytes(b"media")
        return output

    task = {"result": {"cover_url": "https://example.test/poster.jpg", "url": "https://example.test/download"}}
    with tempfile.TemporaryDirectory() as tmp, patch.object(mod, "download_file", side_effect=fake_download):
        output = Path(tmp) / "clip.mp4"
        mod.save_task_results(task, output, "video")
    assert downloaded == ["https://example.test/download"]


def test_batch_exit_code():
    emitted = []
    with tempfile.TemporaryDirectory() as tmp:
        jobs = Path(tmp) / "jobs.jsonl"
        jobs.write_text('{"prompt":"ok","o":"ok.png"}\n{"prompt":"bad"}\n[]\n', encoding="utf-8")
        args = Namespace(jobs=str(jobs), apiz=None)

        def fake_image(job, command_args):
            if "o" not in job:
                raise mod.ApizError("image job needs prompt and o")
            return {"path": job["o"], "cost_cents": 10}

        with patch.object(mod, "find_apiz", return_value=Path("apiz")), patch.object(mod, "image_job", side_effect=fake_image), patch.object(mod, "emit", side_effect=lambda ok, **kw: emitted.append((ok, kw))):
            try:
                mod.cmd_batch(args)
            except SystemExit as exc:
                assert exc.code == 1
            else:
                raise AssertionError("partial batch failure exited zero")
    ok, result = emitted[0]
    assert not ok and len(result["images"]) == 3 and result["cost_cents"] == 10


for test in [test_defaults, test_run_apiz_timeout, test_poll_progress, test_doctor_without_key, test_voices, test_h3_text_defaults, test_h3_video_mapping, test_h3_validation, test_seedance_compatibility, test_seedance_mode_guard, test_generate_asset_h3_content, test_generate_asset_legacy_hash, test_cmd_generate_h3_uploads, test_music_final_validation, test_media_filter, test_media_filter_unknown_suffix, test_batch_exit_code]:
    test()
    print(f"PASS {test.__name__}")
print("all wrapper regression tests passed")
