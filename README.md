# QIF to Monarch Converter

This project provides scripts to convert QIF (Quicken Interchange Format) files into Monarch Money-compatible CSV files. It supports both multi-account and single-account CSV formats, making it easy to import your financial data into Monarch Money.

## Features
- Batch converts all `.QIF` and `.qif` files in the current directory.
- Supports both Python and PowerShell scripts.
- Handles both multi-account and single-account CSV formats.
- Normalizes dates and amounts for Monarch compatibility.
- Adds an import tag to each transaction for easy grouping.

## Usage

### Python Script
1. Place your `.QIF` files in the same directory as `qif_to_monarch_batch.py`.
2. Open a terminal in that directory.
3. Run for multi-account CSV (default):
   ```sh
   python qif_to_monarch_batch.py
   ```
4. Run for single-account CSV (for Monarch's single-account importer):
   ```sh
   python qif_to_monarch_batch.py --single-account
   ```

### PowerShell Script
1. Place your `.QIF` files in the same directory as `qif_to_monarch_batch.ps1`.
2. Open a PowerShell terminal in that directory.
3. Run for multi-account CSV (default):
   ```powershell
   .\qif_to_monarch_batch.ps1
   ```
4. Run for single-account CSV:
   ```powershell
   .\qif_to_monarch_batch.ps1 -SingleAccount
   ```

## Output
- For each QIF file, a `.monarch.csv` file will be created in the same directory, ready for import into Monarch Money.
- The CSV will include an `imported on {date}` tag for easy grouping in Monarch.

## Requirements
- Python 3 (for the Python script)
- PowerShell 5+ (for the PowerShell script)

## Notes
- The single-account mode is required for Monarch's single-account CSV importer. Use the appropriate flag as shown above.
- All processing is local; no data is sent externally.
