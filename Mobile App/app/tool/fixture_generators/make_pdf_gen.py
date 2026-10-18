"""Synthetic bank-statement PDFs for the Paisa PDF import tests.

Everything here is invented: fake bank, fake names, fake account number. Balances
reconcile. Each PDF is produced with reportlab and then encrypted with pikepdf
(qpdf), an implementation that has nothing to do with the Dart reader.

Layouts imitate what is *believed* about two banks' PDF exports (HDFC-like and
SBI-like); no real statement was available to copy from.
"""
import json
import random
import sys
from datetime import date, timedelta
from pathlib import Path

import pikepdf
from reportlab.lib.pagesizes import A4
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas

OUT = Path(sys.argv[1])
OUT.mkdir(parents=True, exist_ok=True)
PASSWORD = "test-password"
ANEK = sys.argv[2]
pdfmetrics.registerFont(TTFont("Anek", ANEK))

W, H = A4
FAKE_ACCOUNT = "50100123456789"

UPI_NAMES = ["ROYAL CITY RESTAURAN", "FRESH MART KOCHI", "SAAVN MEDIA", "METRO CAB SERVICES", "GREEN LEAF PHARMACY", "BOAZ M R", "SHOBHA M", "CITY ELECTRICALS"]
BANKS = ["CNRB0003909", "HDFC0000123", "FDRL0001234", "SBIN0070190"]


def rupees(paise):
    """1234567 paise -> '12,345.67' with Indian grouping."""
    whole, frac = divmod(abs(paise), 100)
    s = str(whole)
    if len(s) > 3:
        head, tail = s[:-3], s[-3:]
        parts = []
        while len(head) > 2:
            parts.insert(0, head[-2:])
            head = head[:-2]
        if head:
            parts.insert(0, head)
        s = ",".join(parts) + "," + tail
    return f"{s}.{frac:02d}"


def make_rows(seed, count, start=date(2026, 8, 1), opening=7_423_453, style="hdfc"):
    rng = random.Random(seed)
    rows, balance, day = [], opening, start
    for i in range(count):
        day += timedelta(days=rng.choice([0, 0, 1, 1, 2]))
        kind = rng.choice(["upi_dr", "upi_dr", "upi_dr", "upi_cr", "neft_cr", "atm", "charge", "chq"])
        ref = "".join(rng.choice("0123456789") for _ in range(12))
        name = rng.choice(UPI_NAMES)
        vpa = name.split()[0].lower() + str(rng.randint(10, 99)) + "@" + rng.choice(["okaxis", "oksbi", "paytm"])
        bank = rng.choice(BANKS)
        if kind == "upi_dr":
            text = f"UPI-{name}-{vpa}-{bank}-{ref}-PAID VIA UPI" if style == "hdfc" else f"WDL TFR UPI/DR/{ref}/{name}/{bank[:4]}/{vpa.split('@')[0]}/Paid"
            debit, credit = rng.choice([8900, 12000, 25000, 45050, 99900, 150000, 1234567, 15000000]), 0
        elif kind == "upi_cr":
            text = f"UPI-{name}-{vpa}-{bank}-{ref}-UPI" if style == "hdfc" else f"DEP TFR UPI/CR/{ref}/{name}/{bank[:4]}/{vpa.split('@')[0]}/UPI"
            debit, credit = 0, rng.choice([500000, 250000, 1000000, 12345600])
        elif kind == "neft_cr":
            text = f"NEFT CR-HSBC0400002-UNTOLD STUDIOS PRIVATE LIMITED-JADHEER TP-HSBCN{rng.randint(10000, 99999)}"
            debit, credit = 0, rng.choice([8500000, 12000000])
        elif kind == "atm":
            text = f"ATM WDL {bank[:4]} KOCHI {ref[:6]}" if style == "hdfc" else f"ATM WDL TFR {ref[:8]} AT KOCHI"
            debit, credit = rng.choice([200000, 1000000]), 0
        elif kind == "charge":
            text = "SMS ALERT CHARGES"
            debit, credit = rng.choice([1770, 2360]), 0
        else:
            text = f"CHQ DEP {rng.randint(100000, 999999)}"
            debit, credit = 0, rng.choice([300000, 4500000])
        balance += credit - debit
        rows.append({"date": day, "narration": text, "ref": ref if kind not in ("charge",) else "", "debit": debit, "credit": credit, "balance": balance})
    return rows


def wrap(text, width):
    """Hard-wrap at a fixed character count, mid-token like a bank's fixed-width field."""
    return [text[i:i + width] for i in range(0, len(text), width)] or [""]


def fmt_date(d, style):
    if style == "dmy2":
        return d.strftime("%d/%m/%y")
    if style == "mon":
        return f"{d.day} {d.strftime('%b %Y')}"
    return d.strftime("%d/%m/%Y")


class Layout:
    """Columns: (key, header text, x, align, header align)."""

    def __init__(self, name, cols, wrap_at, date_style, font, size, leading):
        self.name, self.cols, self.wrap_at = name, cols, wrap_at
        self.date_style, self.font, self.size, self.leading = date_style, font, size, leading


HDFC = Layout(
    "hdfc",
    [("date", "Date", 30, "l", "l"), ("narration", "Narration", 75, "l", "l"), ("ref", "Chq./Ref.No.", 255, "l", "l"),
     ("vdate", "Value Dt", 325, "l", "l"), ("debit", "Withdrawal Amt.", 430, "r", "r"), ("credit", "Deposit Amt.", 497, "r", "r"),
     ("balance", "Closing Balance", 565, "r", "r")],
    36, "dmy2", "Helvetica", 7.5, 9.5)
# Header text centred over the column while the body is left or right aligned.
SBI = Layout(
    "sbi",
    [("date", "Txn Date", 30, "l", "c"), ("vdate", "Value Date", 85, "l", "c"), ("narration", "Description", 140, "l", "c"),
     ("ref", "Ref No./Cheque No.", 320, "l", "c"), ("debit", "Debit", 440, "r", "c"), ("credit", "Credit", 500, "r", "c"),
     ("balance", "Balance", 565, "r", "c")],
    34, "mon", "Helvetica", 7.5, 9.5)

COL_WIDTH = {"date": 50, "vdate": 50, "narration": 175, "ref": 65, "debit": 70, "credit": 60, "balance": 70}


def draw(c, layout, x, text, align, y, col_w=None, font=None, size=None):
    c.setFont(font or layout.font, size or layout.size)
    if align == "l":
        c.drawString(x, y, text)
    elif align == "r":
        c.drawRightString(x, y, text)
    else:
        w = col_w
        c.drawCentredString(x + w / 2, y, text)


def render(path, layout, rows, rows_per_page, repeat_header, title_font=None, font=None, bank="Example Bank Ltd", scanned_page=None):
    c = canvas.Canvas(str(path), pagesize=A4, pageCompression=1)
    font = font or layout.font
    layout.font = font
    pages = [rows[i:i + rows_per_page] for i in range(0, len(rows), rows_per_page)]
    for pno, chunk in enumerate(pages, start=1):
        y = H - 40
        c.setFont(title_font or font, 11)
        c.drawString(30, y, bank + " - Statement of Account")
        y -= 14
        c.setFont(font, 7.5)
        if pno == 1:
            for line in ["Mr. TEST USER", "FLAT 4B, EXAMPLE APARTMENTS", "KOCHI 682001 KERALA INDIA",
                         f"Account No : {FAKE_ACCOUNT}", "Account Branch : KOCHI MAIN", "IFSC Code : EXMP0000123",
                         f"Statement From : {fmt_date(rows[0]['date'], 'dmy4')} To : {fmt_date(rows[-1]['date'], 'dmy4')}",
                         "Date of Statement : 01/09/2026"]:
                c.drawString(30, y, line)
                y -= 10
            y -= 14
        else:
            c.drawString(30, y, f"Account No : {FAKE_ACCOUNT}   (continued)")
            y -= 24
        if pno == 1 or repeat_header:
            c.line(30, y + 9, W - 30, y + 9)
            for key, head, x, align, halign in layout.cols:
                if halign == "c":
                    draw(c, layout, x if align == "l" else x - COL_WIDTH[key], head, "c", y, COL_WIDTH[key], font, 7.5)
                else:
                    draw(c, layout, x, head, halign, y, None, font, 7.5)
            c.line(30, y - 4, W - 30, y - 4)
            y -= 16
        for row in chunk:
            lines = wrap(row["narration"], layout.wrap_at)
            cells = {
                "date": fmt_date(row["date"], layout.date_style),
                "vdate": fmt_date(row["date"], layout.date_style),
                "ref": row["ref"],
                "debit": rupees(row["debit"]) if row["debit"] else "",
                "credit": rupees(row["credit"]) if row["credit"] else "",
                "balance": rupees(row["balance"]),
            }
            for key, _, x, align, _ in layout.cols:
                if key == "narration":
                    continue
                if cells[key]:
                    draw(c, layout, x, cells[key], align, y, None, font, layout.size)
            for i, piece in enumerate(lines):
                draw(c, layout, dict((k, x) for k, _, x, _, _ in layout.cols)["narration"], piece, "l", y - i * layout.leading, None, font, layout.size)
            y -= layout.leading * len(lines) + 3
        if pno == len(pages):
            y -= 14
            c.setFont(font, 7.5)
            c.drawString(30, y, "STATEMENT SUMMARY :-")
            y -= 10
            c.drawString(30, y, "Opening Balance   Dr Count   Cr Count   Debits   Credits   Closing Bal")
            y -= 10
            dr = sum(r["debit"] for r in rows)
            cr = sum(r["credit"] for r in rows)
            first = rows[0]
            opening = first["balance"] - first["credit"] + first["debit"]
            c.drawString(30, y, f"{rupees(opening)}   {sum(1 for r in rows if r['debit'])}   {sum(1 for r in rows if r['credit'])}   {rupees(dr)}   {rupees(cr)}   {rupees(rows[-1]['balance'])}")
            y -= 16
            c.drawString(30, y, "Generated On: 01-SEP-2026 10:15:00   Generated By: SYSTEM   Requesting Branch Code: 0123")
            y -= 10
            c.drawString(30, y, "This is a computer generated statement and does not require signature.")
        c.setFont(font, 7)
        c.drawCentredString(W / 2, 28, f"Page No .: {pno}")
        c.drawCentredString(W / 2, 18, "Example Bank Limited, Registered Office: 1 Example Road, Mumbai 400001")
        c.showPage()
    if scanned_page:
        c.drawImage(scanned_page, 0, 0, W, H)
        c.showPage()
    c.save()


def encrypt(src, dst, scheme):
    with pikepdf.open(src) as pdf:
        if scheme == "rc4128":
            enc = pikepdf.Encryption(user=PASSWORD, owner=PASSWORD + "-owner", R=3, aes=False, metadata=False)
        elif scheme == "aes128":
            enc = pikepdf.Encryption(user=PASSWORD, owner=PASSWORD + "-owner", R=4, aes=True)
        elif scheme == "aes256":
            enc = pikepdf.Encryption(user=PASSWORD, owner=PASSWORD + "-owner", R=6)
        else:
            raise ValueError(scheme)
        pdf.save(dst, encryption=enc, static_id=True)


def truth(rows):
    return [{"date": r["date"].strftime("%d/%m/%Y"), "narration": r["narration"], "ref": r["ref"],
             "debit": rupees(r["debit"]) if r["debit"] else "", "credit": rupees(r["credit"]) if r["credit"] else "",
             "balance": rupees(r["balance"])} for r in rows]


def main():
    tmp = OUT / "plain"
    tmp.mkdir(exist_ok=True)
    expected = {}

    hd = make_rows(1, 14, style="hdfc")
    render(tmp / "hdfc.pdf", HDFC, hd, 40, True)
    expected["statement_hdfc_plain.pdf"] = truth(hd)
    (OUT / "statement_hdfc_plain.pdf").write_bytes((tmp / "hdfc.pdf").read_bytes())
    encrypt(tmp / "hdfc.pdf", OUT / "statement_hdfc_aes256.pdf", "aes256")
    expected["statement_hdfc_aes256.pdf"] = expected["statement_hdfc_plain.pdf"]

    sb = make_rows(2, 12, start=date(2026, 9, 1), opening=7_423_453, style="sbi")
    render(tmp / "sbi.pdf", SBI, sb, 40, False, bank="Example State Bank")
    encrypt(tmp / "sbi.pdf", OUT / "statement_sbi_rc4.pdf", "rc4128")
    expected["statement_sbi_rc4.pdf"] = truth(sb)

    # Three pages, header row repeated on each, an embedded TrueType font (Anek Latin),
    # AES-128. Narrow page capacity forces rows onto later pages.
    mp = make_rows(3, 55, style="hdfc")
    render(tmp / "multi.pdf", HDFC, mp, 20, True, font="Anek")
    encrypt(tmp / "multi.pdf", OUT / "statement_multipage_aes128.pdf", "aes128")
    expected["statement_multipage_aes128.pdf"] = truth(mp)

    # Image-only: the text is drawn into a bitmap, so the page has no text layer.
    from PIL import Image, ImageDraw
    img = Image.new("RGB", (595, 842), "white")
    d = ImageDraw.Draw(img)
    d.text((30, 30), "Example Bank - Statement of Account (scanned copy)", fill="black")
    for i in range(20):
        d.text((30, 80 + i * 14), f"0{i+1}/08/26  UPI-SOMEONE-PAID  1,000.00  72,423.53", fill="black")
    img.save(tmp / "scan.png")
    c = canvas.Canvas(str(tmp / "scan.pdf"), pagesize=A4)
    c.drawImage(str(tmp / "scan.png"), 0, 0, W, H)
    c.showPage()
    c.save()
    encrypt(tmp / "scan.pdf", OUT / "statement_scanned_rc4.pdf", "rc4128")

    (OUT / "pdf_truth.json").write_text(json.dumps(expected, indent=1))
    print("ok", sorted(p.name for p in OUT.glob("*.pdf")))


main()
