#!/usr/bin/env python3
import json
import csv
import sys

# Fuzzers to include
fuzzers = ['selectfuzz', 'aflgo', 'aflplusplus_cmplog', 'aflplusplus_symsan']

def output_details(json_path, csv_path):
    # Load JSON data
    with open(json_path) as f:
        data = json.load(f).get('results', {})
    
    # Collect bug stats per fuzzer
    fuzzer_stats = {}
    all_bugs = set()
    for fuzzer in fuzzers:
        bug_times = {}
        if fuzzer not in data:
            fuzzer_stats[fuzzer] = {}
            continue
        for target, progs in data[fuzzer].items():
            for prog, runs in progs.items():
                for run_id, metrics in runs.items():
                    # Reached times = TTR
                    for bug, t in metrics.get('reached', {}).items():
                        bug_times.setdefault(bug, {'ttr': [], 'tte': []})
                        bug_times[bug]['ttr'].append(t)
                        all_bugs.add(bug)
                    # Triggered times = TTE
                    for bug, t in metrics.get('triggered', {}).items():
                        bug_times.setdefault(bug, {'ttr': [], 'tte': []})
                        bug_times[bug]['tte'].append(t)
                        all_bugs.add(bug)
        # Compute statistics
        stats = {}
        for bug, times in bug_times.items():
            # average and median for TTR
            if times['ttr']:
                avg_ttr = int(sum(times['ttr']) / len(times['ttr']))
                med_ttr = int(sorted(times['ttr'])[len(times['ttr']) // 2])
            else:
                avg_ttr = 'T.O'
                med_ttr = 'T.O'
            # average and median for TTE
            if times['tte']:
                avg_tte = int(sum(times['tte']) / len(times['tte']))
                med_tte = int(sorted(times['tte'])[len(times['tte']) // 2])
            else:
                avg_tte = 'T.O'
                med_tte = 'T.O'
            stats[bug] = {
                'avg_TTE': avg_tte,
                'avg_TTR': avg_ttr,
                'med_TTE': med_tte,
                'med_TTR': med_ttr
            }
        fuzzer_stats[fuzzer] = stats

    # Prepare CSV header
    header = ['bug_id']
    for f in fuzzers:
        header += [f + '_avg_TTE', f + '_avg_TTR', f + '_med_TTE', f + '_med_TTR']

    # Write CSV
    with open(csv_path, 'w', newline='') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(header)
        for bug in sorted(all_bugs):
            row = [bug]
            for f in fuzzers:
                stats = fuzzer_stats.get(f, {}).get(bug, {})
                row.append(stats.get('avg_TTE', 'T.O'))
                row.append(stats.get('avg_TTR', 'T.O'))
                row.append(stats.get('med_TTE', 'T.O'))
                row.append(stats.get('med_TTR', 'T.O'))
            writer.writerow(row)

def output_overall(json_path, csv_path):
    # Load results
    with open(json_path) as f:
        data = json.load(f)
    results = data.get('results', {})

    # Prepare CSV
    fieldnames = ['Target', 'Fuzzer', 'Avg TTR (s)', 'Med TTR (s)', 'Avg TTE (s)', 'Med TTE (s)']
    rows = []

    for fuzzer in fuzzers:
        if fuzzer not in results:
            continue
        targets = sorted(results[fuzzer].keys())
        for target in targets:
            ttr_times = []
            tte_times = []
            prog_runs = results[fuzzer][target]
            # Gather all reach/trigger times
            for runs in prog_runs.values():
                for metrics in runs.values():
                    ttr_times.extend(metrics.get('reached', {}).values())
                    tte_times.extend(metrics.get('triggered', {}).values())

            # Compute stats
            if ttr_times:
                avg_ttr = int(sum(ttr_times) / len(ttr_times))
                med_ttr = int(sorted(ttr_times)[len(ttr_times)//2])
            else:
                avg_ttr = ''
                med_ttr = ''

            if tte_times:
                avg_tte = int(sum(tte_times) / len(tte_times))
                med_tte = int(sorted(tte_times)[len(tte_times)//2])
            else:
                avg_tte = ''
                med_tte = ''

            rows.append({
                'Target': target,
                'Fuzzer': fuzzer,
                'Avg TTR (s)': avg_ttr,
                'Med TTR (s)': med_ttr,
                'Avg TTE (s)': avg_tte,
                'Med TTE (s)': med_tte,
            })

    # Write to CSV
    with open(csv_path, 'w', newline='') as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <results.json>")
        sys.exit(1)
    output_overall(sys.argv[1], "overall.csv")
    output_details(sys.argv[1], "details.csv")
