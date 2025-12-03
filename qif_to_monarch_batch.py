#!/usr/bin/env python3
"""
qif_to_monarch_batch.py
Batch-convert all QIF files in this folder to Monarch Money–compatible CSVs.
- Ensures exact Monarch header order, even if fields are blank.
- Keeps signed Amounts (negative = expense, positive = credit).
- Sets both 'Merchant' and 'Original Statement' to the QIF Payee (P) value by default.
- Optionally derives 'Account' from the filename (can be edited).

Usage:
  Place this script in the same directory as your .QIF exports and run:
      python qif_to_monarch_batch.py
"""

from pathlib import Path
import csv
from datetime import datetime
import argparse

# Exact headers/order from Monarch's sample template
MONARCH_HEADERS = [
    "Date",
    "Merchant Name",
    "Data Provider Description",
    "Amount",
    "Category",
    "Account",
    "Tags",
    "Notes",
]

# Single-account headers/order for Monarch's single-account importer
MONARCH_SINGLE_HEADERS = [
    "Date",
    "Merchant",
    "Category",
    "Account",
    "Original Statement",
    "Notes",
    "Amount",
    "Tags",
]

def parse_qif_to_rows(qif_file: Path, account_name: str | None = None, import_tag: str | None = None, single_account: bool = False) -> list[dict]:
    """
    Parse a QIF file and return a list of row dicts matching MONARCH_HEADERS.
    """
    rows = []
    current = {h: "" for h in MONARCH_HEADERS}
    # pre-fill account if provided
    if account_name:
        current["Account"] = account_name

    def flush():
        # Only flush if we have at least a date and a valid amount
        amt_raw = current.get("Amount")
        amt = normalize_amount(amt_raw)
        if current.get("Date") and amt not in ("", None):
            row = {h: current.get(h, "") for h in MONARCH_HEADERS}
            # Normalize date -> YYYY-MM-DD when possible
            row["Date"] = normalize_date(row["Date"])
            # Normalize Amount to plain numeric string (e.g. -12.34)
            row["Amount"] = amt
            # Derive Merchant fallback if empty
            if not row.get("Merchant Name") and row.get("Data Provider Description"):
                row["Merchant Name"] = row["Data Provider Description"]
            # Add import tag to Tags
            if import_tag:
                if row["Tags"]:
                    row["Tags"] += f", {import_tag}"
                else:
                    row["Tags"] = import_tag
            # For single-account mode, remap keys to single headers
            if single_account:
                row["Merchant"] = row.pop("Merchant Name")
                row["Original Statement"] = row.pop("Data Provider Description")
            rows.append(row)

    with qif_file.open("r", encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line:
                continue
            if line.startswith("!"):  # e.g., !Type:Bank
                continue
            if line == "^":  # end of transaction
                flush()
                current = {h: "" for h in MONARCH_HEADERS}
                if account_name:
                    current["Account"] = account_name
                continue

            code, value = line[:1], line[1:].strip()

            if code == "D":      # Date
                current["Date"] = value
            elif code == "T":    # Amount (signed)
                current["Amount"] = value
            elif code == "P":    # Payee -> Merchant Name
                current["Merchant Name"] = value
            elif code == "M":    # Memo -> Data Provider Description
                current["Data Provider Description"] = value
            elif code == "L":    # Category
                current["Category"] = value
            elif code == "A":    # Account (per-transaction)
                if not single_account:
                    current["Account"] = value
            elif code == "G":    # Tags (custom code for this workflow)
                current["Tags"] = value
            elif code == "N":    # Check/Ref -> Notes (append)
                if current["Notes"]:
                    current["Notes"] += f" (Ref {value})"
                else:
                    current["Notes"] = f"Ref {value}"
            else:
                # Other QIF fields can be added here as needed
                pass

        # Some QIFs omit the trailing '^' on the last txn
        flush()

    return rows

def normalize_amount(s: str) -> str:
    """
    Clean up QIF amount strings and return a plain numeric string suitable for CSV.
    Returns empty string if the input is blank or can't be parsed.
    Examples: "$1,234.56" -> "1234.56", "(12.34)" -> "-12.34"
    """
    if not s:
        return ""
    s = str(s).strip()
    if s == "":
        return ""
    # Parentheses denote negative amounts in some exports
    neg = False
    if s.startswith("(") and s.endswith(")"):
        neg = True
        s = s[1:-1]
    # Remove common currency characters and thousands separators
    for ch in ("$", "\u00A0", ","):
        s = s.replace(ch, "")
    s = s.replace("+", "")
    s = s.strip()
    if s == "":
        return ""
    try:
        v = float(s)
    except Exception:
        return ""
    if neg:
        v = -abs(v)
    return f"{v:.2f}" if (v != int(v)) else f"{int(v)}"


def normalize_date(s: str) -> str:
    """
    Try several common QIF date formats; return ISO YYYY-MM-DD if possible.
    """
    if not s:
        return s
    for fmt in ("%Y-%m-%d", "%m/%d/%Y", "%m/%d/%y", "%m-%d-%Y", "%m-%d-%y"):
        try:
            return datetime.strptime(s, fmt).strftime("%Y-%m-%d")
        except Exception:
            continue
    # If all parsing fails, return original
    return s

def main():
    parser = argparse.ArgumentParser(description="Batch-convert QIF files to Monarch Money CSVs.")
    parser.add_argument("--single-account", action="store_true", help="Use single-account CSV format and force all transactions to the guessed account name.")
    args = parser.parse_args()

    headers = MONARCH_SINGLE_HEADERS if args.single_account else MONARCH_HEADERS

    here = Path(__file__).parent
    qif_files = list(here.glob("*.QIF")) + list(here.glob("*.qif"))
    if not qif_files:
        print("⚠️  No QIF files found in this directory.")
        return

    # Deduplicate matches (case-insensitive filesystems can return same file twice)
    seen = set()
    unique_qif_files = []
    for p in qif_files:
        try:
            key = p.resolve()
        except Exception:
            key = p
        if key in seen:
            continue
        seen.add(key)
        unique_qif_files.append(p)

    # Generate import tag with current date
    date_str = datetime.now().strftime("%d%m%Y")
    import_tag = f"imported on {date_str}"

    for qif in unique_qif_files:
        # Guess account name from filename (edit to taste or set to "")
        account_guess = qif.stem  # e.g., "PenFed_Checking_2025-07"
        rows = parse_qif_to_rows(qif, account_name=account_guess, import_tag=import_tag, single_account=args.single_account)

        out_path = qif.with_suffix(".monarch.csv")
        with out_path.open("w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=headers)
            writer.writeheader()
            for r in rows:
                writer.writerow(r)

        print(f"✅ {qif.name} → {out_path.name}  ({len(rows)} transactions)")

if __name__ == "__main__":
    main()
