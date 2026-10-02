from pathlib import Path
from reportlab.lib.colors import Color, HexColor, black, white
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase.pdfmetrics import stringWidth
from reportlab.pdfgen import canvas
from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "output" / "pdf" / "blurb-demo-newsletter.pdf"
SOURCE_IMAGE = ROOT / "blurb" / "Assets.xcassets" / "DemoWrappedContactSheet.imageset" / "demo-wrapped-contact-sheet.png"
W, H = letter
MARGIN = 42
PAPER = HexColor("#F7F1DE")
INK = HexColor("#121212")
MUTED = HexColor("#77736A")
ACCENT = HexColor("#EB477A")
RULE = HexColor("#2A2926")

PEOPLE = ["You", "Maya", "Alex", "Jordan"]
QUESTIONS = [
    (
        "How did this month feel, in a few honest words?",
        [
            "Full, surprising, and a little slower than I expected - in a good way.",
            "Restorative. I finally made room for weekends that did not need an itinerary.",
            "A little chaotic, but full of the kind of stories I know we will retell.",
            "Hopeful. A lot of small things started moving in the right direction.",
        ],
    ),
    (
        "What was your favorite day this month, and why?",
        [
            "The Saturday we got breakfast, walked by the water, and stayed out until sunset.",
            "Dinner at Jordan's. We planned to stay for an hour and somehow talked until midnight.",
            "The beach day - even the part where we forgot the towels and had to improvise.",
            "My quiet Sunday morning with coffee, music, and nowhere I needed to be.",
        ],
    ),
    (
        "When did you practice gratitude this month?",
        [
            "On a difficult Tuesday, I wrote down three ordinary things that were still good.",
            "Every time somebody in this group checked in without needing a reason.",
            "Driving home after the concert, tired and happy, with everyone singing badly.",
            "When my mom called with good news and I remembered not to rush the conversation.",
        ],
    ),
    (
        "What did this month teach you about yourself?",
        [
            "I do not need a perfect plan before I begin.",
            "Rest is more useful when I stop trying to earn it first.",
            "I am better at asking for help than I used to be.",
            "Consistency can be quiet. It does not have to look impressive to count.",
        ],
    ),
]

SELF_CAPTIONS = [
    "Golden hour with the group",
    "A Saturday by the water",
    "Finally made it to the concert",
    "The quiet morning I needed",
]
FOOD_CAPTIONS = [
    "The pasta worth waiting for",
    "Perfect late-night tacos",
    "Breakfast that became lunch",
    "Homemade dumplings at last",
]


def fill_page(c):
    c.setFillColor(PAPER)
    c.rect(0, 0, W, H, stroke=0, fill=1)


def header(c, section, page):
    c.setFillColor(INK)
    c.setFont("Helvetica-Bold", 9)
    c.drawString(MARGIN, H - 29, "DAILY BLURB")
    c.setFillColor(ACCENT)
    c.rect(W - MARGIN - 112, H - 36, 112, 18, stroke=0, fill=1)
    c.setFillColor(black)
    c.setFont("Helvetica-Bold", 7.5)
    c.drawCentredString(W - MARGIN - 56, H - 30, section.upper())
    c.setStrokeColor(RULE)
    c.setLineWidth(2)
    c.line(MARGIN, H - 44, W - MARGIN, H - 44)
    c.setFont("Helvetica", 7.5)
    c.setFillColor(MUTED)
    c.drawRightString(W - MARGIN, 21, f"MIH - SEPTEMBER 2026  /  {page}")


def accent_label(c, text, x, y, width=None):
    c.setFont("Helvetica-Bold", 8)
    if width is None:
        width = stringWidth(text.upper(), "Helvetica-Bold", 8) + 18
    c.setFillColor(ACCENT)
    c.rect(x, y - 4, width, 18, stroke=0, fill=1)
    c.setFillColor(black)
    c.drawString(x + 9, y + 1, text.upper())
    return width


def wrapped_lines(c, text, font, size, max_width):
    words = text.split()
    lines, line = [], ""
    for word in words:
        trial = f"{line} {word}".strip()
        if stringWidth(trial, font, size) <= max_width:
            line = trial
        else:
            if line:
                lines.append(line)
            line = word
    if line:
        lines.append(line)
    return lines


def draw_wrapped(c, text, x, y, width, font="Times-Roman", size=15, leading=19, color=INK, max_lines=None):
    lines = wrapped_lines(c, text, font, size, width)
    if max_lines:
        lines = lines[:max_lines]
    c.setFont(font, size)
    c.setFillColor(color)
    for line in lines:
        c.drawString(x, y, line)
        y -= leading
    return y


def cover(c):
    fill_page(c)
    c.setFillColor(ACCENT)
    c.rect(0, 0, 18, H, stroke=0, fill=1)
    accent_label(c, "Demo edition", MARGIN, H - 78, 92)
    c.setFillColor(INK)
    c.setFont("Times-Bold", 47)
    c.drawString(MARGIN, H - 154, "THE MIH TIMES")
    c.setLineWidth(5)
    c.line(MARGIN, H - 174, W - MARGIN, H - 174)
    c.setFont("Helvetica-Bold", 11)
    c.drawString(MARGIN, H - 201, "SEPTEMBER 2026  /  MONTHLY NEWSLETTER")
    c.setFillColor(MUTED)
    c.setFont("Times-Italic", 17)
    c.drawString(MARGIN, H - 235, "The stories, people, and moments that defined our month.")

    c.setFillColor(white)
    c.roundRect(MARGIN, 174, W - 2 * MARGIN, 260, 4, stroke=0, fill=1)
    c.setStrokeColor(INK)
    c.setLineWidth(2)
    c.roundRect(MARGIN, 174, W - 2 * MARGIN, 260, 4, stroke=1, fill=0)
    accent_label(c, "Inside this issue", MARGIN + 22, 404, 108)
    items = [
        ("01", "The month in numbers", "16 answers, 4 voices, 8 photos"),
        ("02", "The month in words", "Four Friday reflections from everyone"),
        ("03", "The photo desk", "The places, meals, and faces worth keeping"),
    ]
    y = 360
    for number, title, subtitle in items:
        c.setFillColor(ACCENT)
        c.circle(MARGIN + 38, y + 6, 17, stroke=0, fill=1)
        c.setFillColor(black)
        c.setFont("Helvetica-Bold", 9)
        c.drawCentredString(MARGIN + 38, y + 3, number)
        c.setFont("Times-Bold", 17)
        c.drawString(MARGIN + 72, y + 10, title)
        c.setFont("Helvetica", 9)
        c.setFillColor(MUTED)
        c.drawString(MARGIN + 72, y - 6, subtitle)
        y -= 70

    c.setFillColor(INK)
    c.setFont("Helvetica-Bold", 8)
    c.drawString(MARGIN, 56, "PRIVATE TO MIH")
    c.setFillColor(MUTED)
    c.setFont("Helvetica", 8)
    c.drawRightString(W - MARGIN, 56, "Made with Blurb")
    c.showPage()


def overview(c):
    fill_page(c)
    header(c, "By the numbers", 2)
    accent_label(c, "Monthly dispatch", MARGIN, H - 82, 112)
    c.setFillColor(INK)
    c.setFont("Times-Bold", 31)
    c.drawString(MARGIN, H - 128, "The month, at a glance")

    stats = [("16", "ANSWERS"), ("4", "QUESTIONS"), ("8", "PHOTOS"), ("4", "PEOPLE")]
    gap = 10
    box_w = (W - 2 * MARGIN - 3 * gap) / 4
    x = MARGIN
    for value, label in stats:
        c.setFillColor(white)
        c.rect(x, H - 237, box_w, 78, stroke=0, fill=1)
        c.setStrokeColor(INK)
        c.rect(x, H - 237, box_w, 78, stroke=1, fill=0)
        c.setFillColor(INK)
        c.setFont("Times-Bold", 29)
        c.drawCentredString(x + box_w / 2, H - 196, value)
        c.setFont("Helvetica-Bold", 7)
        c.drawCentredString(x + box_w / 2, H - 219, label)
        x += box_w + gap

    c.setFillColor(white)
    c.roundRect(MARGIN, 312, W - 2 * MARGIN, 202, 4, stroke=0, fill=1)
    c.setStrokeColor(INK)
    c.setLineWidth(1.5)
    c.roundRect(MARGIN, 312, W - 2 * MARGIN, 202, 4, stroke=1, fill=0)
    accent_label(c, "Monthly winners", MARGIN + 20, 480, 104)
    winners = [
        ("MOST QUESTIONS ANSWERED", "Maya", "Showed up for every Friday reflection"),
        ("POINTS LEADER", "You", "Led the month across Daily Blurbs"),
    ]
    y = 438
    for eyebrow, name, note in winners:
        c.setFont("Helvetica-Bold", 7)
        c.setFillColor(MUTED)
        c.drawString(MARGIN + 22, y, eyebrow)
        c.setFillColor(INK)
        c.setFont("Times-Bold", 22)
        c.drawString(MARGIN + 22, y - 27, name)
        c.setFont("Times-Italic", 11)
        c.setFillColor(MUTED)
        c.drawString(MARGIN + 140, y - 23, note)
        y -= 75

    accent_label(c, "Blurb map", MARGIN, 270, 76)
    c.setFont("Times-Bold", 21)
    c.setFillColor(INK)
    c.drawString(MARGIN, 232, "Three cities, one conversation")
    cities = [("Oakland, CA", 7), ("Seattle, WA", 5), ("Brooklyn, NY", 4)]
    y = 188
    for city, count in cities:
        c.setFillColor(ACCENT)
        c.circle(MARGIN + 9, y + 3, 7, stroke=0, fill=1)
        c.setFillColor(INK)
        c.setFont("Times-Bold", 14)
        c.drawString(MARGIN + 28, y, city)
        c.setFont("Helvetica-Bold", 9)
        c.drawRightString(W - MARGIN, y, f"{count} RESPONSES")
        c.setStrokeColor(Color(0, 0, 0, alpha=0.12))
        c.line(MARGIN + 28, y - 10, W - MARGIN, y - 10)
        y -= 38
    c.showPage()


def question_page(c, page, index, question, answers):
    fill_page(c)
    header(c, "The month in words", page)
    accent_label(c, f"Question {index:02d}", MARGIN, H - 82, 82)
    y = draw_wrapped(c, question, MARGIN, H - 128, W - 2 * MARGIN, "Times-Bold", 29, 33)
    y -= 12
    c.setStrokeColor(INK)
    c.setLineWidth(2)
    c.line(MARGIN, y, W - MARGIN, y)
    y -= 37
    for person, answer in zip(PEOPLE, answers):
        c.setFillColor(ACCENT)
        c.circle(MARGIN + 16, y - 1, 16, stroke=0, fill=1)
        c.setFillColor(black)
        c.setFont("Helvetica-Bold", 10)
        c.drawCentredString(MARGIN + 16, y - 4, person[0])
        c.setFillColor(INK)
        c.setFont("Helvetica-Bold", 8)
        c.drawString(MARGIN + 47, y + 8, person.upper())
        y = draw_wrapped(c, answer, MARGIN + 47, y - 14, W - 2 * MARGIN - 47, "Times-Roman", 15, 20)
        y -= 22
        c.setStrokeColor(Color(0, 0, 0, alpha=0.14))
        c.line(MARGIN + 47, y + 8, W - MARGIN, y + 8)
    c.setFillColor(MUTED)
    c.setFont("Times-Italic", 11)
    c.drawString(MARGIN, 48, "Newsletter answers remain editable until the monthly edition is created.")
    c.showPage()


def photo_page(c):
    fill_page(c)
    header(c, "The photo desk", 7)
    accent_label(c, "Photo highlights", MARGIN, H - 82, 104)
    c.setFillColor(INK)
    c.setFont("Times-Bold", 30)
    c.drawString(MARGIN, H - 128, "Eight moments worth keeping")
    c.setFont("Times-Italic", 12)
    c.setFillColor(MUTED)
    c.drawString(MARGIN, H - 151, "Each member's Photo of the Month, with the caption they chose.")

    sheet = Image.open(SOURCE_IMAGE).convert("RGB")
    cols, rows = 4, 2
    cell_w, cell_h = sheet.width // cols, sheet.height // rows
    cards = []
    for i in range(8):
        col, row = i % 4, i // 4
        crop = sheet.crop((col * cell_w, row * cell_h, (col + 1) * cell_w, (row + 1) * cell_h))
        cards.append(crop)

    grid_top = H - 178
    gap = 13
    card_w = (W - 2 * MARGIN - gap) / 2
    image_h = 111
    card_h = 137
    captions = SELF_CAPTIONS + FOOD_CAPTIONS
    authors = PEOPLE + PEOPLE
    for i, image in enumerate(cards):
        col, row = i % 2, i // 2
        x = MARGIN + col * (card_w + gap)
        top = grid_top - row * (card_h + 10)
        y = top - card_h
        c.setFillColor(white)
        c.rect(x, y, card_w, card_h, stroke=0, fill=1)
        c.setStrokeColor(INK)
        c.setLineWidth(1)
        c.rect(x, y, card_w, card_h, stroke=1, fill=0)
        img = ImageReader(image)
        c.drawImage(img, x + 5, y + card_h - image_h - 5, card_w - 10, image_h, preserveAspectRatio=True, anchor="c", mask="auto")
        c.setFillColor(INK)
        c.setFont("Times-Bold", 9)
        c.drawString(x + 6, y + 13, captions[i])
        c.setFont("Helvetica-Bold", 6.5)
        c.setFillColor(MUTED)
        c.drawRightString(x + card_w - 6, y + 13, authors[i].upper())
    c.showPage()


def closing(c):
    fill_page(c)
    header(c, "Final note", 8)
    c.setFillColor(ACCENT)
    c.rect(MARGIN, 504, W - 2 * MARGIN, 154, stroke=0, fill=1)
    c.setFillColor(black)
    c.setFont("Helvetica-Bold", 9)
    c.drawString(MARGIN + 26, 624, "END OF THE SEPTEMBER EDITION")
    c.setFont("Times-Bold", 34)
    c.drawString(MARGIN + 26, 578, "See you next month.")
    c.setFont("Times-Roman", 15)
    c.drawString(MARGIN + 26, 548, "Keep answering. Keep noticing. Keep the good stories close.")

    c.setFillColor(INK)
    c.setFont("Times-Bold", 29)
    c.drawString(MARGIN, 432, "A month looks different")
    c.drawString(MARGIN, 397, "through everyone's eyes.")
    c.setStrokeColor(INK)
    c.setLineWidth(4)
    c.line(MARGIN, 370, W - MARGIN, 370)

    c.setFont("Helvetica-Bold", 8)
    c.drawString(MARGIN, 325, "WHAT HAPPENS NEXT")
    notes = [
        "New newsletter questions arrive on Fridays.",
        "Group-added questions stay private to MiH.",
        "Photos and captions can be changed until month-end.",
        "This finished edition stays in the group archive.",
    ]
    y = 288
    for note in notes:
        c.setFillColor(ACCENT)
        c.circle(MARGIN + 7, y + 3, 5, stroke=0, fill=1)
        c.setFillColor(INK)
        c.setFont("Times-Roman", 14)
        c.drawString(MARGIN + 23, y, note)
        y -= 34

    c.setFillColor(MUTED)
    c.setFont("Helvetica", 8)
    c.drawString(MARGIN, 58, "DEMO CONTENT - PREVIEW OF BLURB PREMIUM NEWSLETTER EXPORT")
    c.showPage()


def contact_sheet_cells():
    sheet = Image.open(SOURCE_IMAGE).convert("RGB")
    cell_w, cell_h = sheet.width // 4, sheet.height // 2
    return [
        sheet.crop(((i % 4) * cell_w, (i // 4) * cell_h, ((i % 4) + 1) * cell_w, ((i // 4) + 1) * cell_h))
        for i in range(8)
    ]


def magazine_cover(c):
    fill_page(c)
    c.setFillColor(ACCENT)
    c.rect(0, 0, 16, H, stroke=0, fill=1)
    c.setFillColor(INK)
    c.setFont("Helvetica-Bold", 8)
    c.drawString(MARGIN, H - 34, "DAILY BLURB  /  DEMO EDITION")
    c.drawRightString(W - MARGIN, H - 34, "SEPTEMBER 2026")
    c.setLineWidth(5)
    c.line(MARGIN, H - 48, W - MARGIN, H - 48)
    c.setFont("Times-Bold", 46)
    c.drawString(MARGIN, H - 104, "THE MIH TIMES")
    c.setFont("Times-Italic", 15)
    c.setFillColor(MUTED)
    c.drawString(MARGIN, H - 130, "Four voices. Four questions. One month worth keeping.")

    cells = contact_sheet_cells()
    hero_y, hero_h = 302, 300
    left_w = 328
    c.setFillColor(white)
    c.rect(MARGIN, hero_y, left_w, hero_h, stroke=0, fill=1)
    c.setStrokeColor(INK)
    c.setLineWidth(1.5)
    c.rect(MARGIN, hero_y, left_w, hero_h, stroke=1, fill=0)
    c.drawImage(ImageReader(cells[0]), MARGIN + 7, hero_y + 7, left_w - 14, hero_h - 14, preserveAspectRatio=True, anchor="c", mask="auto")

    side_x = MARGIN + left_w + 14
    side_w = W - MARGIN - side_x
    accent_label(c, "In this issue", side_x, hero_y + hero_h - 12, side_w)
    c.setFillColor(INK)
    c.setFont("Times-Bold", 21)
    c.drawString(side_x, hero_y + hero_h - 63, "The month")
    c.drawString(side_x, hero_y + hero_h - 88, "in words")
    c.setFont("Times-Roman", 11)
    y = hero_y + hero_h - 122
    for number, question in enumerate([q[0] for q in QUESTIONS], 1):
        c.setFillColor(ACCENT)
        c.circle(side_x + 9, y + 3, 8, stroke=0, fill=1)
        c.setFillColor(black)
        c.setFont("Helvetica-Bold", 6)
        c.drawCentredString(side_x + 9, y + 1, f"{number:02d}")
        y = draw_wrapped(c, question, side_x + 24, y + 8, side_w - 24, "Times-Bold", 10.5, 13)
        y -= 15

    c.setFillColor(INK)
    c.setFont("Times-Bold", 12)
    c.drawString(MARGIN, 280, "GOLDEN HOUR WITH THE GROUP")
    c.setFont("Helvetica", 8)
    c.setFillColor(MUTED)
    c.drawRightString(MARGIN + left_w, 280, "PHOTO OF THE MONTH  /  YOU")

    stats = [("16", "ANSWERS"), ("4", "QUESTIONS"), ("8", "PHOTOS"), ("3", "CITIES")]
    gap = 8
    box_w = (W - 2 * MARGIN - gap * 3) / 4
    for i, (value, label) in enumerate(stats):
        x = MARGIN + i * (box_w + gap)
        c.setFillColor(ACCENT if i == 0 else white)
        c.rect(x, 184, box_w, 62, stroke=0, fill=1)
        c.setStrokeColor(INK)
        c.rect(x, 184, box_w, 62, stroke=1, fill=0)
        c.setFillColor(black)
        c.setFont("Times-Bold", 23)
        c.drawCentredString(x + box_w / 2, 214, value)
        c.setFont("Helvetica-Bold", 6.5)
        c.drawCentredString(x + box_w / 2, 198, label)

    c.setFillColor(INK)
    c.setFont("Times-Bold", 18)
    c.drawString(MARGIN, 137, "Inside: reflections, winners, photos, and the map")
    c.setStrokeColor(INK)
    c.setLineWidth(2)
    c.line(MARGIN, 122, W - MARGIN, 122)
    c.setFillColor(MUTED)
    c.setFont("Times-Italic", 10)
    c.drawString(MARGIN, 93, "A private monthly recap for MiH. Made from the answers and moments everyone chose to share.")
    c.setFont("Helvetica-Bold", 7)
    c.drawString(MARGIN, 52, "PRIVATE TO MIH")
    c.drawRightString(W - MARGIN, 52, "MADE WITH BLURB")
    c.showPage()


def compact_question_spread(c, page, question_items):
    fill_page(c)
    header(c, "The month in words", page)
    top = H - 70
    section_h = 326
    for section_index, (question_number, question, answers) in enumerate(question_items):
        section_top = top - section_index * (section_h + 17)
        accent_label(c, f"Question {question_number:02d}", MARGIN, section_top - 8, 80)
        title_y = draw_wrapped(c, question, MARGIN, section_top - 42, W - 2 * MARGIN, "Times-Bold", 23, 25, max_lines=2)
        rule_y = title_y - 3
        c.setStrokeColor(INK)
        c.setLineWidth(1.5)
        c.line(MARGIN, rule_y, W - MARGIN, rule_y)

        col_gap = 18
        col_w = (W - 2 * MARGIN - col_gap) / 2
        base_y = rule_y - 24
        for i, (person, answer) in enumerate(zip(PEOPLE, answers)):
            col = i % 2
            row = i // 2
            x = MARGIN + col * (col_w + col_gap)
            y = base_y - row * 104
            c.setFillColor(ACCENT)
            c.circle(x + 10, y + 2, 10, stroke=0, fill=1)
            c.setFillColor(black)
            c.setFont("Helvetica-Bold", 7)
            c.drawCentredString(x + 10, y, person[0])
            c.setFillColor(INK)
            c.setFont("Helvetica-Bold", 7)
            c.drawString(x + 27, y + 7, person.upper())
            draw_wrapped(c, answer, x + 27, y - 9, col_w - 27, "Times-Roman", 11.5, 14, max_lines=5)
            c.setStrokeColor(Color(0, 0, 0, alpha=0.12))
            c.line(x + 27, y - 75, x + col_w, y - 75)
    c.showPage()


def magazine_closing_spread(c):
    fill_page(c)
    header(c, "Photos and highlights", 4)
    accent_label(c, "The photo desk", MARGIN, H - 82, 92)
    c.setFillColor(INK)
    c.setFont("Times-Bold", 27)
    c.drawString(MARGIN, H - 124, "Eight moments worth keeping")

    cells = contact_sheet_cells()
    captions = SELF_CAPTIONS + FOOD_CAPTIONS
    authors = PEOPLE + PEOPLE
    gap = 8
    card_w = (W - 2 * MARGIN - 3 * gap) / 4
    image_h = 105
    card_h = 129
    grid_top = H - 150
    for i, image in enumerate(cells):
        col, row = i % 4, i // 4
        x = MARGIN + col * (card_w + gap)
        y = grid_top - (row + 1) * card_h - row * gap
        c.setFillColor(white)
        c.rect(x, y, card_w, card_h, stroke=0, fill=1)
        c.setStrokeColor(INK)
        c.rect(x, y, card_w, card_h, stroke=1, fill=0)
        c.drawImage(ImageReader(image), x + 4, y + 20, card_w - 8, image_h, preserveAspectRatio=True, anchor="c", mask="auto")
        c.setFillColor(INK)
        c.setFont("Times-Bold", 6.8)
        caption = captions[i]
        if stringWidth(caption, "Times-Bold", 6.8) > card_w - 26:
            caption = caption[:21] + "..."
        c.drawString(x + 4, y + 8, caption)
        c.setFont("Helvetica-Bold", 5.5)
        c.setFillColor(MUTED)
        c.drawRightString(x + card_w - 4, y + 8, authors[i].upper())

    lower_top = 320
    left_w = 300
    c.setFillColor(white)
    c.rect(MARGIN, 92, left_w, lower_top - 92, stroke=0, fill=1)
    c.setStrokeColor(INK)
    c.rect(MARGIN, 92, left_w, lower_top - 92, stroke=1, fill=0)
    accent_label(c, "Monthly winners", MARGIN + 15, lower_top - 27, 96)
    c.setFillColor(INK)
    c.setFont("Helvetica-Bold", 7)
    c.drawString(MARGIN + 15, lower_top - 66, "MOST QUESTIONS ANSWERED")
    c.setFont("Times-Bold", 25)
    c.drawString(MARGIN + 15, lower_top - 94, "Maya")
    c.setFont("Helvetica-Bold", 7)
    c.drawString(MARGIN + 15, lower_top - 130, "POINTS LEADER")
    c.setFont("Times-Bold", 25)
    c.drawString(MARGIN + 15, lower_top - 158, "You")
    c.setFont("Times-Italic", 10)
    c.setFillColor(MUTED)
    c.drawString(MARGIN + 15, 112, "Small rituals. Good stories. A month together.")

    right_x = MARGIN + left_w + 14
    right_w = W - MARGIN - right_x
    c.setFillColor(ACCENT)
    c.rect(right_x, 92, right_w, lower_top - 92, stroke=0, fill=1)
    c.setFillColor(black)
    c.setFont("Helvetica-Bold", 7)
    c.drawString(right_x + 17, lower_top - 28, "THE MONTH ON THE MAP")
    c.setFont("Times-Bold", 21)
    c.drawString(right_x + 17, lower_top - 62, "3 cities")
    cities = [("Oakland, CA", "7"), ("Seattle, WA", "5"), ("Brooklyn, NY", "4")]
    y = lower_top - 100
    for city, count in cities:
        c.setFillColor(black)
        c.circle(right_x + 21, y + 2, 4, stroke=0, fill=1)
        c.setFont("Times-Bold", 10)
        c.drawString(right_x + 34, y, city)
        c.setFont("Helvetica-Bold", 7)
        c.drawRightString(right_x + right_w - 17, y, count)
        y -= 29
    c.setFont("Times-Bold", 17)
    c.drawString(right_x + 17, 119, "See you next month.")
    c.setFont("Helvetica", 7)
    c.drawString(right_x + 17, 105, "KEEP ANSWERING. KEEP NOTICING.")
    c.showPage()


def two_page_words(c):
    fill_page(c)
    c.setFillColor(ACCENT)
    c.rect(0, 0, 14, H, stroke=0, fill=1)
    c.setFillColor(INK)
    c.setFont("Helvetica-Bold", 7.5)
    c.drawString(MARGIN, H - 28, "DAILY BLURB  /  DEMO EDITION")
    c.drawRightString(W - MARGIN, H - 28, "SEPTEMBER 2026")
    c.setLineWidth(4)
    c.line(MARGIN, H - 39, W - MARGIN, H - 39)
    c.setFont("Times-Bold", 36)
    c.drawString(MARGIN, H - 82, "THE MIH TIMES")
    c.setFont("Times-Italic", 11.5)
    c.setFillColor(MUTED)
    c.drawString(MARGIN, H - 103, "Four voices, four Friday questions, and one month worth keeping.")

    stats = [("16", "ANSWERS"), ("4", "QUESTIONS"), ("8", "PHOTOS"), ("3", "CITIES")]
    gap = 7
    box_w = (W - 2 * MARGIN - 3 * gap) / 4
    for i, (value, label) in enumerate(stats):
        x = MARGIN + i * (box_w + gap)
        c.setFillColor(ACCENT if i == 0 else white)
        c.rect(x, H - 158, box_w, 39, stroke=0, fill=1)
        c.setStrokeColor(INK)
        c.setLineWidth(0.8)
        c.rect(x, H - 158, box_w, 39, stroke=1, fill=0)
        c.setFillColor(black)
        c.setFont("Times-Bold", 16)
        c.drawCentredString(x + box_w / 2, H - 140, value)
        c.setFont("Helvetica-Bold", 5.5)
        c.drawCentredString(x + box_w / 2, H - 152, label)

    section_top = H - 180
    section_h = 138
    col_gap = 15
    col_w = (W - 2 * MARGIN - col_gap) / 2
    for q_index, (question, answers) in enumerate(QUESTIONS, start=1):
        top = section_top - (q_index - 1) * section_h
        accent_label(c, f"Question {q_index:02d}", MARGIN, top, 70)
        title_y = draw_wrapped(c, question, MARGIN + 82, top + 6, W - 2 * MARGIN - 82, "Times-Bold", 15.5, 17, max_lines=2)
        rule_y = min(top - 17, title_y - 2)
        c.setStrokeColor(INK)
        c.setLineWidth(1)
        c.line(MARGIN, rule_y, W - MARGIN, rule_y)

        base_y = rule_y - 17
        for i, (person, answer) in enumerate(zip(PEOPLE, answers)):
            col, row = i % 2, i // 2
            x = MARGIN + col * (col_w + col_gap)
            y = base_y - row * 48
            c.setFillColor(ACCENT)
            c.circle(x + 7, y + 2, 7, stroke=0, fill=1)
            c.setFillColor(black)
            c.setFont("Helvetica-Bold", 5.5)
            c.drawCentredString(x + 7, y, person[0])
            c.setFillColor(INK)
            c.setFont("Helvetica-Bold", 5.8)
            c.drawString(x + 18, y + 7, person.upper())
            draw_wrapped(c, answer, x + 18, y - 4, col_w - 18, "Times-Roman", 8.4, 10, max_lines=4)
        if q_index < 4:
            c.setStrokeColor(Color(0, 0, 0, alpha=0.16))
            c.line(MARGIN, top - section_h + 11, W - MARGIN, top - section_h + 11)

    c.setFillColor(MUTED)
    c.setFont("Helvetica", 6.5)
    c.drawString(MARGIN, 24, "NEWSLETTER ANSWERS STAY EDITABLE UNTIL THE MONTHLY EDITION IS CREATED.")
    c.drawRightString(W - MARGIN, 24, "MIH  /  1 OF 2")
    c.showPage()


def two_page_photos(c):
    fill_page(c)
    header(c, "Photos and highlights", 2)
    accent_label(c, "The photo desk", MARGIN, H - 74, 90)
    c.setFillColor(INK)
    c.setFont("Times-Bold", 26)
    c.drawString(MARGIN + 104, H - 71, "Eight moments worth keeping")

    cells = contact_sheet_cells()
    captions = SELF_CAPTIONS + FOOD_CAPTIONS
    authors = PEOPLE + PEOPLE
    gap = 7
    card_w = (W - 2 * MARGIN - 3 * gap) / 4
    image_h = 102
    card_h = 125
    grid_top = H - 100
    for i, image in enumerate(cells):
        col, row = i % 4, i // 4
        x = MARGIN + col * (card_w + gap)
        y = grid_top - (row + 1) * card_h - row * gap
        c.setFillColor(white)
        c.rect(x, y, card_w, card_h, stroke=0, fill=1)
        c.setStrokeColor(INK)
        c.setLineWidth(0.8)
        c.rect(x, y, card_w, card_h, stroke=1, fill=0)
        c.drawImage(ImageReader(image), x + 4, y + 19, card_w - 8, image_h, preserveAspectRatio=True, anchor="c", mask="auto")
        c.setFillColor(INK)
        c.setFont("Times-Bold", 6.5)
        caption = captions[i]
        if stringWidth(caption, "Times-Bold", 6.5) > card_w - 25:
            caption = caption[:20] + "..."
        c.drawString(x + 4, y + 7, caption)
        c.setFont("Helvetica-Bold", 5)
        c.setFillColor(MUTED)
        c.drawRightString(x + card_w - 4, y + 7, authors[i].upper())

    lower_top = 420
    panel_h = 145
    panel_gap = 10
    panel_w = (W - 2 * MARGIN - panel_gap) / 2
    c.setFillColor(white)
    c.rect(MARGIN, lower_top - panel_h, panel_w, panel_h, stroke=0, fill=1)
    c.setStrokeColor(INK)
    c.setLineWidth(1.2)
    c.rect(MARGIN, lower_top - panel_h, panel_w, panel_h, stroke=1, fill=0)
    accent_label(c, "Monthly winners", MARGIN + 14, lower_top - 23, 94)
    c.setFillColor(INK)
    c.setFont("Helvetica-Bold", 6)
    c.drawString(MARGIN + 14, lower_top - 58, "MOST QUESTIONS ANSWERED")
    c.setFont("Times-Bold", 23)
    c.drawString(MARGIN + 14, lower_top - 84, "Maya")
    c.setFont("Helvetica-Bold", 6)
    c.drawString(MARGIN + 14, lower_top - 112, "POINTS LEADER")
    c.setFont("Times-Bold", 23)
    c.drawString(MARGIN + 14, lower_top - 138, "You")

    map_x = MARGIN + panel_w + panel_gap
    c.setFillColor(ACCENT)
    c.rect(map_x, lower_top - panel_h, panel_w, panel_h, stroke=0, fill=1)
    c.setFillColor(black)
    c.setFont("Helvetica-Bold", 6)
    c.drawString(map_x + 14, lower_top - 23, "THE MONTH ON THE MAP")
    c.setFont("Times-Bold", 22)
    c.drawString(map_x + 14, lower_top - 52, "3 cities")
    cities = [("Oakland, CA", "7"), ("Seattle, WA", "5"), ("Brooklyn, NY", "4")]
    y = lower_top - 84
    for city, count in cities:
        c.circle(map_x + 18, y + 2, 3.5, stroke=0, fill=1)
        c.setFont("Times-Bold", 9.5)
        c.drawString(map_x + 29, y, city)
        c.setFont("Helvetica-Bold", 6)
        c.drawRightString(map_x + panel_w - 14, y, count)
        y -= 26

    c.setFillColor(INK)
    c.setFont("Times-Bold", 21)
    c.drawString(MARGIN, 238, "A month looks different through everyone's eyes.")
    c.setLineWidth(3)
    c.line(MARGIN, 218, W - MARGIN, 218)
    c.setFont("Times-Roman", 12)
    c.setFillColor(MUTED)
    c.drawString(MARGIN, 190, "Small rituals. Honest answers. Photos we almost forgot to take.")

    c.setFillColor(ACCENT)
    c.rect(MARGIN, 77, W - 2 * MARGIN, 88, stroke=0, fill=1)
    c.setFillColor(black)
    c.setFont("Helvetica-Bold", 7)
    c.drawString(MARGIN + 20, 141, "END OF THE SEPTEMBER EDITION")
    c.setFont("Times-Bold", 25)
    c.drawString(MARGIN + 20, 111, "See you next month.")
    c.setFont("Times-Roman", 10)
    c.drawString(MARGIN + 250, 112, "Keep answering. Keep noticing. Keep the good stories close.")
    c.setFillColor(MUTED)
    c.setFont("Helvetica", 6.5)
    c.drawString(MARGIN, 24, "DEMO CONTENT - PREVIEW OF BLURB PREMIUM NEWSLETTER EXPORT")
    c.showPage()


def build():
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    c = canvas.Canvas(str(OUTPUT), pagesize=letter, pageCompression=1)
    c.setTitle("Blurb Demo Newsletter - September 2026")
    c.setAuthor("Blurb")
    two_page_words(c)
    two_page_photos(c)
    c.save()
    print(OUTPUT)


if __name__ == "__main__":
    build()
