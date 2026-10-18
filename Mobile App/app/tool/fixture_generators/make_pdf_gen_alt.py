"""A deliberately awkward third layout, to find what the reader assumes.

Particulars header centred over a left-aligned body, word-wrapped (not mid-token)
descriptions drawn one word at a time, a heading stacked over two lines, dates as
01-Aug-2026, balances as "73,235.53 Cr", no repeated heading on later pages, a
footer that starts with a date, rupee amounts with a leading symbol-free format,
and an opening-balance line with no date.
"""
import json
import sys
import textwrap
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import importlib.util
spec = importlib.util.spec_from_file_location("g", str(Path(__file__).parent / "gen.py"))
src = (Path(__file__).parent / "gen.py").read_text().replace("\nmain()\n", "\n")
src = src.replace("OUT = Path(sys.argv[1])", "OUT = Path(sys.argv[1])").replace("ANEK = sys.argv[2]", "ANEK = sys.argv[2]")
ns = {"__name__": "g"}
exec(compile(src, "gen.py", "exec"), ns)
make_rows, rupees, encrypt, truth, W, H, A4 = (ns[k] for k in ["make_rows", "rupees", "encrypt", "truth", "W", "H", "A4"])
from reportlab.pdfgen import canvas
from reportlab.pdfbase.pdfmetrics import stringWidth

OUT = Path(sys.argv[1])
rows = make_rows(7, 30, style="hdfc")
# word-wrap descriptions: reuse the generator's own rows, wrap at word boundaries
c = canvas.Canvas(str(OUT / "alt_plain.pdf"), pagesize=A4)
FONT, SIZE, LEAD = "Helvetica", 8, 10
X = {"date": 28, "part": 100, "chq": 330, "debit": 455, "credit": 515, "balance": 575}


def word_by_word(x, y, text):
    for w in text.split(" "):
        c.drawString(x, y, w)
        x += stringWidth(w + " ", FONT, SIZE)


def page_top(pno, first):
    y = H - 40
    c.setFont("Helvetica-Bold", 11)
    c.drawString(28, y, "Example Co-operative Bank" if first else "Statement of Account (contd.)")
    y -= 20
    c.setFont(FONT, SIZE)
    if first:
        c.drawString(28, y, "A/c No: 000012345678   Customer: TEST USER")
        y -= 24
    return y


y = page_top(1, True)
# two-line heading
c.setFont("Helvetica-Bold", SIZE)
c.drawString(X["date"], y, "Tran")
c.drawString(X["date"], y - 10, "Date")
c.drawCentredString(X["part"] + 110, y - 10, "Particulars")
c.drawString(X["chq"], y, "Chq")
c.drawString(X["chq"], y - 10, "No.")
c.drawRightString(X["debit"], y, "Withdrawal")
c.drawRightString(X["debit"], y - 10, "(Dr)")
c.drawRightString(X["credit"], y, "Deposit")
c.drawRightString(X["credit"], y - 10, "(Cr)")
c.drawRightString(X["balance"], y - 10, "Balance")
y -= 26
c.setFont(FONT, SIZE)
c.drawString(X["part"], y, "OPENING BALANCE")
c.drawRightString(X["balance"], y, f"{rupees(rows[0]['balance'] - rows[0]['credit'] + rows[0]['debit'])} Cr")
y -= LEAD + 4
per_page = 17
pno = 1
for i, r in enumerate(rows):
    if i and i % per_page == 0:
        c.setFont(FONT, 7)
        c.drawString(28, 24, "17-OCT-2026 09:30 Page %d of 2" % pno)
        c.showPage()
        pno += 1
        y = page_top(pno, False)
        y -= 6
    c.setFont(FONT, SIZE)
    lines = textwrap.wrap(r["narration"].replace("-", "- ").replace("  ", " "), 38) or [""]
    d = r["date"]
    c.drawString(X["date"], y, f"{d.day:02d}-{d.strftime('%b-%Y')}")
    if r["ref"]:
        c.drawCentredString(X["chq"] + 30, y, r["ref"])
    if r["debit"]:
        c.drawRightString(X["debit"], y, rupees(r["debit"]))
    if r["credit"]:
        c.drawRightString(X["credit"], y, rupees(r["credit"]))
    c.drawRightString(X["balance"], y, f"{rupees(r['balance'])} Cr")
    for k, piece in enumerate(lines):
        word_by_word(X["part"], y - k * LEAD, piece)
    y -= LEAD * len(lines) + 4
c.setFont(FONT, 7)
c.drawString(28, 24, "17-OCT-2026 09:30 Page %d of 2" % pno)
c.showPage()
c.save()

encrypt(OUT / "alt_plain.pdf", OUT / "alt_aes256.pdf", "aes256")
truth_rows = truth(rows)
# the descriptions are re-wrapped at spaces, so the truth is the text with "- " collapsed back is not possible:
# record the wrapped-and-joined form the way a person reads it
for t in truth_rows:
    t["narration"] = " ".join(textwrap.wrap(t["narration"].replace("-", "- ").replace("  ", " "), 38))
(OUT / "alt_truth.json").write_text(json.dumps(truth_rows, indent=1))
print("alt ok", len(rows))
