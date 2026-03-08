import subprocess
import json
import sys
import os

def show_speed():
    """Calls measure_speed.py, parses the JSON, and prints a formatted table."""
    try:
        # Get path to current directory to ensure we call the script correctly
        current_dir = os.path.dirname(os.path.abspath(__file__))
        measure_script_path = os.path.join(current_dir, "measure_speed.py")
        
        # Execute measure_speed.py and capture stdout
        result = subprocess.run(
            [sys.executable, measure_script_path],
            capture_output=True,
            text=True,
            check=True
        )
        
        # Parse JSON output from measure_speed.py
        data = json.loads(result.stdout)
        
        if "error" in data:
            print(f"Error measuring speed: {data['error']}")
            sys.exit(1)
            
        # Print formatted table
        print("-" * 50)
        print(f"{'Metric':<20} | {'Value'}")
        print("-" * 50)
        print(f"{'Download (Mbps)':<20} | {data['download_mbps']}")
        print(f"{'Upload (Mbps)':<20} | {data['upload_mbps']}")
        print(f"{'Ping (ms)':<20} | {data['ping_ms']}")
        print(f"{'Server':<20} | {data['server']['name']} ({data['server']['location']})")
        print("-" * 50)
        
    except subprocess.CalledProcessError as e:
        print(f"Subprocess error: {e.stderr}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"An unexpected error occurred: {str(e)}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    show_speed()
