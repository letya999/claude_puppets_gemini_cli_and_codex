# Plan: Internet Speed Scripts

## Goal
Create two Python scripts in the project root:
1. `measure_speed.py` - measures current internet speed
2. `show_speed.py` - displays the result in the console

## Steps

### Step 1: Create `measure_speed.py`
- File: project root / measure_speed.py
- Uses `speedtest-cli` library (`pip install speedtest-cli`)
- Measures download Mbps, upload Mbps, ping ms
- Outputs result as JSON to stdout (machine-readable)

### Step 2: Create `show_speed.py`
- File: project root / show_speed.py
- Calls `measure_speed.py` via subprocess
- Parses JSON output
- Prints formatted table to console

## Requirements
- Python 3.x
- speedtest-cli: `pip install speedtest-cli`
- No hardcoded configs
- Comments only where logic is non-obvious
