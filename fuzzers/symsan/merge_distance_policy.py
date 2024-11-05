#!/usr/bin/env python3

import os
import sys
from pathlib import Path

def remove_repeated_lines(fp):
    lines = set()
    with open(fp, 'r') as f:
        for l in f.readlines():
            if not l: continue
            if l == '\n': continue
            lines.add(l)
    lines = list(lines)
    with open(fp, 'w') as f:
        f.writelines(lines)

def sort_key(item):
    return item[1] if item[1] >= 0 else float('inf')
        
if __name__ == '__main__':
    if len(sys.argv) != 2:
        print('Usage: python merge_distance_policy.py <static analysis results directory>')
        sys.exit(1)
    
    sa_dir = Path(sys.argv[1])
    if not os.path.isdir(sa_dir):
        print('Error: {} is not a directory'.format(sa_dir))
        sys.exit(1)
    
    reach_distance = sa_dir / 'distance_reach.cfg.txt'
    reach_policy = sa_dir / 'policy_reach.txt'
    trigger_distance = sa_dir / 'distance_trigger.cfg.txt'
    trigger_policy = sa_dir / 'policy_trigger.txt'
    if not (os.path.isfile(reach_distance) and os.path.isfile(reach_policy) and
        os.path.isfile(trigger_distance) and os.path.isfile(trigger_policy)):
        print('Static analysis results are missing')
        sys.exit(1)

    # Remove repeated lines
    remove_repeated_lines(reach_distance)
    remove_repeated_lines(reach_policy)
    remove_repeated_lines(trigger_distance)
    remove_repeated_lines(trigger_policy)
    
    # Merge distance
    with open(reach_distance, 'r') as f:
        reach_distance_lines = f.readlines()
    with open(trigger_distance, 'r') as f:
        trigger_distance_lines = f.readlines()
    distance_dict = {}
    for l in trigger_distance_lines:
        items = l.split(',')
        bid, loc, distance = items[0], items[1], float(items[2])
        distance_dict[(bid, loc)] = distance
    for l in reach_distance_lines:
        items = l.split(',')
        bid, loc, distance = items[0], items[1], float(items[2])
        distance_dict[(bid, loc)] = distance + 1000.
    distance_dict = dict(sorted(distance_dict.items(), key=sort_key))
    with open(sa_dir / 'distance.cfg.txt', 'w') as f:
        for k, v in distance_dict.items():
            f.write('{},{},{}\n'.format(k[0], k[1], v))
    os.unlink(reach_distance)
    os.unlink(trigger_distance)
    
    # Merge policy
    with open(reach_policy, 'r') as f:
        reach_policy_lines = f.readlines()
    with open(trigger_policy, 'r') as f:
        trigger_policy_lines = f.readlines()
    with open(sa_dir / 'policy.txt', 'a') as f:
        f.writelines(reach_policy_lines)
        f.writelines(trigger_policy_lines)
    os.unlink(reach_policy)
    os.unlink(trigger_policy)
