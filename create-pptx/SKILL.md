---
name: create-pptx
description: >-
  Generate PowerPoint (.pptx) presentations with Nubank visual identity using
  python-pptx. Use when asked to create a PowerPoint, pptx, presentation, deck,
  or slides.
---

# Nubank-Style PowerPoint Builder

Generate Python scripts using `python-pptx` to build `.pptx` slide decks matching Nubank's corporate style.

## Prerequisites

```bash
pip install python-pptx --index-url https://pypi.org/simple/
```

## Output Format

Generate a Python script that:
1. Imports `python-pptx` and helpers
2. Loads the Nu logo from the assets folder
3. Builds all slides programmatically with Nubank branding
4. Saves as `<topic>-deck.pptx`

## Slide Size

Standard widescreen 16:9: `Inches(10) x Inches(5.625)`

## Brand Colors

| Token | Hex | Usage |
|---|---|---|
| `NU_PURPLE` | `#820AD1` | Primary brand. Slide titles, header fills, accents |
| `NU_DARK_PURPLE` | `#890EBC` | Secondary purple. Flow diagrams, model boxes |
| `NU_DEEP_PURPLE` | `#2F0549` | Very dark purple. Deep emphasis text |
| `NU_LIGHT_PURPLE` | `#C692E9` | Light purple fills. Soft accents |
| `NU_GREY` | `#595959` | Subtitles, chart titles, secondary body text |
| `NU_LIGHT_GREY` | `#EEEEEE` | Card/panel fills, shape backgrounds |
| `NU_MID_GREY` | `#B7B7B7` | Borders, dividers, secondary shapes |
| `NU_WHITE` | `#FFFFFF` | Slide backgrounds, text on dark surfaces |
| `NU_BLACK` | `#000000` | Primary body text on light backgrounds |
| `NU_GREEN` | `#6AA84F` | Positive values, green metrics |
| `NU_RED` | `#D00000` | Negative status, alerts |
| `NU_BLUE` | `#1155CC` | Links, flow arrows, annotations |

## Fonts

| Font | Usage |
|---|---|
| `Google Sans` | Primary font for most content: body, tables, insights, callouts |
| `Google Sans Medium` | Section titles, framework labels |
| `Roboto` | Slide titles, table chart titles, bold headings |
| `Roboto Light` | Body text, agenda items, flow descriptions |
| `Helvetica Neue` | Cover slide titles only |

**Fallback**: If Google Sans is not available, use `Roboto` as primary.

## Type Scale

| Role | Size (Pt) | Font | Bold | Color |
|---|---|---|---|---|
| Cover title | 37 | Helvetica Neue | Yes | `NU_PURPLE` |
| Cover subtitle | 19 | Helvetica Neue | No | `NU_PURPLE` |
| Agenda title | 30 | Roboto | Yes | `NU_PURPLE` |
| Agenda items | 16 | Roboto Light | No | `NU_BLACK` |
| Slide title | 18-21 | Roboto | Yes | `NU_PURPLE` |
| Section divider text | 40 | Roboto Light | No | `NU_WHITE` |
| Body text | 11-12 | Google Sans / Roboto Light | No | `NU_BLACK` or `NU_GREY` |
| Table header | 10 | Roboto / Google Sans | Yes | `NU_WHITE` |
| Table body | 8-10 | Google Sans | No | `NU_BLACK` |
| Footnote/caption | 8 | Google Sans | No | `NU_GREY` |
| KPI value | 9 | Google Sans | Yes | `NU_GREEN` |
| KPI label | 11 | Google Sans | Yes | `NU_WHITE` |

## Logo Assets

Logos are stored in `~/.cursor/skills/create-pptx/assets/`:

| File | Usage | Typical Size |
|---|---|---|
| `nu_logo.png` | Cover slide (top-left), content slides | `0.85 x 0.46 in` at `(0.40, 0.39)` |
| `section_logo.png` | Section divider slides (top-left) | `1.53 x 1.53 in` at `(0.16, 0.17)` |
| `cover_decoration.png` | Cover slide (right side decoration) | `5.63 x 5.63 in` at `(4.71, 0.00)` |
| ~~`agenda_bg.png`~~ | **Do not use** - removed from design | - |

## Key Rules

- **NO chrome**: Do NOT add "Nubank" / "Confidential" text to every slide
- **Cover slide**: White bg, purple title (`Helvetica Neue` 37pt), Nu logo top-left, cover decoration image on right
- **Agenda slides**: White background, purple title (`Roboto` 30pt bold), black items (`Roboto Light` 16pt). Do NOT use background images
- **Section dividers**: Solid dark/purple bg, large white text (40pt), section logo top-left
- **Content slides**: White bg, purple Roboto title (18-21pt), Google Sans body
- **Tables**: Purple header row (`#820AD1`) with white text, alternating white/`#EEEEEE` rows
- **Emphasis text**: Use purple color for key findings/insights
- **Positive values**: Green `#6AA84F`
- **Flow/link text**: Blue `#1155CC`
- **Card fills**: Light grey `#EEEEEE`
- **Fonts**: Never use `Inter`. Use `Google Sans`, `Roboto`, `Roboto Light`, or `Helvetica Neue`

## Slide Types

1. **Cover**: White bg, purple `Helvetica Neue` 37pt title, subtitle 19pt, Nu logo top-left (`0.85x0.46in`), cover decoration image on right side
2. **Agenda**: White bg, "Agenda" in `Roboto` 30pt purple bold, numbered items in `Roboto Light` 16pt black. No background image
3. **Section Divider**: Solid dark bg, large white text (40pt `Roboto Light`), section logo top-left (`1.53x1.53in`)
4. **Content (text + insights)**: White bg, purple Roboto title, Google Sans body, purple-colored key findings
5. **What | Why | Impact**: Multi-section layout with KPI boxes (dark purple headers, green metric values)
6. **Data/Chart Slide**: Title in grey bold, embedded chart images, purple/grey text annotations
7. **Table Slide**: Purple title, full-width table with purple header row and alternating row fills
8. **Framework/Timeline**: Milestone boxes with purple labels, descriptive text
9. **Next Steps**: Numbered items with icons, purple accent headers
10. **Monitoring/Metrics Table**: Multi-column table with detailed descriptions
11. **Closing**: White bg, Nu logo centered, optional "Thank you" in purple. Clean and minimal - no dark backgrounds

## Do / Don't

**DO**: Use white backgrounds for content slides, purple titles (Roboto), Google Sans for body text, green for positive metrics, load logos from assets folder, use `Inches(10) x Inches(5.625)` slide size.

**DON'T**: Use Inter font, add "Nubank"/"Confidential" chrome, use `Inches(13.333)` slide size, download logos from CDN, use emoji icons, use colored card backgrounds other than light grey, use dark/black backgrounds for closing slides, use background images on agenda slides.

## Detailed Reference

For complete code examples, helper functions, chart styling, and slide builder functions, see [reference.md](reference.md).
