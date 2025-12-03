<#
.SYNOPSIS
    qif_to_monarch_batch.ps1
    Batch-convert all QIF files in this folder to Monarch Money–compatible CSVs.
    - Ensures exact Monarch header order, even if fields are blank.
    - Keeps signed Amounts (negative = expense, positive = credit).
    - Sets both 'Merchant' and 'Original Statement' to the QIF Payee (P) value by default.
    - Optionally derives 'Account' from the filename (can be edited).

.PARAMETER SingleAccount
    Use single-account CSV format and force all transactions to the guessed account name.

.EXAMPLE
    .\qif_to_monarch_batch.ps1
    .\qif_to_monarch_batch.ps1 -SingleAccount
#>

param(
    [switch]$SingleAccount
)

# Exact headers/order from Monarch's sample template
$MONARCH_HEADERS = @(
    "Date",
    "Merchant Name",
    "Data Provider Description",
    "Amount",
    "Category",
    "Account",
    "Tags",
    "Notes"
)

# Single-account headers/order for Monarch's single-account importer
$MONARCH_SINGLE_HEADERS = @(
    "Date",
    "Merchant",
    "Category",
    "Account",
    "Original Statement",
    "Notes",
    "Amount",
    "Tags"
)

function Normalize-Amount {
    param([string]$s)
    if (-not $s) { return "" }
    $s = $s.Trim()
    if ($s -eq "") { return "" }
    $neg = $false
    if ($s -match '^\((.*)\)$') {
        $neg = $true
        $s = $matches[1]
    }
    $s = $s -replace '[\$,\u00A0,]', '' -replace '\+', ''
    $s = $s.Trim()
    if ($s -eq "") { return "" }
    $v = 0.0
    if ([double]::TryParse($s, [ref]$v)) {
        if ($neg) { $v = -[math]::Abs($v) }
        if ($v -eq [math]::Floor($v)) {
            return [int]$v
        } else {
            return $v.ToString("F2")
        }
    }
    return ""
}

function Normalize-Date {
    param([string]$s)
    if (-not $s) { return $s }
    $formats = @("yyyy-MM-dd", "M/d/yyyy", "M/d/yy", "M-d-yyyy", "M-d-yy")
    foreach ($fmt in $formats) {
        try {
            $dt = [DateTime]::ParseExact($s, $fmt, $null, [System.Globalization.DateTimeStyles]::None)
            return $dt.ToString("yyyy-MM-dd")
        } catch { }
    }
    return $s
}

function Parse-QifToRows {
    param(
        [string]$qifFile,
        [string]$accountName,
        [string]$importTag,
        [bool]$singleAccount
    )
    $rows = @()
    $current = @{}
    foreach ($h in $MONARCH_HEADERS) {
        $current[$h] = ""
    }
    if ($accountName) {
        $current["Account"] = $accountName
    }

    $content = Get-Content -Path $qifFile -Encoding UTF8
    foreach ($raw in $content) {
        $line = $raw.Trim()
        if (-not $line) { continue }
        if ($line.StartsWith("!")) { continue }
        if ($line -eq "^") {
            # flush
            $amtRaw = $current["Amount"]
            $amt = Normalize-Amount $amtRaw
            if ($current["Date"] -and $amt -notin @("", $null)) {
                $row = @{}
                foreach ($h in $MONARCH_HEADERS) {
                    $row[$h] = $current[$h]
                }
                $row["Date"] = Normalize-Date $row["Date"]
                $row["Amount"] = $amt
                if (-not $row["Merchant Name"] -and $row["Data Provider Description"]) {
                    $row["Merchant Name"] = $row["Data Provider Description"]
                }
                if ($importTag) {
                    if ($row["Tags"]) {
                        $row["Tags"] += ", $importTag"
                    } else {
                        $row["Tags"] = $importTag
                    }
                }
                if ($singleAccount) {
                    $row["Merchant"] = $row["Merchant Name"]
                    $row.Remove("Merchant Name")
                    $row["Original Statement"] = $row["Data Provider Description"]
                    $row.Remove("Data Provider Description")
                }
                $rows += [PSCustomObject]$row
            }
            $current = @{}
            foreach ($h in $MONARCH_HEADERS) {
                $current[$h] = ""
            }
            if ($accountName) {
                $current["Account"] = $accountName
            }
            continue
        }

        if ($line.Length -gt 0) {
            $code = $line[0]
            $value = $line.Substring(1).Trim()
        } else {
            continue
        }

        switch ($code) {
            "D" { $current["Date"] = $value }
            "T" { $current["Amount"] = $value }
            "P" { $current["Merchant Name"] = $value }
            "M" { $current["Data Provider Description"] = $value }
            "L" { $current["Category"] = $value }
            "A" { if (-not $singleAccount) { $current["Account"] = $value } }
            "G" { $current["Tags"] = $value }
            "N" {
                if ($current["Notes"]) {
                    $current["Notes"] += " (Ref $value)"
                } else {
                    $current["Notes"] = "Ref $value"
                }
            }
            default { }
        }
    }
    # final flush
    $amtRaw = $current["Amount"]
    $amt = Normalize-Amount $amtRaw
    if ($current["Date"] -and $amt -notin @("", $null)) {
        $row = @{}
        foreach ($h in $MONARCH_HEADERS) {
            $row[$h] = $current[$h]
        }
        $row["Date"] = Normalize-Date $row["Date"]
        $row["Amount"] = $amt
        if (-not $row["Merchant Name"] -and $row["Data Provider Description"]) {
            $row["Merchant Name"] = $row["Data Provider Description"]
        }
        if ($importTag) {
            if ($row["Tags"]) {
                $row["Tags"] += ", $importTag"
            } else {
                $row["Tags"] = $importTag
            }
        }
        if ($singleAccount) {
            $row["Merchant"] = $row["Merchant Name"]
            $row.Remove("Merchant Name")
            $row["Original Statement"] = $row["Data Provider Description"]
            $row.Remove("Data Provider Description")
        }
        $rows += [PSCustomObject]$row
    }
    return $rows
}

$headers = if ($SingleAccount) { $MONARCH_SINGLE_HEADERS } else { $MONARCH_HEADERS }

$here = $PSScriptRoot
$qifFiles = @(Get-ChildItem -Path $here -Filter "*.QIF" -File) + @(Get-ChildItem -Path $here -Filter "*.qif" -File)
if (-not $qifFiles) {
    Write-Host "⚠️  No QIF files found in this directory."
    return
}

# Deduplicate matches (case-insensitive filesystems can return same file twice)
$seen = @{}
$uniqueQifFiles = @()
foreach ($p in $qifFiles) {
    $key = $p.FullName.ToLower()
    if (-not $seen.ContainsKey($key)) {
        $seen[$key] = $true
        $uniqueQifFiles += $p
    }
}

# Generate import tag with current date
$dateStr = Get-Date -Format "ddMMyyyy"
$importTag = "imported on $dateStr"

foreach ($qif in $uniqueQifFiles) {
    $accountGuess = $qif.BaseName
    $rows = Parse-QifToRows -qifFile $qif.FullName -accountName $accountGuess -importTag $importTag -singleAccount $SingleAccount.IsPresent

    $outPath = $qif.FullName -replace '\.QIF$', '.monarch.csv' -replace '\.qif$', '.monarch.csv'
    $rows | Select-Object $headers | Export-Csv -Path $outPath -NoTypeInformation -Encoding UTF8

    Write-Host "✅ $($qif.Name) → $(Split-Path $outPath -Leaf)  ($($rows.Count) transactions)"
}