#!/usr/bin/env python3
"""
Analyze tool calling statistics from agent.log files in pbfuzz experiments.

This script:
1. Finds all agent.log files under pbfuzz directory
2. Extracts tool calls from two patterns:
   - "⬢ <server> <tool>" or "⬢ <tool> ..."
   - "$ <shell_command> ..."
3. Generates a CSV table with experiments as rows and tool counts as columns
"""

import os
import re
import csv
from pathlib import Path
from collections import defaultdict
from typing import Dict, List, Tuple


def normalize_tool_name(tool_name: str) -> str:
    """
    Normalize tool names by removing trailing punctuation and variations.
    
    Examples:
        - "Read", "Read,", "Reading", "Reading." -> "Read"
        - "Grepped", "Grepped,", "Grepping" -> "Grepped"
        - "Listed", "Listed,", "Listing" -> "Listed"
        - "Searched", "Searched," -> "Searched"
    """
    # First, remove trailing punctuation (commas, periods)
    tool_name = tool_name.rstrip('.,')
    
    # Map variations to base form
    variations_map = {
        'Reading': 'Read',
        'Grepping': 'Grepped',
        'Listing': 'Listed',
    }
    
    return variations_map.get(tool_name, tool_name)


def should_skip_tool(tool_name: str) -> bool:
    """
    Check if a tool name should be skipped (not a real tool call).
    
    Skip patterns:
        - Generating, Generating., Generating.., Generating...
        - Calling, Calling., Calling.., Calling...
        - Running., Running.., Running...
    """
    # Remove trailing punctuation for checking
    base_name = tool_name.rstrip('.,')
    
    skip_prefixes = ['Generating', 'Calling', 'Running']
    
    return base_name in skip_prefixes


def parse_tool_calls(log_file_path: str) -> Dict[str, int]:
    """
    Parse an agent.log file and count tool calls.
    
    Returns:
        Dictionary mapping tool names to call counts
    """
    tool_counts = defaultdict(int)
    
    try:
        with open(log_file_path, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                line = line.strip()
                
                # Pattern 1: "⬢ <server> <tool>" or "⬢ <tool> ..."
                if line.startswith('⬢ '):
                    # Remove the "⬢ " prefix
                    rest = line[2:].strip()
                    
                    # Split by whitespace
                    parts = rest.split(None, 1)  # Split on first whitespace only
                    
                    if len(parts) >= 1:
                        # First word is the tool name
                        raw_tool_name = parts[0]
                        
                        # Skip if it's not a real tool call
                        if should_skip_tool(raw_tool_name):
                            continue
                        
                        # Normalize the tool name
                        tool_name = normalize_tool_name(raw_tool_name)
                        tool_counts[tool_name] += 1
                
                # Pattern 2: "$ <shell_command> ..."
                elif line.startswith('$ '):
                    # Shell command
                    tool_counts['shell'] += 1
    
    except Exception as e:
        print(f"Error parsing {log_file_path}: {e}")
    
    return dict(tool_counts)


def extract_experiment_info(log_file_path: str, base_dir: str) -> str:
    """
    Extract experiment identifier from log file path.
    
    Format: <project>/<program>/<ID>
    Example: libpng/libpng_read_fuzzer/PNG001
    """
    # Get relative path from base_dir
    rel_path = os.path.relpath(log_file_path, base_dir)
    
    # Split path: project/program/ID/0/findings/agent.log
    parts = rel_path.split(os.sep)
    
    if len(parts) >= 3:
        project = parts[0]
        program = parts[1]
        bug_id = parts[2]
        return f"{project}/{program}/{bug_id}"
    
    return rel_path


def find_all_agent_logs(base_dir: str) -> List[str]:
    """
    Find all agent.log files under the base directory.
    """
    agent_logs = []
    
    for root, dirs, files in os.walk(base_dir):
        if 'agent.log' in files:
            agent_logs.append(os.path.join(root, 'agent.log'))
    
    return sorted(agent_logs)


def parse_whitelist(captainrc_path: str) -> set:
    """
    Parse WHITELIST from captainrc file.
    
    Returns a set of bug IDs (e.g., {"LUA001", "PDF002", ...})
    """
    whitelist = set()
    
    try:
        with open(captainrc_path, 'r') as f:
            in_whitelist = False
            for line in f:
                line = line.strip()
                
                if 'WHITELIST=(' in line:
                    in_whitelist = True
                    # Extract IDs from the same line if they exist after the opening paren
                    content = line.split('WHITELIST=(')[1]
                    if content and ')' not in line:
                        # IDs on the same line as WHITELIST=(
                        ids = content.strip().split()
                        for id_str in ids:
                            id_clean = id_str.strip('"')
                            if id_clean:
                                whitelist.add(id_clean)
                    elif ')' in content:
                        # All IDs are on this line
                        in_whitelist = False
                        content = content.split(')')[0]
                        ids = content.strip().split()
                        for id_str in ids:
                            id_clean = id_str.strip('"')
                            if id_clean:
                                whitelist.add(id_clean)
                elif in_whitelist:
                    if ')' in line:
                        in_whitelist = False
                        content = line.split(')')[0]
                        ids = content.strip().split()
                        for id_str in ids:
                            id_clean = id_str.strip('"')
                            if id_clean:
                                whitelist.add(id_clean)
                    else:
                        ids = line.strip().split()
                        for id_str in ids:
                            id_clean = id_str.strip('"')
                            if id_clean:
                                whitelist.add(id_clean)
    except Exception as e:
        print(f"Error parsing whitelist from {captainrc_path}: {e}")
    
    return whitelist


def generate_csv_report(base_dir: str, output_file: str, whitelist: set = None):
    """
    Generate CSV report of tool calling statistics.
    
    Args:
        base_dir: Base directory containing pbfuzz experiments
        output_file: Output CSV file path
        whitelist: Optional set of bug IDs to include. If None, include all.
    """
    # Find all agent.log files
    agent_logs = find_all_agent_logs(base_dir)
    print(f"Found {len(agent_logs)} agent.log files")
    
    if whitelist:
        print(f"Using whitelist filter: {len(whitelist)} bug IDs")
    
    # Parse all logs and collect statistics
    experiment_data = {}
    all_tools = set()
    skipped_count = 0
    
    for log_file in agent_logs:
        exp_name = extract_experiment_info(log_file, base_dir)
        
        # Extract bug ID from experiment name (e.g., "libpng/libpng_read_fuzzer/PNG001" -> "PNG001")
        bug_id = exp_name.split('/')[-1] if '/' in exp_name else exp_name
        
        # Skip if whitelist is provided and bug ID is not in it
        if whitelist and bug_id not in whitelist:
            skipped_count += 1
            continue
        
        tool_counts = parse_tool_calls(log_file)
        
        experiment_data[exp_name] = tool_counts
        all_tools.update(tool_counts.keys())
        
        print(f"Processed: {exp_name} ({sum(tool_counts.values())} total calls)")
    
    if whitelist:
        print(f"Skipped {skipped_count} experiments not in whitelist")
    
    # Sort tools alphabetically
    sorted_tools = sorted(all_tools)
    
    # Write CSV
    with open(output_file, 'w', newline='', encoding='utf-8') as csvfile:
        # Header: Experiment, tool1, tool2, ..., Total
        fieldnames = ['Experiment'] + sorted_tools + ['Total']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        
        writer.writeheader()
        
        # Write data for each experiment
        for exp_name in sorted(experiment_data.keys()):
            tool_counts = experiment_data[exp_name]
            
            row = {'Experiment': exp_name}
            total = 0
            
            for tool in sorted_tools:
                count = tool_counts.get(tool, 0)
                row[tool] = count
                total += count
            
            row['Total'] = total
            writer.writerow(row)
    
    print(f"\nCSV report generated: {output_file}")
    print(f"Total experiments: {len(experiment_data)}")
    print(f"Total unique tools: {len(all_tools)}")
    print(f"\nTool distribution:")
    
    # Calculate total calls per tool across all experiments
    tool_totals = defaultdict(int)
    for tool_counts in experiment_data.values():
        for tool, count in tool_counts.items():
            tool_totals[tool] += count
    
    for tool in sorted(tool_totals.keys(), key=lambda x: tool_totals[x], reverse=True):
        print(f"  {tool}: {tool_totals[tool]} calls")


def main():
    # Base directory for pbfuzz experiments
    base_dir = "/mnt/work/magma/tools/captain/workdir/ar/pbfuzz"
    
    # Output CSV files
    output_file_all = "/mnt/work/magma/tools/benchd/tool_call_statistics.csv"
    output_file_whitelist = "/mnt/work/magma/tools/benchd/tool_call_statistics_whitelist.csv"
    
    # captainrc path
    captainrc_path = "/mnt/work/magma/tools/captain/captainrc"
    
    print("=" * 80)
    print("Tool Call Statistics Analysis for PBFuzz Experiments")
    print("=" * 80)
    print()
    
    if not os.path.exists(base_dir):
        print(f"Error: Base directory does not exist: {base_dir}")
        return
    
    # Generate report for all experiments
    print("=" * 80)
    print("REPORT 1: All Experiments")
    print("=" * 80)
    generate_csv_report(base_dir, output_file_all)
    
    # Generate report for whitelist experiments only
    print("\n" + "=" * 80)
    print("REPORT 2: Whitelist Experiments Only (from captainrc)")
    print("=" * 80)
    
    if os.path.exists(captainrc_path):
        whitelist = parse_whitelist(captainrc_path)
        print(f"\nLoaded whitelist with {len(whitelist)} bug IDs:")
        print(f"  {sorted(whitelist)}")
        generate_csv_report(base_dir, output_file_whitelist, whitelist=whitelist)
    else:
        print(f"Warning: captainrc not found at {captainrc_path}")
        print("Skipping whitelist report generation")
    
    print("\n" + "=" * 80)
    print("Done!")


if __name__ == "__main__":
    main()

