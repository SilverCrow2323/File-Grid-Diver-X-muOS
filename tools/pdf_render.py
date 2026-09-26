#!/usr/bin/env python3
import sys, os

# --- sys.path con wheel PyMuPDF estratto ---
_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.dirname(_HERE)
for _cand in (
    os.path.join(_ROOT, "data", "pdf_pack", "lib"),
    "data/pdf_pack/lib",
    "/opt/muos/share/fgdx/pdf_pack/lib",
):
    if os.path.isdir(os.path.join(_cand, "pymupdf")) and _cand not in sys.path:
        sys.path.insert(0, _cand)

def main():
    if len(sys.argv) < 3:
        sys.stderr.write("usage: pdf_render.py <pdf> <page> <dpi> <out.png>\n"
                         "       pdf_render.py <pdf> info\n")
        return 2
    try:
        import pymupdf
    except ImportError:
        try:
            import fitz as pymupdf
        except ImportError:
            sys.stderr.write("pymupdf not installed\n")
            return 3

    path = sys.argv[1]
    if sys.argv[2] == "info":
        doc = pymupdf.open(path)
        print(doc.page_count)
        return 0

    if len(sys.argv) < 5:
        sys.stderr.write("missing args\n")
        return 2

    page = int(sys.argv[2]); dpi = int(sys.argv[3]); out = sys.argv[4]
    doc = pymupdf.open(path)
    if page < 1 or page > doc.page_count:
        sys.stderr.write("page out of range\n")
        return 4
    pg = doc.load_page(page - 1)
    zoom = dpi / 72.0
    mat = pymupdf.Matrix(zoom, zoom)
    pix = pg.get_pixmap(matrix=mat, alpha=False)
    d = os.path.dirname(out)
    if d: os.makedirs(d, exist_ok=True)
    pix.save(out)
    return 0

if __name__ == "__main__":
    sys.exit(main())
