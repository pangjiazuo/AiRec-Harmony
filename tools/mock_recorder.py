"""仅供本机 UI 联调：独立内存配置，不连接或写入真实开发板。"""
import argparse
import copy
import io
import json
import threading
import time
import zipfile
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


def initial_config():
    return {
        "server": {"host": "0.0.0.0", "port": 8080},
        "unknown_fixture": {"must_preserve": True},
        "storage": {"target_id": "internal", "max_gb": 32, "min_free_gb": 2},
        "channels": [
            {"id": number, "name": f"AHD{number}", "enabled": number == 1,
             "source": f"/dev/fixture{number}", "crop": [number, 0, 1280, 720],
             "unknown_field": f"keep-{number}", "width": 1280, "height": 720,
             "fps": 25, "preview_fps": 15,
             "recording": {"enabled": True, "segment_minutes": 3},
             "detection": {"enabled": True, "categories": ["person", "vehicle", "animal"],
                           "threshold_seconds": 5, "confidence": 0.5,
                           "sample_interval": 1, "lost_tolerance_seconds": 3}}
            for number in range(1, 6)
        ]
    }


def timeline_fixture(start, end, channel=1, media_size=0):
    """全天分钟索引含相接、空白、已清理和跨午夜片段；只作为测试数据。"""
    left = datetime.fromisoformat(start.replace("Z", "+00:00"))
    right = datetime.fromisoformat(end.replace("Z", "+00:00"))
    if left.tzinfo is None or right.tzinfo is None or not timedelta(0) < right - left <= timedelta(hours=26):
        raise ValueError("invalid timezone/window")
    recordings, events = [], []
    if channel == 1:
        count = int((right - left).total_seconds() / 60)
        for minute in range(count):
            if minute % 10 in (5, 6):
                continue
            point = left + timedelta(minutes=minute)
            recordings.append({"id": f"fixture-{minute}", "channel_id": channel,
                "created_at": point.isoformat(), "duration_seconds": 60, "size_bytes": media_size,
                "url": f"/media/fixture-{minute}.mp4", "available": minute % 10 != 8,
                "error": "测试：已清理" if minute % 10 == 8 else ""})
        for name, point in (("midnight-before", left - timedelta(seconds=30)), ("midnight-after", right - timedelta(seconds=30))):
            recordings.append({"id": name, "channel_id": channel, "created_at": point.isoformat(),
                "duration_seconds": 60, "size_bytes": media_size, "url": f"/media/{name}.mp4", "available": True, "error": ""})
        for hour in range(int((right - left).total_seconds() // 3600)):
            for kind, seconds, duration in (("dwell", 180, 40), ("person", 135, 1), ("vehicle", 425, 1), ("animal", 585, 1)):
                point = left + timedelta(hours=hour, seconds=seconds)
                events.append({"start": point.isoformat(), "end": (point + timedelta(seconds=duration)).isoformat(), "event_type": kind})
    recordings.sort(key=lambda item: (item["created_at"], item["id"]))
    return {"start": left.astimezone(timezone.utc).isoformat(), "end": right.astimezone(timezone.utc).isoformat(),
            "recordings": recordings, "event_segments": events}


class Fixture:
    def __init__(self, report, video=None):
        self.config = initial_config()
        self.original = copy.deepcopy(self.config)
        self.writes = []
        self.requests = []
        self.offline = False
        self.timeline_mode = "normal"
        self.video = video.read_bytes() if video else b""
        self.report = report
        self.lock = threading.RLock()

    def save(self):
        self.report.parent.mkdir(parents=True, exist_ok=True)
        self.report.write_text(json.dumps({"config": self.config, "original": self.original,
            "writes": self.writes, "requests": self.requests, "offline": self.offline,
            "timeline_mode": self.timeline_mode}, ensure_ascii=False, indent=2), encoding="utf-8")


def serve(port, report, video=None):
    fixture = Fixture(report, video)

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def send(self, value, code=200, mime="application/json"):
            payload = value if isinstance(value, bytes) else json.dumps(value, ensure_ascii=False).encode()
            self.send_response(code)
            self.send_header("Content-Type", mime)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            try:
                self.wfile.write(payload)
            except (BrokenPipeError, ConnectionResetError):
                pass  # 客户端取消或换日是本工具的正常测试路径。

        def media(self, head=False):
            if fixture.offline or not fixture.video:
                self.send({"error": "fixture media unavailable"}, 503)
                return
            data = fixture.video
            left, right, code = 0, len(data) - 1, 200
            requested = self.headers.get("Range", "")
            if requested:
                try:
                    begin, finish = requested.removeprefix("bytes=").split("-")
                    if not requested.startswith("bytes=") or "," in requested:
                        raise ValueError("single range required")
                    left = int(begin) if begin else max(0, len(data) - int(finish))
                    right = min(len(data) - 1, int(finish)) if begin and finish else len(data) - 1
                    if left > right or left < 0 or left >= len(data):
                        raise ValueError("range outside media")
                    code = 206
                except ValueError:
                    self.send_response(416)
                    self.send_header("Content-Range", f"bytes */{len(data)}")
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
            self.send_response(code)
            self.send_header("Content-Type", "video/mp4")
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Length", str(right - left + 1))
            if code == 206:
                self.send_header("Content-Range", f"bytes {left}-{right}/{len(data)}")
            self.end_headers()
            if not head:
                try:
                    self.wfile.write(data[left:right + 1])
                except (BrokenPipeError, ConnectionResetError):
                    pass

        def do_HEAD(self):
            if urlparse(self.path).path.startswith("/media/"):
                self.media(head=True)
            else:
                self.send({"error": "fixture route absent"}, 404)

        def do_GET(self):
            parsed = urlparse(self.path)
            if parsed.path == "/api/timeline" and fixture.timeline_mode == "delay":
                time.sleep(10)
            with fixture.lock:
                fixture.requests.append(self.path)
                if len(fixture.requests) > 500:
                    fixture.requests = fixture.requests[-500:]
                fixture.save()
                if parsed.path == "/__test__/state":
                    self.send({"config": fixture.config, "original": fixture.original, "writes": fixture.writes})
                    return
                if fixture.offline:
                    self.send({"error": "fixture temporarily offline"}, 503)
                    return
                if parsed.path.startswith("/media/"):
                    self.media()
                elif parsed.path == "/api/timeline":
                    if fixture.timeline_mode == "legacy":
                        self.send({"error": "fixture old server"}, 404)
                    elif fixture.timeline_mode == "oversize":
                        self.send({"error": "全天索引超过 10000 条测试上限"}, 422)
                    else:
                        try:
                            query = parse_qs(parsed.query)
                            self.send(timeline_fixture(query["start"][0], query["end"][0], int(query["channel_id"][0]), len(fixture.video)))
                        except (ValueError, KeyError, IndexError):
                            self.send({"error": "invalid timeline query"}, 400)
                elif parsed.path == "/api/config":
                    self.send(fixture.config)
                elif parsed.path == "/api/status":
                    self.send({"channels": [{"id": c["id"], "name": c["name"], "enabled": c["enabled"],
                        "state": "no_signal", "recording": False} for c in fixture.config["channels"]],
                        "system": {"hostname": "UI TEST", "cpu_percent": 12, "temperature_c": 40,
                            "memory": {"used_bytes": 1073741824, "total_bytes": 4294967296, "used_percent": 25}},
                        "storage": {"label": "测试存储", "free_bytes": 20 * 1073741824, "total_bytes": 32 * 1073741824},
                        "uptime_seconds": 100, "detector": {"ready": True}})
                elif parsed.path == "/api/storage/targets":
                    self.send({"selected_id": fixture.config["storage"]["target_id"], "targets": [
                        {"id": "internal", "label": "内部存储（测试）", "available": True, "writable": True, "free_bytes": 20 * 1073741824},
                        {"id": "uuid:fixture-sd", "label": "SD 卡（测试）", "available": True, "writable": True, "free_bytes": 30 * 1073741824}]})
                elif parsed.path == "/api/diagnostics/model":
                    self.send({"name": "YOLOv5s ReLU", "version": "fixture", "tracker": "ByteTrack", "backend_label": "测试数据",
                               "npu": {"used": True}, "vpu": {"used": True}, "limitations": []})
                elif parsed.path == "/api/logs":
                    self.send({"items": [{"name": "fixture.log", "size_bytes": 32}]})
                elif parsed.path == "/api/logs/download":
                    output = io.BytesIO()
                    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
                        archive.writestr("fixture.log", "Harmony recorder native download check\n")
                    self.send(output.getvalue(), mime="application/zip")
                elif parsed.path in ("/api/recordings", "/api/events"):
                    self.send({"items": []})
                else:
                    self.send({"error": "fixture route absent"}, 404)

        def do_PUT(self):
            size = int(self.headers.get("Content-Length", "0"))
            if size <= 0 or size > 65536:
                self.send({"error": "invalid body size"}, 400)
                return
            try:
                body = json.loads(self.rfile.read(size))
                with fixture.lock:
                    if self.path == "/__test__/timeline_mode":
                        if body["mode"] not in ("normal", "legacy", "oversize", "delay"):
                            raise ValueError("invalid timeline mode")
                        fixture.timeline_mode = body["mode"]
                        fixture.save()
                        self.send({"ok": True})
                    elif self.path == "/__test__/offline":
                        fixture.offline = bool(body["offline"])
                        fixture.save()
                        self.send({"ok": True})
                    elif self.path == "/api/config":
                        if fixture.offline:
                            self.send({"error": "fixture temporarily offline"}, 503)
                            return
                        if not isinstance(body, dict) or len(body.get("channels", [])) != 5:
                            raise ValueError("five channels required")
                        fixture.config = body
                        fixture.writes.append(copy.deepcopy(body))
                        fixture.save()
                        self.send({"ok": True, "config": fixture.config, "restart_required": False})
                    else:
                        self.send({"error": "fixture route absent"}, 404)
            except (ValueError, KeyError, TypeError) as error:
                self.send({"error": str(error)}, 400)

    fixture.save()
    print(f"Fixture listening on 127.0.0.1:{port}; no upstream connections", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=18081)
    parser.add_argument("--report", type=Path, default=Path(".local/mock-state.json"))
    parser.add_argument("--video", type=Path, help="仅使用明确指定的本地测试 MP4；不会自动下载媒体")
    options = parser.parse_args()
    serve(options.port, options.report, options.video)
