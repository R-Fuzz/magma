#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Analyze trigger statistics from results_pretty.json based on WHITELIST.

Usage:
  python3 analyze_triggers.py --json <path> --captainrc <path> --max-round <N>

Optional Arguments:
  --json JSON              Path to results_pretty.json (default: results_pretty.json)
  --captainrc CAPTAINRC    Path to captainrc file (default: captainrc)
  --max-round MAX_ROUND    Maximum round ID to analyze (default: 8)
  --output OUTPUT          Output CSV file (default: trigger_statistics.csv)

Example:
  python3 analyze_triggers.py \
    --json /mnt/work/magma/tools/captain/consistency/results_pretty.json \
    --captainrc /mnt/work/magma/tools/captain/captainrc \
    --max-round 8

Output:
  A CSV file with the following structure:
  - Column 1: Fuzzer/Bug (e.g., "sndfile_fuzzer/SND005")
  - Columns 2-N: Round 0 through Round max_round
    * ✓ = Bug was triggered in that round
    * ✗ = Bug was NOT triggered in that round
  - Last Column: Count = Total number of rounds where bug was triggered

Notes:
  - A bug is considered "triggered" if the "triggered" dictionary for that 
    bug in a given round contains a value > 0
  - Only bugs listed in the WHITELIST section of captainrc are analyzed
  - Empty round data is treated as NA (no data for that round)
  - Results are sorted alphabetically by Fuzzer/Bug combination

"""
import argparse
import json
import re
from pathlib import Path
from typing import Dict, List, Set, Tuple
import pandas as pd


def parse_whitelist(captainrc_path: Path) -> Set[str]:
    """Extract WHITELIST from captainrc file."""
    whitelist = set()
    with open(captainrc_path, 'r') as f:
        content = f.read()
    
    # Find WHITELIST section
    match = re.search(r'WHITELIST=\((.*?)\)', content, re.DOTALL)
    if match:
        whitelist_content = match.group(1)
        # Extract quoted strings
        bugs = re.findall(r'"([^"]+)"', whitelist_content)
        whitelist.update(bugs)
    
    return whitelist


def extract_fuzzers_and_bugs(json_data: Dict, whitelist: Set[str]) -> Dict[str, List[Tuple[str, int]]]:
    """
    Extract fuzzer/bug combinations from JSON data.
    Returns dict: fuzzer_name -> [(bug_id, round_id), ...]
    """
    results = {}
    
    # Traverse the nested structure: results -> pbfuzz -> project -> fuzzer -> bug_id -> round_id
    if 'results' not in json_data or 'pbfuzz' not in json_data['results']:
        return results
    
    pbfuzz_data = json_data['results']['pbfuzz']
    
    for project, project_data in pbfuzz_data.items():
        if not isinstance(project_data, dict):
            continue
        
        for fuzzer, fuzzer_data in project_data.items():
            if not isinstance(fuzzer_data, dict):
                continue
            
            for bug_id, bug_data in fuzzer_data.items():
                # Check if this bug is in whitelist
                if bug_id not in whitelist:
                    continue
                
                if not isinstance(bug_data, dict):
                    continue
                
                fuzzer_key = f"{fuzzer}/{bug_id}"
                if fuzzer_key not in results:
                    results[fuzzer_key] = []
                
                for round_id_str, round_data in bug_data.items():
                    try:
                        round_id = int(round_id_str)
                        results[fuzzer_key].append((bug_id, round_id))
                    except (ValueError, TypeError):
                        continue
    
    return results


def check_trigger(json_data: Dict, fuzzer_name: str, bug_id: str, round_id: int):
    """
    Check if a specific fuzzer/bug combination triggered in a given round.
    Returns:
      - True: triggered (bug_id in triggered dict with value > 0)
      - False: round exists but not triggered (bug_id not in triggered or value == 0)
      - None: empty round data (round_id not found)
    """
    pbfuzz_data = json_data.get('results', {}).get('pbfuzz', {})
    
    # Find the project and fuzzer
    for project, project_data in pbfuzz_data.items():
        if fuzzer_name in project_data:
            fuzzer_data = project_data[fuzzer_name]
            if bug_id in fuzzer_data:
                bug_data = fuzzer_data[bug_id]
                if str(round_id) in bug_data:
                    # Round data exists
                    round_data = bug_data[str(round_id)]
                    triggered = round_data.get('triggered', {})
                    # Check if bug_id is in triggered with non-zero count
                    return bug_id in triggered and triggered[bug_id] > 0
                else:
                    # Round data does not exist for this bug/fuzzer
                    return None
    
    return None


def build_trigger_table(json_path: Path, captainrc_path: Path, max_round: int) -> pd.DataFrame:
    """Build trigger statistics table."""
    # Load JSON
    with open(json_path, 'r') as f:
        json_data = json.load(f)
    
    # Parse whitelist
    whitelist = parse_whitelist(captainrc_path)
    print(f"Found {len(whitelist)} bugs in WHITELIST: {sorted(whitelist)}")
    
    # Extract fuzzer/bug combinations
    fuzzers_bugs = extract_fuzzers_and_bugs(json_data, whitelist)
    print(f"Found {len(fuzzers_bugs)} fuzzer/bug combinations in JSON")
    
    # Build table
    # Rows: fuzzer/bug_id, Columns: round_id (0 to max_round) + Count
    rows = []
    
    for fuzzer_key in sorted(fuzzers_bugs.keys()):
        fuzzer_name, bug_id = fuzzer_key.rsplit('/', 1)
        row_data = {'Fuzzer/Bug': fuzzer_key}
        
        trigger_count = 0
        for round_id in range(max_round + 1):
            result = check_trigger(json_data, fuzzer_name, bug_id, round_id)
            # result can be True (triggered), False (not triggered), or None (no data)
            if result is True:
                row_data[f'Round {round_id}'] = '✓'
                trigger_count += 1
            elif result is False:
                row_data[f'Round {round_id}'] = '✗'
            else:  # result is None
                row_data[f'Round {round_id}'] = 'NA'
        
        row_data['Count'] = trigger_count
        rows.append(row_data)
    
    df = pd.DataFrame(rows)
    
    return df


def main():
    parser = argparse.ArgumentParser(description='Analyze trigger statistics from results JSON')
    parser.add_argument('--json', type=Path, default=Path('results_pretty.json'),
                        help='Path to results_pretty.json')
    parser.add_argument('--captainrc', type=Path, default=Path('captainrc'),
                        help='Path to captainrc file')
    parser.add_argument('--max-round', type=int, default=8,
                        help='Maximum round ID to analyze')
    parser.add_argument('--output', type=Path, default=Path('trigger_statistics.csv'),
                        help='Output CSV file')
    
    args = parser.parse_args()
    
    # Verify files exist
    if not args.json.exists():
        print(f"Error: {args.json} not found")
        return
    if not args.captainrc.exists():
        print(f"Error: {args.captainrc} not found")
        return
    
    print(f"Loading JSON from {args.json}")
    print(f"Loading WHITELIST from {args.captainrc}")
    print(f"Max round: {args.max_round}")
    
    # Build table
    df = build_trigger_table(args.json, args.captainrc, args.max_round)
    
    # Display table
    print("\n" + "="*80)
    print("TRIGGER STATISTICS TABLE")
    print("="*80)
    print(df.to_string(index=False))
    print("="*80)
    
    # Save to CSV
    df.to_csv(args.output, index=False)
    print(f"\nTable saved to {args.output}")


if __name__ == '__main__':
    main()

