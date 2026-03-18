# Nubank PPTX — Code Reference

## Python Constants

```python
from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.shapes import MSO_SHAPE
import os

ASSETS_DIR = os.path.expanduser("~/.cursor/skills/create-pptx/assets")

NU_PURPLE = RGBColor(0x82, 0x0A, 0xD1)
NU_DARK_PURPLE = RGBColor(0x89, 0x0E, 0xBC)
NU_DEEP_PURPLE = RGBColor(0x2F, 0x05, 0x49)
NU_LIGHT_PURPLE = RGBColor(0xC6, 0x92, 0xE9)
NU_GREY = RGBColor(0x59, 0x59, 0x59)
NU_LIGHT_GREY = RGBColor(0xEE, 0xEE, 0xEE)
NU_MID_GREY = RGBColor(0xB7, 0xB7, 0xB7)
NU_WHITE = RGBColor(0xFF, 0xFF, 0xFF)
NU_BLACK = RGBColor(0x00, 0x00, 0x00)
NU_GREEN = RGBColor(0x6A, 0xA8, 0x4F)
NU_RED = RGBColor(0xD0, 0x00, 0x00)
NU_BLUE = RGBColor(0x11, 0x55, 0xCC)
DARK_BG = RGBColor(0x1A, 0x1A, 0x2E)
```

## Helper Functions

```python
def load_logo(name="nu_logo.png"):
    return os.path.join(ASSETS_DIR, name)


def set_text(tf, text, font_size=Pt(11), color=NU_BLACK, bold=False,
             alignment=PP_ALIGN.LEFT, font_name="Google Sans"):
    tf.clear()
    tf.word_wrap = True
    p = tf.paragraphs[0]
    p.alignment = alignment
    run = p.add_run()
    run.text = text
    run.font.size = font_size
    run.font.color.rgb = color
    run.font.bold = bold
    run.font.name = font_name
    return run


def add_paragraph(tf, text, font_size=Pt(11), color=NU_BLACK, bold=False,
                  alignment=PP_ALIGN.LEFT, font_name="Google Sans",
                  space_before=Pt(0), space_after=Pt(4)):
    p = tf.add_paragraph()
    p.alignment = alignment
    p.space_before = space_before
    p.space_after = space_after
    run = p.add_run()
    run.text = text
    run.font.size = font_size
    run.font.color.rgb = color
    run.font.bold = bold
    run.font.name = font_name
    return run
```

## Type Scale

| Role | Size | Bold | Font | Color (on light bg) |
|---|---|---|---|---|
| Cover title | `Pt(37)` | Yes | `Helvetica Neue` | `NU_PURPLE` |
| Cover subtitle | `Pt(19)` | No | `Helvetica Neue` | `NU_PURPLE` |
| Agenda title | `Pt(30)` | Yes | `Roboto` | `NU_PURPLE` |
| Agenda items | `Pt(16)` | No | `Roboto Light` | `NU_BLACK` |
| Slide title | `Pt(18)` | Yes | `Roboto` | `NU_PURPLE` |
| Section divider | `Pt(40)` | No | `Roboto Light` | `NU_WHITE` |
| Body text | `Pt(11)` | No | `Google Sans` | `NU_BLACK` |
| Subtitle/caption | `Pt(12)` | No | `Roboto Light` | `NU_GREY` |
| Table header | `Pt(10)` | Yes | `Roboto` | `NU_WHITE` |
| Table body | `Pt(10)` | No | `Google Sans` | `NU_BLACK` |
| KPI value | `Pt(9)` | Yes | `Google Sans` | `NU_GREEN` |
| Footnote | `Pt(8)` | No | `Google Sans` | `NU_GREY` |

## Slide Builders

### Cover

```python
def add_cover(prs, title, subtitle=""):
    slide = prs.slides.add_slide(prs.slide_layouts[6])

    # Nu logo top-left
    logo_path = load_logo("nu_logo.png")
    slide.shapes.add_picture(logo_path, Inches(0.40), Inches(0.39),
                             width=Inches(0.85))

    # Cover decoration on right
    deco_path = load_logo("cover_decoration.png")
    slide.shapes.add_picture(deco_path, Inches(4.71), Inches(0.00),
                             width=Inches(5.63))

    # Title
    txBox = slide.shapes.add_textbox(Inches(0.5), Inches(1.2), Inches(4.0), Inches(2.5))
    set_text(txBox.text_frame, title, font_size=Pt(37), color=NU_PURPLE,
             bold=True, font_name="Helvetica Neue")

    # Subtitle
    if subtitle:
        txBox2 = slide.shapes.add_textbox(Inches(0.5), Inches(3.5), Inches(4.0), Inches(0.6))
        set_text(txBox2.text_frame, subtitle, font_size=Pt(19), color=NU_PURPLE,
                 font_name="Helvetica Neue")
    return slide
```

### Agenda

```python
def add_agenda(prs, items, highlight_idx=None):
    slide = prs.slides.add_slide(prs.slide_layouts[6])

    # Title
    txBox = slide.shapes.add_textbox(Inches(0.5), Inches(0.5), Inches(4), Inches(1))
    set_text(txBox.text_frame, "Agenda", font_size=Pt(30), color=NU_PURPLE,
             bold=True, font_name="Roboto")

    # Items
    txBox2 = slide.shapes.add_textbox(Inches(0.5), Inches(1.5), Inches(5), Inches(3.5))
    tf = txBox2.text_frame
    tf.word_wrap = True
    for i, item in enumerate(items):
        if i == 0:
            p = tf.paragraphs[0]
        else:
            p = tf.add_paragraph()
        p.space_after = Pt(10)
        run = p.add_run()
        run.text = item
        run.font.size = Pt(16)
        run.font.color.rgb = NU_BLACK
        run.font.name = "Roboto Light"
        if highlight_idx is not None and i == highlight_idx:
            run.font.bold = True
    return slide
```

### Section Divider

```python
def add_section_divider(prs, text):
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    bg = slide.background.fill
    bg.solid()
    bg.fore_color.rgb = DARK_BG

    # Section logo top-left
    logo_path = load_logo("section_logo.png")
    slide.shapes.add_picture(logo_path, Inches(0.16), Inches(0.17),
                             width=Inches(1.53))

    # Text
    txBox = slide.shapes.add_textbox(Inches(0.5), Inches(1.5), Inches(9), Inches(3.5))
    set_text(txBox.text_frame, text, font_size=Pt(40), color=NU_WHITE,
             font_name="Roboto Light")
    return slide
```

### Content Slide

```python
def add_content_slide(prs, title, body_paragraphs=None):
    slide = prs.slides.add_slide(prs.slide_layouts[6])

    # Title
    txBox = slide.shapes.add_textbox(Inches(0.3), Inches(0.3), Inches(9), Inches(0.7))
    set_text(txBox.text_frame, title, font_size=Pt(18), color=NU_PURPLE,
             bold=True, font_name="Roboto")

    # Body
    if body_paragraphs:
        txBox2 = slide.shapes.add_textbox(Inches(0.3), Inches(1.1), Inches(9.3), Inches(4.0))
        tf = txBox2.text_frame
        tf.word_wrap = True
        for i, para in enumerate(body_paragraphs):
            if i == 0:
                set_text(tf, para, font_size=Pt(11), color=NU_BLACK, font_name="Google Sans")
            else:
                add_paragraph(tf, para, font_size=Pt(11), color=NU_BLACK,
                              font_name="Google Sans", space_before=Pt(4))
    return slide
```

### Table Slide

```python
def add_table_slide(prs, title, headers, rows, left=Inches(0.3), top=Inches(1.3), width=Inches(9.4)):
    slide = prs.slides.add_slide(prs.slide_layouts[6])

    txBox = slide.shapes.add_textbox(Inches(0.3), Inches(0.3), Inches(9), Inches(0.7))
    set_text(txBox.text_frame, title, font_size=Pt(18), color=NU_PURPLE,
             bold=True, font_name="Roboto")

    num_rows = len(rows) + 1
    num_cols = len(headers)
    table_shape = slide.shapes.add_table(num_rows, num_cols, left, top, width,
                                          Inches(num_rows * 0.35))
    table = table_shape.table

    for col_idx, header in enumerate(headers):
        cell = table.cell(0, col_idx)
        cell.fill.solid()
        cell.fill.fore_color.rgb = NU_PURPLE
        cell.vertical_anchor = MSO_ANCHOR.MIDDLE
        run = cell.text_frame.paragraphs[0].add_run()
        run.text = header
        run.font.size = Pt(10)
        run.font.bold = True
        run.font.color.rgb = NU_WHITE
        run.font.name = "Roboto"

    for row_idx, row_data in enumerate(rows):
        for col_idx, value in enumerate(row_data):
            cell = table.cell(row_idx + 1, col_idx)
            cell.fill.solid()
            cell.fill.fore_color.rgb = NU_LIGHT_GREY if row_idx % 2 == 1 else NU_WHITE
            cell.vertical_anchor = MSO_ANCHOR.MIDDLE
            run = cell.text_frame.paragraphs[0].add_run()
            run.text = str(value)
            run.font.size = Pt(10)
            run.font.color.rgb = NU_BLACK
            run.font.name = "Google Sans"
    return slide, table_shape
```

### KPI Box

```python
def add_kpi_box(slide, left, top, width, height, label, value, header_color=NU_PURPLE):
    header = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, left, top,
                                     width, Inches(0.35))
    header.fill.solid()
    header.fill.fore_color.rgb = header_color
    header.line.fill.background()
    set_text(header.text_frame, label, font_size=Pt(11), color=NU_WHITE,
             bold=True, alignment=PP_ALIGN.CENTER, font_name="Google Sans")

    body = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, left,
                                   top + Inches(0.35), width,
                                   height - Inches(0.35))
    body.fill.solid()
    body.fill.fore_color.rgb = NU_LIGHT_GREY
    body.line.fill.background()
    set_text(body.text_frame, value, font_size=Pt(9), color=NU_GREEN,
             bold=True, alignment=PP_ALIGN.CENTER, font_name="Google Sans")
    return header, body
```

### Card with Bullet Points

```python
def add_bullet_card(slide, left, top, width, height, title, items,
                     header_color=NU_PURPLE):
    card = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, left, top,
                                   width, height)
    card.fill.solid()
    card.fill.fore_color.rgb = NU_LIGHT_GREY
    card.line.fill.background()

    header = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, left, top,
                                     width, Inches(0.35))
    header.fill.solid()
    header.fill.fore_color.rgb = header_color
    header.line.fill.background()
    set_text(header.text_frame, title, font_size=Pt(10), color=NU_WHITE,
             bold=True, alignment=PP_ALIGN.CENTER, font_name="Roboto")

    txBox = slide.shapes.add_textbox(left + Inches(0.15), top + Inches(0.45),
                                      width - Inches(0.3), height - Inches(0.55))
    tf = txBox.text_frame
    tf.word_wrap = True
    for i, item in enumerate(items):
        if i == 0:
            set_text(tf, f"  {item}", font_size=Pt(10), color=NU_BLACK,
                     font_name="Google Sans")
        else:
            add_paragraph(tf, f"  {item}", font_size=Pt(10), color=NU_BLACK,
                          font_name="Google Sans", space_before=Pt(3))
    return card
```

### Closing

```python
def add_closing(prs, text="Thank you"):
    slide = prs.slides.add_slide(prs.slide_layouts[6])

    # Purple accent line at the top
    line = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(0), Inches(0),
                                   Inches(10), Inches(0.06))
    line.fill.solid()
    line.fill.fore_color.rgb = NU_PURPLE
    line.line.fill.background()

    # Nu logo centered
    logo_path = load_logo("nu_logo.png")
    slide.shapes.add_picture(logo_path, Inches(4.3), Inches(1.8), width=Inches(1.4))

    # Text
    if text:
        txBox = slide.shapes.add_textbox(Inches(2), Inches(3.5), Inches(6), Inches(1))
        set_text(txBox.text_frame, text, font_size=Pt(30), color=NU_PURPLE,
                 bold=True, alignment=PP_ALIGN.CENTER, font_name="Roboto")
    return slide
```

## Script Structure

```python
#!/usr/bin/env python3
"""Generate <topic> presentation with Nubank branding."""

# === Imports & Constants ===
# === Helper Functions ===
# === Slide Builders ===

def main():
    prs = Presentation()
    prs.slide_width = Inches(10)
    prs.slide_height = Inches(5.625)

    add_cover(prs, "Title", "Subtitle")
    add_agenda(prs, ["Item 1", "Item 2", "Item 3"])
    # ... content slides ...
    add_closing(prs)

    output_path = "<topic>-deck.pptx"
    prs.save(output_path)
    print(f"Presentation saved to: {os.path.abspath(output_path)}")

if __name__ == "__main__":
    main()
```

All content must be real — no placeholder "Lorem ipsum" text.

## Spacing & Layout

- Slide padding: `Inches(0.3)` left/right, `Inches(0.3)` top
- Card gap: `Inches(0.15)`
- Card fills: `NU_LIGHT_GREY` (`#EEEEEE`)
- Content area: full slide width minus padding
- Avoid cluttering — prefer whitespace over cramming content

## Chart/Data Colors

- Primary data: Purple (`#820AD1`)
- Secondary data: Light grey (`#B7B7B7`)
- Positive values: Green (`#6AA84F`)
- Negative values: Red (`#D00000`)
- Annotations/links: Blue (`#1155CC`)
- Emphasis in text: Purple (`#890EBC`)
