"""A statement made by a second, unrelated PDF library (fpdf2): a real table with bordered
cells, a text wrap inside a cell (multi_cell), an embedded TrueType font as a CID font with
a ToUnicode map, vertically-top-aligned cells. Used only to cross-check the reader."""
import json
import sys
from pathlib import Path

sys.argv = [sys.argv[0], "out", sys.argv[1]]
src = (Path(__file__).parent / "gen.py").read_text().replace("\nmain()\n", "\n")
ns = {"__name__": "g"}
exec(compile(src, "gen.py", "exec"), ns)
make_rows, rupees, encrypt, truth = (ns[k] for k in ["make_rows", "rupees", "encrypt", "truth"])
from fpdf import FPDF
from fpdf.fonts import FontFace

OUT = Path("out")
rows = make_rows(11, 24, opening=60_000_000, style="sbi"); assert all(r["balance"] > 0 for r in rows)
pdf = FPDF(format="A4")
pdf.add_font("Anek", "", sys.argv[2])
pdf.set_font("Anek", size=7.5)
pdf.add_page()
pdf.set_font("Anek", size=11)
pdf.cell(text="Example Bank - Account Statement", new_x="LMARGIN", new_y="NEXT")
pdf.set_font("Anek", size=7.5)
pdf.cell(text="Account Number : 37791533954   IFSC : EXMP0000123", new_x="LMARGIN", new_y="NEXT")
pdf.ln(4)
with pdf.table(col_widths=(18, 62, 28, 22, 22, 28), text_align=("LEFT", "LEFT", "LEFT", "RIGHT", "RIGHT", "RIGHT"), line_height=4, headings_style=FontFace(emphasis=None)) as table:
    head = table.row()
    for h in ["Date", "Description", "Ref No./Cheque No.", "Debit", "Credit", "Balance"]:
        head.cell(h)
    for r in rows:
        row = table.row()
        row.cell(r["date"].strftime("%d/%m/%Y"))
        row.cell(r["narration"])
        row.cell(r["ref"])
        row.cell(rupees(r["debit"]) if r["debit"] else "")
        row.cell(rupees(r["credit"]) if r["credit"] else "")
        row.cell(rupees(r["balance"]))
pdf.output(str(OUT / "fpdf_plain.pdf"))
encrypt(OUT / "fpdf_plain.pdf", OUT / "fpdf_aes256.pdf", "aes256")
t = truth(rows)
json.dump(t, open(OUT / "fpdf_truth.json", "w"), indent=1)
print("fpdf ok", len(rows))
