#!/usr/bin/env python3
"""Check complete stamp borders in real Qt captures and an independent PDF render."""
import json
from pathlib import Path
import struct
import sys
import zlib


def png(path):
    data = path.read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', path
    compressed = bytearray()
    offset = 8
    while offset < len(data):
        size = struct.unpack('>I', data[offset:offset+4])[0]
        kind, chunk = data[offset+4:offset+8], data[offset+8:offset+8+size]
        if kind == b'IHDR':
            width, height, depth, color, compression, filtering, interlace = struct.unpack('>IIBBBBB', chunk)
            assert depth == 8 and color in (2, 6) and not interlace, (path, depth, color, interlace)
        elif kind == b'IDAT':
            compressed.extend(chunk)
        offset += size + 12
    channels = 4 if color == 6 else 3
    stride = width * channels
    raw = zlib.decompress(compressed)
    assert len(raw) == (stride+1)*height
    rows = []
    previous = bytearray(stride)
    for y in range(height):
        start = y*(stride+1)
        filter_type = raw[start]
        row = bytearray(raw[start+1:start+1+stride])
        assert filter_type in range(5)
        for i in range(stride):
            left = row[i-channels] if i >= channels else 0
            up = previous[i]
            upper_left = previous[i-channels] if i >= channels else 0
            if filter_type == 1:
                value = left
            elif filter_type == 2:
                value = up
            elif filter_type == 3:
                value = (left+up)//2
            elif filter_type == 4:
                predictor = left+up-upper_left
                value = min((left,up,upper_left), key=lambda v: abs(predictor-v))
            else:
                value = 0
            row[i] = (row[i]+value) & 255
        rows.append(row)
        previous = row
    def pixel(x, y):
        i = max(0, min(width-1, x))*channels
        value = rows[max(0, min(height-1, y))][i:i+channels]
        alpha = value[3]/255 if channels == 4 else 1
        return tuple(round(c*alpha+255*(1-alpha)) for c in value[:3])
    return width, height, pixel


def check_borders(path, marks):
    width, height, pixel = png(path)
    def ink(x, y):
        return min(pixel(x,y)) < 235
    for index, mark in enumerate(marks):
        x, y, w, h = mark['x']*width, mark['y']*height, mark['w']*width, mark['h']*height
        for side in ('left','right','top','bottom'):
            hits = 0
            for step in range(25):
                fraction = 0.2+0.6*step/24
                if side in ('left','right'):
                    px, py = x+(w if side == 'right' else 0), y+h*fraction
                else:
                    px, py = x+w*fraction, y+(h if side == 'bottom' else 0)
                # Canvas and grabToImage round their physical dimensions
                # independently; allow three pixels for that raster alignment.
                hits += any(ink(round(px)+dx,round(py)+dy) for dx in range(-3,4) for dy in range(-3,4))
            assert hits >= 22, f'{path.name}: stamp {index} has a clipped {side} border ({hits}/25)'


root = Path(sys.argv[1])
marks = None
sizes = []
for line in (root/'output.log').read_text().splitlines():
    if 'STAMP_MARKS ' in line:
        marks = json.loads(line.split('STAMP_MARKS ',1)[1])
    if 'STAMP_SIZE ' in line:
        sizes.append(json.loads(line.split('STAMP_SIZE ',1)[1]))
assert len(sizes) == 8 and marks is not None and len(marks) == 8
assert all(s['width'] >= 990 and abs(s['width']/s['height']-1000/330) < 0.05 for s in sizes), sizes
for name in ('onscreen-0.5.png','onscreen-1.png','onscreen-2.png','exported.png'):
    check_borders(root/name,marks)
print('PASS: complete borders for all eight stamps, 50%/100%/200% zoom and independent PDF export')
