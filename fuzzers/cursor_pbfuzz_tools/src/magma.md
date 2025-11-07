# Magma Benchmark Architecture - Instructions for LLM Agents

## Overview

Magma is a ground-truth fuzzing benchmark suite that contains real programs with real bugs. The benchmark includes instrumentation to track two key metrics:
- **Reached count**: How many times buggy code is executed
- **Triggered count**: How many times the actual fault condition is satisfied by input

## Important: Do NOT Analyze Benchmark Instrumentation

**CRITICAL INSTRUCTION**: This benchmark contains instrumentation macros and functions that are ONLY used for measurement purposes. Do not waste time analyzing or trying to understand the following:

### Ignore These Macros/Functions:
- `MAGMA_LOG()` - This is benchmark instrumentation, NOT part of the target program
- `MAGMA_LOG_V()` - This is benchmark instrumentation, NOT part of the target program  
- `MAGMA_AND()` - This is benchmark instrumentation, NOT part of the target program
- `MAGMA_OR()` - This is benchmark instrumentation, NOT part of the target program
- `magma_log()` - This is the underlying benchmark function, NOT part of the target program

### Build Configuration (Fixed Values):
- `MAGMA_ENABLE_FIXES` - **UNDEFINED** (bugs are NOT fixed, they exist for fuzzing)
- `MAGMA_ENABLE_CANARIES` - **DEFINED** (instrumentation is enabled to track bug triggering)

## What This Means for Bug Triggering

When you see code like this in patches:
```c
#ifdef MAGMA_ENABLE_FIXES
    // Fixed version of code
#else
    // Buggy version of code
    #ifdef MAGMA_ENABLE_CANARIES
        MAGMA_LOG("%MAGMA_BUG%", condition_that_triggers_bug);
    #endif
#endif
```

**Focus ONLY on the buggy code path** (the `#else` branch). The `MAGMA_LOG` call is just measurement instrumentation - the actual bug exists in the surrounding buggy code logic.

## Your Task

1. **Focus on the actual bug logic** - not the MAGMA_LOG calls
2. **Understand the vulnerable code paths** - these are in the `#else` branches when MAGMA_ENABLE_FIXES is undefined
3. **Generate inputs that trigger the buggy conditions** - the conditions inside MAGMA_LOG calls show you what triggers the bug, your goal is to make this condition becomes true.
4. **Do not try to understand or reverse-engineer the benchmark infrastructure** - it's not part of the target program

Remember: You are fuzzing the TARGET PROGRAM, not the Magma benchmark infrastructure. The MAGMA_* macros are just measuring your success, not part of the attack surface.
