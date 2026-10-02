#!/usr/bin/env python3
"""A dependency-free worker for exercising subprocess and export failure paths."""

import argparse
import json
import os
from pathlib import Path
import signal
import sys
import time

MIDI = (
    b"MThd\x00\x00\x00\x06\x00\x00\x00\x01\x00\x60"
    b"MTrk\x00\x00\x00\x0c\x00\x90\x3c\x64\x60\x80\x3c\x00\x00\xff\x2f\x00"
)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode")
    parser.add_argument("--marker")
    parser.add_argument("--input", type=Path)
    parser.add_argument("--output", type=Path)
    args, _ = parser.parse_known_args()
    mode = args.mode or "success"
    marker = args.marker
    if args.input:
        text = args.input.read_text()
        if text.startswith("mode:"):
            fields = text.split(":", 2)
            mode = fields[1]
            if len(fields) == 3:
                marker = fields[2]
    if mode == "stream":
        for chunk in [b'{"version":1,"event":"transcribing","message":"caf\xc3',
                      b'\xa9 ', b'\xf0\x9f', b'\x8e\xb9"}\n',
                      b'{"version":1,"event":"done"}']:
            os.write(sys.stdout.fileno(), chunk)
            time.sleep(0.01)
        os.write(sys.stderr.fileno(), b"stderr-tail-without-newline")
        return
    if mode == "failure":
        for _ in range(1000):
            os.write(sys.stderr.fileno(), b"diagnostic-" + b"x" * 64 + b"\n")
        os.write(sys.stderr.fileno(), b"terminal-failure")
        sys.exit(7)
    if mode == "signal":
        print("signal-tail", file=sys.stderr, flush=True)
        os.kill(os.getpid(), signal.SIGKILL)
    if mode == "wait":
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        if marker:
            Path(marker).write_text(str(os.getpid()))
        print(json.dumps({"version": 1, "event": "transcribing"}), flush=True)
        time.sleep(60)
    if mode == "invalid":
        args.output.write_bytes(b"not-midi")
        return
    if mode == "missing":
        return
    args.output.write_bytes(MIDI)
    print(json.dumps({"version": 1, "event": "done", "output": str(args.output)}), flush=True)


if __name__ == "__main__":
    main()
