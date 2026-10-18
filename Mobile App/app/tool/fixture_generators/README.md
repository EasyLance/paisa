# Fixture generators

The statement fixtures in `test/fixtures/` are synthetic (fake names and account numbers,
balances that reconcile) and are made by tools other than the code under test, so a test
cannot pass merely because the app agrees with itself.

| Fixtures | Made by | Kept here |
|---|---|---|
| `statement_hdfc_*.pdf`, `statement_sbi_rc4.pdf`, `statement_multipage_aes128.pdf`, `statement_scanned_rc4.pdf`, `pdf_truth.json` | `make_pdf_gen.py` (reportlab, encrypted with qpdf through pikepdf) | yes |
| `statement_alt_aes256.pdf` and the awkward-layout variants | `make_pdf_gen_alt.py` | yes |
| the bordered, centred-text table | `make_pdf_gen_fpdf.py` (fpdf2) | yes |
| `statement.xlsx`, `statement_encrypted_sha1_aes128.xlsx`, `statement_encrypted_sha512_aes256.xlsx` | Python `msoffcrypto-tool` key handling plus a small compound-file writer written for the purpose, because the library's own writer corrupts the package stream and its integrity step fails on SHA-1; the library's *reader* then decrypts the output, which is the independent check | **no** — see `Mobile App/docs/findings.md` F19 for how it was done |

All encrypted fixtures use the test password `test-password`. Run a generator in a
throwaway Python venv (`pip install reportlab pikepdf fpdf2`); they were written against
the versions current on 2026-10-17 and write into a folder you pass or an `out/` folder
next to them (read the top of each file).
