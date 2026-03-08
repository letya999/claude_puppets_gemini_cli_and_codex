import speedtest
import json
import sys

def measure():
    """Measures internet speed and returns result as a dictionary."""
    try:
        st = speedtest.Speedtest()
        
        # Get best server based on ping
        st.get_best_server()
        
        # Measure download and upload speeds (in bits per second)
        st.download()
        st.upload()
        
        # Extract results
        results_dict = st.results.dict()
        
        # Get server information safely
        server_info = results_dict.get('server', {})
        server_name = server_info.get('name', 'Unknown')
        city = server_info.get('city', 'Unknown City')
        country = server_info.get('country', 'Unknown Country')
        location = f"{city}, {country}"
        
        # Format the data for JSON output
        output = {
            "download_mbps": round(results_dict.get('download', 0) / 1_000_000, 2),
            "upload_mbps": round(results_dict.get('upload', 0) / 1_000_000, 2),
            "ping_ms": round(results_dict.get('ping', 0), 2),
            "server": {
                "name": server_name,
                "location": location
            }
        }
        
        print(json.dumps(output))
        
    except Exception as e:
        error_output = {
            "error": str(e)
        }
        print(json.dumps(error_output), file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    measure()
