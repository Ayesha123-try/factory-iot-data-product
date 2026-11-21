# One-command local run on Windows (PowerShell):  .\run_all.ps1
# Creates the virtual environment on first run, then builds everything end to end.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Test-Path ".venv")) {
    Write-Host "Creating virtual environment and installing requirements..."
    python -m venv .venv
    .\.venv\Scripts\python.exe -m pip install --upgrade pip
    .\.venv\Scripts\python.exe -m pip install -r requirements.txt
}

$env:DBT_PROFILES_DIR = $PSScriptRoot
New-Item -ItemType Directory -Force warehouse | Out-Null

Write-Host "`n[1/3] dbt build (seeds, models, tests)"
.\.venv\Scripts\dbt.exe build
if ($LASTEXITCODE -ne 0) { throw "dbt build failed" }

Write-Host "`n[2/3] Export gold KPIs to outputs/"
.\.venv\Scripts\python.exe scripts\export_outputs.py

Write-Host "`n[3/3] Generate dbt docs site"
.\.venv\Scripts\dbt.exe docs generate

Write-Host "`nDone. KPIs are in outputs\. Run '.venv\Scripts\dbt.exe docs serve' for the docs site."
