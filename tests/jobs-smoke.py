#!/usr/bin/env python3
"""Cancel an active renderer, then prove the PDF session still works."""
import json
import os
from pathlib import Path
import queue
import subprocess
import tempfile
import threading
import time

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="pdfseal-jobs-") as folder:
    work = Path(folder)
    source = work / "source.pdf"
    subprocess.run(["python3", str(root / "tests/make-fixture.py"), str(source)], check=True)
    wrappers = work / "wrappers"
    wrappers.mkdir()
    marker = work / "render-started"
    wrapper = wrappers / "pdftoppm"
    wrapper.write_text('#!/bin/sh\ntouch "$PDFSEAL_RENDER_MARKER"\nexec sleep 30\n')
    wrapper.chmod(0o700)
    runtime = work / "runtime"
    runtime.mkdir(mode=0o700)
    env = dict(os.environ, PATH=str(wrappers) + os.pathsep + os.environ["PATH"],
               XDG_RUNTIME_DIR=str(runtime), PDFSEAL_RENDER_MARKER=str(marker))
    worker = subprocess.Popen([str(root / "bin/pdfseal-worker")], stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE, text=True, env=env)
    messages = queue.Queue()
    def read():
        for line in worker.stdout:
            messages.put(json.loads(line))
    threading.Thread(target=read, daemon=True).start()
    def send(request):
        worker.stdin.write(json.dumps(request) + "\n")
        worker.stdin.flush()
    def response(identifier):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            message = messages.get(timeout=max(0.01, deadline - time.monotonic()))
            if message.get("id") == identifier and "ok" in message:
                return message
        raise AssertionError("Worker response timed out")
    try:
        assert messages.get(timeout=5)["event"] == "ready"
        send(dict(id=1, op="open", path=str(source)))
        opened = response(1)
        assert opened["ok"], opened
        pages = opened["result"]["pages"]
        send(dict(id=2, op="apply", action="ocr", pages=pages, marks=[]))
        deadline = time.monotonic() + 5
        while not marker.exists() and time.monotonic() < deadline:
            time.sleep(0.02)
        assert marker.exists(), "OCR never started its renderer"
        start = time.monotonic()
        send(dict(op="cancel", target=2))
        cancelled = response(2)
        assert not cancelled["ok"] and cancelled["error"] == "Operation cancelled", cancelled
        assert time.monotonic() - start < 2, "Cancellation did not stop the active child"
        output = work / "after-cancel.pdf"
        send(dict(id=3, op="export", path=str(output), pages=pages, marks=[]))
        assert response(3)["ok"]
        text = subprocess.check_output(["pdftotext", str(output), "-"], text=True)
        assert "PDFSeal native test document" in text
        worker.stdin.close()
        assert worker.wait(timeout=5) == 0
        assert not list(runtime.iterdir()), "Private session files survived shutdown"
        print("PASS: active renderer cancellation, unchanged document, reusable session, private-file cleanup")
    finally:
        if worker.poll() is None:
            worker.kill()
            worker.wait()
