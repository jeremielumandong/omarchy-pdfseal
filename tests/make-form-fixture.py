#!/usr/bin/env python3
from pathlib import Path
import sys

objects = []
def add(value):
    objects.append(value)
    return len(objects)
def stream(content, attrs=b""):
    return b"<< /Length " + str(len(content)).encode() + b" " + attrs + b" >>\nstream\n" + content + b"\nendstream"
add(b"<< /Type /Catalog /Pages 2 0 R /AcroForm 6 0 R >>")
add(b"<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 500 700] >>")
add(b"<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R /Annots [7 0 R 8 0 R 10 0 R 11 0 R 12 0 R 16 0 R] >>")
add(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
add(stream(b"BT /F1 22 Tf 50 640 Td (Interactive form fixture) Tj ET"))
add(b"<< /Fields [7 0 R 8 0 R 9 0 R 12 0 R 16 0 R] /DA (/F1 12 Tf 0 g) /DR << /Font << /F1 4 0 R >> >> /NeedAppearances true >>")
add(b"<< /Type /Annot /Subtype /Widget /FT /Tx /T (FullName) /V (Ada) /Rect [70 520 350 550] /P 3 0 R >>")
add(b"<< /Type /Annot /Subtype /Widget /FT /Btn /T (Agree) /V /Yes /AS /Yes /Rect [70 450 90 470] /AP << /N << /Off 13 0 R /Yes 14 0 R >> >> /P 3 0 R >>")
add(b"<< /FT /Btn /Ff 32768 /T (Choice) /V /One /Kids [10 0 R 11 0 R] >>")
add(b"<< /Type /Annot /Subtype /Widget /Parent 9 0 R /AS /One /Rect [70 390 90 410] /AP << /N << /Off 13 0 R /One 15 0 R >> >> /P 3 0 R >>")
add(b"<< /Type /Annot /Subtype /Widget /Parent 9 0 R /AS /Off /Rect [120 390 140 410] /AP << /N << /Off 13 0 R /Two 15 0 R >> >> /P 3 0 R >>")
add(b"<< /Type /Annot /Subtype /Widget /FT /Ch /Ff 131072 /T (Select) /V (Alpha) /Opt [(Alpha) (Beta)] /Rect [70 310 280 340] /P 3 0 R >>")
attrs = b"/Type /XObject /Subtype /Form /BBox [0 0 20 20] /Resources << >>"
add(stream(b"0 G 1 w 0.5 0.5 19 19 re S", attrs))
add(stream(b"0 G 1 w 0.5 0.5 19 19 re S 3 3 m 17 17 l 3 17 m 17 3 l S", attrs))
add(stream(b"0 g 5 5 10 10 re f", attrs))
add(b"<< /Type /Annot /Subtype /Widget /FT /Tx /Ff 1 /T (Locked) /V (Fixed) /Rect [70 250 250 275] /P 3 0 R >>")
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
