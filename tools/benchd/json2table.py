#!/usr/bin/env python3
import json
import statistics
import csv
import warnings
from collections import defaultdict

from survival_analysis import parse_args, get_time_to_bug, calc_survival, calc_median_survival, METRICS

fuzzers = set()

def output_details(json_path, csv_path, num_trials, trial_length):
    global fuzzers
    # Load JSON data
    with open(json_path) as f:
        data = json.load(f).get('results', {})
    
    # Ignore warnings
    warnings.simplefilter('ignore')
    
    # Collect bug stats per fuzzer; use "program/bug" as unique key
    fuzzer_stats = defaultdict(lambda: defaultdict(dict))
    all_prog_bugs = set()
    # Use get_time_to_bug function from survival_analysis.py
    for ttb in get_time_to_bug(data, num_trials):
        fuzzer = ttb['fuzzer']
        fuzzers.add(fuzzer)
        bug = ttb['bug']
        program = ttb['program']
        prog_bug = f"{program}/{bug}"
        all_prog_bugs.add(prog_bug)
        
        # Do survival analysis for both reached and triggered
        stats = {}
        for metric in METRICS:
            if metric in ttb:
                surv_time, surv_ci = calc_survival(ttb[metric], trial_length)
                surv_time_int = int(surv_time) if surv_time is not None else 'T.O'
                surv_ci_int = int(surv_ci) if surv_ci is not None else 'NA'
            else:
                surv_time_int = 'T.O'
                surv_ci_int = 'NA'
            
            # Calculate median for comparison
            times = ttb.get(metric, [])
            med_surv = calc_median_survival(times, trial_length)
            if med_surv is not None:
                med_time = int(med_surv)
            else:
                med_time = 'T.O'

            # Calculate success count (number of successful trials)
            success_count = sum(1 for t in times if t is not None)
            
            stats[f'surv_{metric}'] = surv_time_int
            stats[f'ci_{metric}'] = surv_ci_int
            stats[f'med_{metric}'] = med_time
            stats[f'count_{metric}'] = success_count
        
        fuzzer_stats[fuzzer][prog_bug] = stats

    # Prepare CSV header
    header = ['program_bug_id']
    for f in fuzzers:
        for metric in METRICS:
            header += [f'{f}_surv_{metric}', f'{f}_ci_{metric}', f'{f}_med_{metric}', f'{f}_count_{metric}']

    # Write CSV
    with open(csv_path, 'w', newline='') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(header)
        for prog_bug in sorted(all_prog_bugs):
            row = [prog_bug]
            for f in fuzzers:
                stats = fuzzer_stats.get(f, {}).get(prog_bug, {})
                for metric in METRICS:
                    row.append(stats.get(f'surv_{metric}', 'T.O'))
                    row.append(stats.get(f'ci_{metric}', 0))
                    row.append(stats.get(f'med_{metric}', 'T.O'))
                    row.append(stats.get(f'count_{metric}', 0))
            writer.writerow(row)

def output_overall(json_path, csv_path):
    global fuzzers
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
    # The same argument parser as survival_analysis.py
    args = parse_args()
    output_details(args.json, "details.csv", args.num_trials, args.trial_length)
