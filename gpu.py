"""GPU metrics via ioreg (no sudo required on Apple Silicon)."""

import subprocess
import re


def sample():
    """Return GPU utilization % from AGXAccelerator, or None if unavailable."""
    try:
        result = subprocess.run(
            ["ioreg", "-r", "-d", "1", "-c", "AGXAccelerator"],
            capture_output=True, text=True, timeout=3,
        )
        if result.returncode != 0:
            return {"utilization": None}

        # Look for "gpu-utilization-%" or "gpu-core-utilization-%"
        # Different M-series chips report slightly differently
        output = result.stdout

        match = re.search(r'"gpu-core-utilization-%"\s*=\s*(\d+)', output)
        if not match:
            match = re.search(r'"gpu-utilization-%"\s*=\s*(\d+)', output)

        if match:
            return {"utilization": int(match.group(1))}

        # Fallback: try parsing "performanceStatistics" block
        match = re.search(
            r'"Device Utilization %"\s*=\s*(\d+)', output
        )
        if match:
            return {"utilization": int(match.group(1))}

        return {"utilization": None}

    except Exception:
        return {"utilization": None}
