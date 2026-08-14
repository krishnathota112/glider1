#!/usr/bin/env python3
"""
extract_docs.py - Extract text from the EGO reference PDFs and parameter lists.

Writes plain-text dumps next to a cache dir so the manuals can be grepped
instead of re-parsed each time.

Usage:
    python extract_docs.py --all
    python extract_docs.py --pdf <path.pdf> [--pages 1-20]
    python extract_docs.py --xlsx <path.xlsx>
    python extract_docs.py --grep "PARAMETER" --in <dump.txt>
"""
import os
import sys
import argparse

DOC_ROOT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "126193", "decGlider_20260204_014e", "decGlider_doc")

CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_doccache")

PDFS = {
    "ego_format": os.path.join(
        DOC_ROOT, "EGO_gliders_user_manual",
        "ego_gliders_netcdf_format_manual_V1.15_20250211.pdf"),
    "ego_qc": os.path.join(
        DOC_ROOT, "EGO_gliders_quality_control_manual",
        "ego_gliders_quality_control_manual_V1.5_20250211.pdf"),
    "decoder": os.path.join(
        DOC_ROOT, "decoder_user_manual",
        "groom_gliders_coriolis_matlab_decoder_V2.13_20250211.pdf"),
}

XLSX = {
    "param_list": os.path.join(
        DOC_ROOT, "EGO_gliders_user_manual", "_EGO_specific_lists",
        "glider_specific_parameters_list_20231212.xlsx"),
    "tech_mapping": os.path.join(
        DOC_ROOT, "mapping_of_input_data",
        "mapping of_technical_data_20231212.xlsx"),
    "slocum_mapping": os.path.join(
        DOC_ROOT, "mapping_of_input_data",
        "gl_get_glider_data_slocum_FINAL.xlsx"),
}


def extract_pdf(path, out_path=None, page_range=None):
    """Extract text from a PDF using PyMuPDF, one marked section per page."""
    import fitz

    doc = fitz.open(path)
    n = doc.page_count
    lo, hi = 0, n
    if page_range:
        parts = page_range.split("-")
        lo = int(parts[0]) - 1
        hi = int(parts[1]) if len(parts) > 1 else lo + 1
        lo = max(0, lo)
        hi = min(n, hi)

    chunks = []
    for i in range(lo, hi):
        text = doc.load_page(i).get_text("text")
        chunks.append(f"\n===== PAGE {i+1} / {n} =====\n{text}")
    doc.close()

    full = "".join(chunks)
    if out_path:
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        with open(out_path, "w", encoding="utf-8") as fh:
            fh.write(full)
        print(f"  {os.path.basename(path)}: {n} pages -> {out_path}")
    return full


def extract_xlsx(path, out_path=None):
    """Dump every sheet of a workbook to tab-separated text."""
    import pandas as pd

    sheets = pd.read_excel(path, sheet_name=None, header=None)
    parts = []
    for name, df in sheets.items():
        parts.append(f"\n===== SHEET: {name}  ({df.shape[0]}x{df.shape[1]}) =====")
        parts.append(df.to_csv(sep="\t", index=False, header=False))
    full = "\n".join(parts)

    if out_path:
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        with open(out_path, "w", encoding="utf-8") as fh:
            fh.write(full)
        print(f"  {os.path.basename(path)}: {len(sheets)} sheets -> {out_path}")
    return full


def do_all():
    os.makedirs(CACHE, exist_ok=True)
    print("Extracting PDFs...")
    for key, path in PDFS.items():
        if not os.path.exists(path):
            print(f"  MISSING: {path}")
            continue
        extract_pdf(path, os.path.join(CACHE, f"{key}.txt"))

    print("\nExtracting spreadsheets...")
    for key, path in XLSX.items():
        if not os.path.exists(path):
            print(f"  MISSING: {path}")
            continue
        try:
            extract_xlsx(path, os.path.join(CACHE, f"{key}.txt"))
        except Exception as e:
            print(f"  ERROR {os.path.basename(path)}: {e}")

    print(f"\nDumps in: {CACHE}")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--all", action="store_true")
    p.add_argument("--pdf")
    p.add_argument("--xlsx")
    p.add_argument("--pages")
    p.add_argument("--out")
    args = p.parse_args()

    if args.all:
        do_all()
    elif args.pdf:
        txt = extract_pdf(args.pdf, args.out, args.pages)
        if not args.out:
            print(txt)
    elif args.xlsx:
        txt = extract_xlsx(args.xlsx, args.out)
        if not args.out:
            print(txt)
    else:
        p.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
