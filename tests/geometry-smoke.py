#!/usr/bin/env python3
"""Verify exported annotation placement using independent Poppler rasterization."""
import json
import base64
import struct
import zlib
from pathlib import Path
import subprocess
import tempfile
import time

plugin = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="pdfseal-geometry-") as folder:
    work = Path(folder)
    subprocess.run(["python3", str(plugin / "tests/make-fixture.py"), str(work / "input.pdf")], check=True)
    # Four identical pages at distinct inherited/view rotations.
    subprocess.run(["qpdf", str(work / "input.pdf"), "--pages", ".", "1,1,1,1", "--",
                    "--rotate=90:2", "--rotate=180:3", "--rotate=270:4", str(work / "rotated.pdf")], check=True)
    worker = subprocess.Popen([str(plugin / "bin/pdfseal-worker")],
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    assert json.loads(worker.stdout.readline())["event"] == "ready"
    serial = 0
    def request(op, **values):
        global serial
        serial += 1
        worker.stdin.write(json.dumps(dict(id=serial, op=op, **values)) + "\n")
        worker.stdin.flush()
        reply = json.loads(worker.stdout.readline())
        assert reply["ok"], reply
        return reply["result"]
    try:
        request("open", path=str(work / "rotated.pdf"))
        start = time.perf_counter()
        request("render", page=1, pixels=1600)
        cold_ms = (time.perf_counter() - start) * 1000
        start = time.perf_counter()
        cached = request("render", page=1, pixels=1600)
        warm_ms = (time.perf_counter() - start) * 1000
        assert cached["cached"]
        def chunk(kind, data):
            return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
        # Transparent top quarter tests image orientation and alpha independently.
        raw = b"".join(b"\0" + bytes([204, 0, 51, 0 if y < 5 else 255]) * 40 for y in range(20))
        png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 40, 20, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
        data_url = "data:image/png;base64," + base64.b64encode(png).decode()
        for kind in ("box", "image"):
            request("export", path=str(work / "marked.pdf"),
                    pages=[dict(number=n) for n in range(1, 5)],
                    marks=[dict(page=n, kind=kind, dataUrl=data_url, color="#cc0033", size=2,
                                x=0.2, y=0.3, w=0.25, h=0.15) for n in range(1, 5)])
            for n in range(1, 5):
                image = subprocess.check_output(["pdftoppm", "-f", str(n), "-l", str(n),
                          "-singlefile", "-cropbox", "-scale-to", "700", str(work / "marked.pdf")])
                magic, dimensions, maximum, pixels = image.split(b"\n", 3)
                assert magic == b"P6" and maximum == b"255"
                width, height = map(int, dimensions.split())
                hits = [(i % width, i // width) for i in range(width * height)
                        if pixels[i * 3] > 150 and pixels[i * 3 + 1] < 60 and 20 < pixels[i * 3 + 2] < 110]
                assert hits, f"Page {n}: annotation missing"
                actual = [min(x for x, y in hits) / width, min(y for x, y in hits) / height,
                          max(x for x, y in hits) / width, max(y for x, y in hits) / height]
                assert all(abs(a - b) < 0.01 for a, b in zip(actual, [0.2, 0.3375 if kind == "image" else 0.3, 0.45, 0.45])), (kind, n, actual)
        print(f"PASS: box/image placement and transparency at 0/90/180/270 degrees; fixture preview {cold_ms:.1f} ms, cached {warm_ms:.1f} ms")
    finally:
        worker.stdin.close()
        assert worker.wait(timeout=10) == 0
