#!/usr/bin/env python3
"""Generate a deterministic two-page PDF without external Python packages."""
from pathlib import Path
import sys

objects = [
    b"<< /Type /Catalog /Pages 2 0 R >>",
    b"<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 /MediaBox [0 0 500 700] /Resources << /Font << /F1 5 0 R >> >> >>",
    b"<< /Type /Page /Parent 2 0 R /Contents 6 0 R >>",
    b"<< /Type /Page /Parent 2 0 R /Contents 6 0 R /Rotate 90 >>",
    b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
]
content = b"q 0.2 0.4 0.6 rg 350 350 100 60 re f Q BT /F1 22 Tf 45 620 Td (PDFSeal native test document) Tj 0 -42 Td (Draw a signature below.) Tj ET"
objects.append(b"<< /Length " + str(len(content)).encode() + b" >>\nstream\n" + content + b"\nendstream")
pdf = bytearray(b"%PDF-1.7\n")
offsets = [0]
for number, obj in enumerate(objects, 1):
    offsets.append(len(pdf))
    pdf.extend(f"{number} 0 obj\n".encode() + obj + b"\nendobj\n")
xref = len(pdf)
pdf.extend(f"xref\n0 {len(offsets)}\n0000000000 65535 f \n".encode())
for offset in offsets[1:]:
    pdf.extend(f"{offset:010d} 00000 n \n".encode())
pdf.extend(f"trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode())
Path(sys.argv[1]).write_bytes(pdf)
