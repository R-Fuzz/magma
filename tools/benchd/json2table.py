#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Validate and fill experiment_data.xlsx
Default filenames:
  --json results_pretty.json
  --excel experiment_data.xlsx
  --out experiment_data.filled.xlsx
Optional: --excel, --fix-mismatches  If added, will also change inconsistent values to JSON values; by default only fills empty values.
"""
import argparse
import json
import re
from pathlib import Path
from typing import Union

import pandas as pd

# -------- JSON Flattening --------

# -------- Project Mapping --------
TARGET_TO_PROJECT = {
    'libpng_read_fuzzer': 'libpng',
    'xml_read_memory_fuzzer': 'libxml2',
    'libxml2_xml_read_memory_fuzzer': 'libxml2',
    'sqlite3_fuzz': 'sqlite3',
    'sndfile_fuzzer': 'libsndfile',
    'lua': 'lua',
    'bignum': 'openssl',
    'asn1': 'openssl',
    'client': 'openssl',
    'server': 'openssl',
    'asn1parse': 'openssl',
    'x509': 'openssl',
    'xmllint': 'libxml2',
    'pdftoppm': 'poppler',
    'pdfimages': 'poppler',
    'pdf_fuzzer': 'poppler',
    'tiffcp': 'libtiff',
    'tiff_read_rgba_fuzzer': 'libtiff',
    'parser': 'php',
    'exif': 'php',
    'json': 'php',
    'unserialize': 'php'
}

# -------- Fuzzer Mapping --------
FUZZER_MAPPING = {
    'PBFuzz': 'pbfuzz',
    'cursor': 'cursor_cli',
    'cursor-tools': 'cursor_pbfuzz_tools'
}

def extract_project_from_target(target: Union[str, None]) -> str:
    """Extract project name from target name"""
    if not target:
        return ""
    return TARGET_TO_PROJECT.get(target, target.split('_')[0] if '_' in target else target)

# -------- Data Comparison and Validation --------
def get_json_data(json_path: Path) -> dict:
    """Load and return JSON data"""
    with open(json_path, "r", encoding="utf-8") as f:
        return json.load(f)

def get_excel_data_from_json(json_data: dict) -> pd.DataFrame:
    """Extract all data from JSON in the same format as Excel comparison needs"""
    rows = []
    results = json_data.get("results", {})
    
    for fuzzer, projects in results.items():
        for project, targets in projects.items():
            for target, bugmap in targets.items():
                for bug_id, seed_map in bugmap.items():
                    metrics = next(iter(seed_map.values())) if seed_map else {}
                    reached = metrics.get("reached", {})
                    triggered = metrics.get("triggered", {})
                    
                    # Get the first value from each dict
                    reached_val = next(iter(reached.values())) if reached else 0
                    triggered_val = next(iter(triggered.values())) if triggered else 0

                    rows.append({
                        "fuzzer": fuzzer,
                        "project": project,
                        "target": target,
                        "bug": bug_id.upper(),
                        "reached": reached_val,
                        "triggered": triggered_val
                    })
    
    return pd.DataFrame(rows)

def create_empty_excel_from_json(json_df: pd.DataFrame) -> pd.DataFrame:
    """Create an empty Excel DataFrame with the correct multi-level header structure"""
    # Create the multi-level column structure
    columns = [
        ('Program', 'Unnamed: 0_level_1'),
        ('BUG_ID', 'Unnamed: 1_level_1'),
        ('PBFuzz', 'R'),
        ('PBFuzz', 'TTR'),
        ('PBFuzz', 'T'),
        ('PBFuzz', 'TTE'),
        ('cursor', 'R'),
        ('cursor', 'TTR'),
        ('cursor', 'T'),
        ('cursor', 'TTE'),
        ('cursor-tools', 'R'),
        ('cursor-tools', 'TTR'),
        ('cursor-tools', 'T'),
        ('cursor-tools', 'TTE')
    ]
    
    # Create empty DataFrame with multi-level columns
    empty_df = pd.DataFrame(columns=pd.MultiIndex.from_tuples(columns))
    
    return empty_df

def find_missing_rows(excel_df: pd.DataFrame, json_df: pd.DataFrame) -> pd.DataFrame:
    """Find rows that exist in JSON but not in Excel"""
    # Get all combinations from Excel
    excel_keys = set()
    current_target = None
    
    for idx, row in excel_df.iterrows():
        target_val = row.iloc[0]  # Program column
        bug_val = row.iloc[1]     # BUG_ID column
        
        if pd.notna(target_val):
            current_target = str(target_val).strip()
        
        if pd.notna(bug_val):
            bug_id = str(bug_val).strip()
            project = extract_project_from_target(current_target)
            
            # Check both fuzzers
            for fuzzer in ['pbfuzz', 'cursor_cli', 'cursor_pbfuzz_tools']:
                excel_keys.add((fuzzer, project, current_target, bug_id))
    
    # Get all combinations from JSON
    json_keys = set()
    for _, row in json_df.iterrows():
        json_keys.add((row['fuzzer'], row['project'], row['target'], row['bug']))
    
    # Find missing combinations
    missing_keys = json_keys - excel_keys
    missing_rows = json_df[json_df.apply(
        lambda row: (row['fuzzer'], row['project'], row['target'], row['bug']) in missing_keys, 
        axis=1
    )]
    
    return missing_rows

def compare_and_fill_excel(excel_df: pd.DataFrame, json_df: pd.DataFrame, fix_mismatches: bool = False):
    """Compare Excel with JSON and fill missing/inconsistent data"""
    audit_filled = []
    audit_mismatch = []
    
    current_target = None
    
    for idx, row in excel_df.iterrows():
        target_val = row.iloc[0]  # Program column
        bug_val = row.iloc[1]     # BUG_ID column
        
        # Update current target context
        if pd.notna(target_val):
            current_target = str(target_val).strip()
        
        if pd.notna(bug_val):
            bug_id = str(bug_val).strip()
            project = extract_project_from_target(current_target)
            
            # Process each fuzzer's columns
            for fuzzer_excel, fuzzer_json in FUZZER_MAPPING.items():
                # Find corresponding JSON data
                json_row = json_df[
                    (json_df['fuzzer'] == fuzzer_json) &
                    (json_df['project'] == project) &
                    (json_df['target'] == current_target) &
                    (json_df['bug'] == bug_id)
                ]
                
                if json_row.empty:
                    continue
                
                json_data = json_row.iloc[0]
                reached_val = json_data['reached']
                triggered_val = json_data['triggered']
                
                # Find the column indices for this fuzzer
                fuzzer_cols = {}
                for i, col in enumerate(excel_df.columns):
                    if isinstance(col, tuple) and col[0] == fuzzer_excel:
                        fuzzer_cols[col[1]] = i
                
                # Process R column (reached status)
                if 'R' in fuzzer_cols:
                    r_col_idx = fuzzer_cols['R']
                    current_r = excel_df.iloc[idx, r_col_idx]
                    new_r = '✅' if reached_val > 0 else '❌'
                    
                    if pd.isna(current_r):
                        excel_df.iloc[idx, r_col_idx] = new_r
                        audit_filled.append({
                            'fuzzer': fuzzer_json,
                            'target': current_target,
                            'bug': bug_id,
                            'column': f'{fuzzer_excel}_R',
                            'old_value': 'NaN',
                            'new_value': new_r
                        })
                    elif current_r != new_r:
                        audit_mismatch.append({
                            'fuzzer': fuzzer_json,
                            'target': current_target,
                            'bug': bug_id,
                            'column': f'{fuzzer_excel}_R',
                            'excel_value': current_r,
                            'json_value': new_r
                        })
                        if fix_mismatches:
                            excel_df.iloc[idx, r_col_idx] = new_r
                
                # Process TTR column (reached count)
                if 'TTR' in fuzzer_cols:
                    ttr_col_idx = fuzzer_cols['TTR']
                    current_ttr = excel_df.iloc[idx, ttr_col_idx]
                    new_ttr = reached_val if reached_val > 0 else None
                    
                    if pd.isna(current_ttr):
                        excel_df.iloc[idx, ttr_col_idx] = new_ttr
                        audit_filled.append({
                            'fuzzer': fuzzer_json,
                            'target': current_target,
                            'bug': bug_id,
                            'column': f'{fuzzer_excel}_TTR',
                            'old_value': 'NaN',
                            'new_value': new_ttr
                        })
                    elif current_ttr != new_ttr:
                        audit_mismatch.append({
                            'fuzzer': fuzzer_json,
                            'target': current_target,
                            'bug': bug_id,
                            'column': f'{fuzzer_excel}_TTR',
                            'excel_value': current_ttr,
                            'json_value': new_ttr
                        })
                        if fix_mismatches:
                            excel_df.iloc[idx, ttr_col_idx] = new_ttr
                
                # Process T column (triggered status)
                if 'T' in fuzzer_cols:
                    t_col_idx = fuzzer_cols['T']
                    current_t = excel_df.iloc[idx, t_col_idx]
                    new_t = '✅' if triggered_val > 0 else '❌'
                    
                    if pd.isna(current_t):
                        excel_df.iloc[idx, t_col_idx] = new_t
                        audit_filled.append({
                            'fuzzer': fuzzer_json,
                            'target': current_target,
                            'bug': bug_id,
                            'column': f'{fuzzer_excel}_T',
                            'old_value': 'NaN',
                            'new_value': new_t
                        })
                    elif current_t != new_t:
                        audit_mismatch.append({
                            'fuzzer': fuzzer_json,
                            'target': current_target,
                            'bug': bug_id,
                            'column': f'{fuzzer_excel}_T',
                            'excel_value': current_t,
                            'json_value': new_t
                        })
                        if fix_mismatches:
                            excel_df.iloc[idx, t_col_idx] = new_t
                
                # Process TTE column (triggered count)
                if 'TTE' in fuzzer_cols:
                    tte_col_idx = fuzzer_cols['TTE']
                    current_tte = excel_df.iloc[idx, tte_col_idx]
                    new_tte = triggered_val if triggered_val > 0 else None
                    
                    if pd.isna(current_tte):
                        excel_df.iloc[idx, tte_col_idx] = new_tte
                        audit_filled.append({
                            'fuzzer': fuzzer_json,
                            'target': current_target,
                            'bug': bug_id,
                            'column': f'{fuzzer_excel}_TTE',
                            'old_value': 'NaN',
                            'new_value': new_tte
                        })
                    elif current_tte != new_tte:
                        audit_mismatch.append({
                            'fuzzer': fuzzer_json,
                            'target': current_target,
                            'bug': bug_id,
                            'column': f'{fuzzer_excel}_TTE',
                            'excel_value': current_tte,
                            'json_value': new_tte
                        })
                        if fix_mismatches:
                            excel_df.iloc[idx, tte_col_idx] = new_tte
    
    return pd.DataFrame(audit_filled), pd.DataFrame(audit_mismatch)

def insert_missing_rows(excel_df: pd.DataFrame, missing_rows: pd.DataFrame) -> pd.DataFrame:
    """Insert missing rows into Excel DataFrame, maintaining the original format"""
    if missing_rows.empty:
        return excel_df
    
    # Group missing rows by target
    missing_by_target = {}
    for _, row in missing_rows.iterrows():
        target = row['target']
        if target not in missing_by_target:
            missing_by_target[target] = []
        missing_by_target[target].append(row)
    
    # Create new rows for each target
    new_rows = []
    for target, rows in missing_by_target.items():
        # Group by bug_id to avoid duplicates
        bugs = set()
        for row in rows:
            bugs.add(row['bug'])
        
        for bug_id in sorted(bugs):
            # Create a new row with the same structure as Excel
            new_row: list = [None] * len(excel_df.columns)
            
            # Set Program (target) - only in first row of each target group
            new_row[0] = target
            
            # Set BUG_ID
            new_row[1] = bug_id
            
            # Fill fuzzer data
            for fuzzer_excel, fuzzer_json in FUZZER_MAPPING.items():
                # Find the fuzzer's data for this specific bug
                fuzzer_data = None
                for row in rows:
                    if row['fuzzer'] == fuzzer_json and row['bug'] == bug_id:
                        fuzzer_data = row
                        break
                
                if fuzzer_data is not None:
                    reached_val = fuzzer_data['reached']
                    triggered_val = fuzzer_data['triggered']
                    
                    # Find column indices for this fuzzer
                    for i, col in enumerate(excel_df.columns):
                        if isinstance(col, tuple) and col[0] == fuzzer_excel:
                            if col[1] == 'R':
                                new_row[i] = '✅' if reached_val > 0 else '❌'
                            elif col[1] == 'TTR':
                                new_row[i] = reached_val if reached_val > 0 else None
                            elif col[1] == 'T':
                                new_row[i] = '✅' if triggered_val > 0 else '❌'
                            elif col[1] == 'TTE':
                                new_row[i] = triggered_val if triggered_val > 0 else None
            
            new_rows.append(new_row)
    
    # Insert new rows at the end
    if new_rows:
        new_df = pd.DataFrame(new_rows, columns=excel_df.columns)
        if excel_df.empty:
            result_df = new_df
        else:
            result_df = pd.concat([excel_df, new_df], ignore_index=True)
    else:
        result_df = excel_df
    
    return result_df

def find_extra_rows(excel_df: pd.DataFrame, json_df: pd.DataFrame) -> pd.DataFrame:
    """Find rows that exist in Excel but not in JSON"""
    # Get all combinations from JSON
    json_keys = set()
    for _, row in json_df.iterrows():
        json_keys.add((row['fuzzer'], row['project'], row['target'], row['bug']))
    
    # Get all combinations from Excel
    excel_keys = set()
    current_target = None
    
    for idx, row in excel_df.iterrows():
        target_val = row.iloc[0]  # Program column
        bug_val = row.iloc[1]     # BUG_ID column
        
        if pd.notna(target_val):
            current_target = str(target_val).strip()
        
        if pd.notna(bug_val):
            bug_id = str(bug_val).strip()
            project = extract_project_from_target(current_target)
            
            # Check both fuzzers
            for fuzzer in ['pbfuzz', 'cursor_cli', 'cursor_pbfuzz_tools']:
                excel_keys.add((fuzzer, project, current_target, bug_id))
    
    # Find extra combinations
    extra_keys = excel_keys - json_keys
    
    # Create DataFrame with extra rows
    extra_rows = []
    current_target = None
    
    for idx, row in excel_df.iterrows():
        target_val = row.iloc[0]  # Program column
        bug_val = row.iloc[1]     # BUG_ID column
        
        if pd.notna(target_val):
            current_target = str(target_val).strip()
        
        if pd.notna(bug_val):
            bug_id = str(bug_val).strip()
            project = extract_project_from_target(current_target)
            
            # Check if this combination is extra
            for fuzzer in ['pbfuzz', 'cursor_cli', 'cursor_pbfuzz_tools']:
                if (fuzzer, project, current_target, bug_id) in extra_keys:
                    extra_rows.append({
                        'fuzzer': fuzzer,
                        'project': project,
                        'target': current_target,
                        'bug': bug_id,
                        'row_index': idx
                    })
    
    return pd.DataFrame(extra_rows)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", default="results_pretty.json")
    ap.add_argument("--excel", default="experiment_data.xlsx", 
                    help="Excel file to process (default: experiment_data.xlsx)")
    ap.add_argument("--out", default="experiment_data.filled.xlsx")
    ap.add_argument("--fix-mismatches", action="store_true")
    args = ap.parse_args()

    # Load JSON data
    json_data = get_json_data(Path(args.json))
    json_df = get_excel_data_from_json(json_data)
    
    # Read Excel with multi-level headers, or create new if file doesn't exist
    if Path(args.excel).exists():
        print("Reading Excel with multi-level headers...")
        excel_df = pd.read_excel(args.excel, header=[0,1])
    else:
        print(f"Excel file '{args.excel}' not found. Creating new Excel file from JSON data...")
        excel_df = create_empty_excel_from_json(json_df)
    
    # Find missing rows
    missing_rows = find_missing_rows(excel_df, json_df)
    print(f"Found {len(missing_rows)} missing rows")
    
    # Compare and fill existing data
    audit_filled, audit_mismatch = compare_and_fill_excel(excel_df, json_df, args.fix_mismatches)
    print(f"Filled {len(audit_filled)} cells")
    print(f"Found {len(audit_mismatch)} mismatches")
    
    # Insert missing rows
    excel_df = insert_missing_rows(excel_df, missing_rows)
    print(f"Inserted {len(missing_rows)} new rows")
    
    # Find extra rows
    audit_extra = find_extra_rows(excel_df, json_df)
    print(f"Found {len(audit_extra)} extra rows")
    
    # Create audit_added from missing_rows
    audit_added = missing_rows[['fuzzer', 'project', 'target', 'bug', 'reached', 'triggered']].copy()

    # Write output using openpyxl to preserve original format
    try:
        from openpyxl import Workbook
    except ImportError:
        raise ImportError("openpyxl is required. Install it with: pip install openpyxl")
    
    wb = Workbook()
    ws = wb.active
    if ws is not None:
        ws.title = "data"
    
    # Write the multi-level header
    header_row1 = []
    header_row2 = []
    for col in excel_df.columns:
        if isinstance(col, tuple):
            header_row1.append(col[0])
            header_row2.append(col[1])
        else:
            header_row1.append(str(col))
            header_row2.append("")
    
    if ws is not None:
        ws.append(header_row1)
        ws.append(header_row2)
        
        # Write data rows
        for _, row in excel_df.iterrows():
            ws.append(row.tolist())
    
    # Save the workbook
    wb.save(args.out)
    
    # Now add audit sheets using pandas
    with pd.ExcelWriter(args.out, engine="openpyxl", mode='a') as w:
        # Audit sheets
        if not audit_added.empty:
            audit_added.to_excel(w, index=False, sheet_name="audit_added")
        else:
            pd.DataFrame(columns=['fuzzer', 'project', 'target', 'bug', 'reached', 'triggered']).to_excel(w, index=False, sheet_name="audit_added")
        
        if not audit_filled.empty:
            audit_filled.to_excel(w, index=False, sheet_name="audit_filled")
        else:
            pd.DataFrame(columns=['fuzzer', 'target', 'bug', 'column', 'old_value', 'new_value']).to_excel(w, index=False, sheet_name="audit_filled")
        
        if not audit_mismatch.empty:
            audit_mismatch.to_excel(w, index=False, sheet_name="audit_mismatch")
        else:
            pd.DataFrame(columns=['fuzzer', 'target', 'bug', 'column', 'excel_value', 'json_value']).to_excel(w, index=False, sheet_name="audit_mismatch")
        
        if not audit_extra.empty:
            audit_extra.to_excel(w, index=False, sheet_name="audit_extra")
        else:
            pd.DataFrame(columns=['fuzzer', 'project', 'target', 'bug', 'row_index']).to_excel(w, index=False, sheet_name="audit_extra")

    # Summary
    print("\n[SUMMARY]")
    print(f"New rows added: {len(audit_added)}")
    print(f"Cells filled:   {len(audit_filled)}")
    print(f"Mismatches:     {len(audit_mismatch)} rows{' (fixed)' if args.fix_mismatches else ''}")
    print(f"Extra rows:     {len(audit_extra)} rows")

if __name__ == "__main__":
    main()