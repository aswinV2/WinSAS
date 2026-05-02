import io
import json
import base64
from pypdf import PdfReader, PdfWriter
from reportlab.pdfgen import canvas as rl_canvas
from reportlab.lib.colors import HexColor
from reportlab.lib.utils import ImageReader
from PIL import Image as PILImage


def edit_pdf(pdf_bytes: bytes, annotations_json: str) -> bytes:
    """
    Burns annotations onto a PDF.
    annotations_json: JSON string of list of annotation objects.
    Each annotation targets a page_index and has a type:
      - text:     { type, page, x, y, text, font_size, color, bold, italic }
      - image:    { type, page, x, y, width, height, data }  # data = base64 png/jpg
      - rect:     { type, page, x, y, width, height, color, fill_color, stroke_width }
      - ellipse:  { type, page, x, y, width, height, color, fill_color, stroke_width }
      - line:     { type, page, x1, y1, x2, y2, color, stroke_width }
      - freehand: { type, page, points: [[x,y],...], color, stroke_width }
    All coordinates are in percentage (0-100) of page width/height.
    """
    annotations = json.loads(annotations_json)
    reader = PdfReader(io.BytesIO(pdf_bytes))
    writer = PdfWriter()

    for page_index, page in enumerate(reader.pages):
        page_width = float(page.mediabox.width)
        page_height = float(page.mediabox.height)

        # Filter annotations for this page
        page_annots = [a for a in annotations if a.get("page", 0) == page_index]

        if not page_annots:
            writer.add_page(page)
            continue

        # Create overlay canvas for this page
        overlay_buf = io.BytesIO()
        c = rl_canvas.Canvas(overlay_buf, pagesize=(page_width, page_height))

        for annot in page_annots:
            try:
                _draw_annotation(c, annot, page_width, page_height)
            except Exception as e:
                print(f"Annotation error: {e}")
                continue

        c.save()
        overlay_buf.seek(0)

        # Merge overlay onto the page
        from pypdf import PdfReader as PR
        overlay_page = PR(overlay_buf).pages[0]
        page.merge_page(overlay_page)
        writer.add_page(page)

    out = io.BytesIO()
    writer.write(out)
    out.seek(0)
    return out.read()


def _pct_to_pt(val, total):
    """Convert percentage coordinate to points."""
    return (val / 100.0) * total


def _draw_annotation(c, annot, pw, ph):
    atype = annot["type"]

    if atype == "text":
        x = _pct_to_pt(annot["x"], pw)
        # PDF y=0 is bottom, Flutter y=0 is top — flip
        y = ph - _pct_to_pt(annot["y"], ph)
        font_size = annot.get("font_size", 16)
        color = HexColor(annot.get("color", "#000000"))
        text = annot.get("text", "")
        bold = annot.get("bold", False)
        italic = annot.get("italic", False)

        if bold and italic:
            font = "Helvetica-BoldOblique"
        elif bold:
            font = "Helvetica-Bold"
        elif italic:
            font = "Helvetica-Oblique"
        else:
            font = "Helvetica"

        c.setFont(font, font_size)
        c.setFillColor(color)
        c.drawString(x, y - font_size, text)

    elif atype == "rect":
        x = _pct_to_pt(annot["x"], pw)
        y = ph - _pct_to_pt(annot["y"], ph)
        w = _pct_to_pt(annot["width"], pw)
        h = _pct_to_pt(annot["height"], ph)
        stroke_w = annot.get("stroke_width", 2)
        stroke_color = HexColor(annot.get("color", "#000000"))
        fill_color = annot.get("fill_color")

        c.setLineWidth(stroke_w)
        c.setStrokeColor(stroke_color)
        if fill_color and fill_color != "none":
            c.setFillColor(HexColor(fill_color))
            c.rect(x, y - h, w, h, stroke=1, fill=1)
        else:
            c.rect(x, y - h, w, h, stroke=1, fill=0)

    elif atype == "ellipse":
        x = _pct_to_pt(annot["x"], pw)
        y = ph - _pct_to_pt(annot["y"], ph)
        w = _pct_to_pt(annot["width"], pw)
        h = _pct_to_pt(annot["height"], ph)
        stroke_w = annot.get("stroke_width", 2)
        stroke_color = HexColor(annot.get("color", "#000000"))
        fill_color = annot.get("fill_color")

        c.setLineWidth(stroke_w)
        c.setStrokeColor(stroke_color)
        cx = x + w / 2
        cy = y - h / 2
        if fill_color and fill_color != "none":
            c.setFillColor(HexColor(fill_color))
            c.ellipse(cx - w/2, cy - h/2, cx + w/2, cy + h/2, stroke=1, fill=1)
        else:
            c.ellipse(cx - w/2, cy - h/2, cx + w/2, cy + h/2, stroke=1, fill=0)

    elif atype == "line":
        x1 = _pct_to_pt(annot["x1"], pw)
        y1 = ph - _pct_to_pt(annot["y1"], ph)
        x2 = _pct_to_pt(annot["x2"], pw)
        y2 = ph - _pct_to_pt(annot["y2"], ph)
        stroke_w = annot.get("stroke_width", 2)
        color = HexColor(annot.get("color", "#000000"))

        c.setLineWidth(stroke_w)
        c.setStrokeColor(color)
        c.line(x1, y1, x2, y2)

    elif atype == "freehand":
        points = annot.get("points", [])
        if len(points) < 2:
            return
        stroke_w = annot.get("stroke_width", 2)
        color = HexColor(annot.get("color", "#000000"))

        c.setLineWidth(stroke_w)
        c.setStrokeColor(color)
        c.setLineCap(1)  # round cap

        p = c.beginPath()
        x0 = _pct_to_pt(points[0][0], pw)
        y0 = ph - _pct_to_pt(points[0][1], ph)
        p.moveTo(x0, y0)
        for pt in points[1:]:
            px = _pct_to_pt(pt[0], pw)
            py = ph - _pct_to_pt(pt[1], ph)
            p.lineTo(px, py)
        c.drawPath(p, stroke=1, fill=0)

    elif atype == "image":
        x = _pct_to_pt(annot["x"], pw)
        y = ph - _pct_to_pt(annot["y"], ph)
        w = _pct_to_pt(annot["width"], pw)
        h = _pct_to_pt(annot["height"], ph)
        data = annot.get("data", "")

        # Strip data URL prefix if present
        if "," in data:
            data = data.split(",")[1]

        img_bytes = base64.b64decode(data)
        pil_img = PILImage.open(io.BytesIO(img_bytes))
        if pil_img.mode in ("RGBA", "P"):
            pil_img = pil_img.convert("RGB")

        img_buf = io.BytesIO()
        pil_img.save(img_buf, format="JPEG", quality=90)
        img_buf.seek(0)

        c.drawImage(ImageReader(img_buf), x, y - h, width=w, height=h)