"""Network metrics: upload/download speed from psutil deltas, with history."""

import time
from collections import deque
import psutil

_prev_counters = None
_prev_time = None

# Rolling history for graph (last 30 samples ~60s at 2s interval)
HISTORY_LEN = 30
download_history = deque([0.0] * HISTORY_LEN, maxlen=HISTORY_LEN)
upload_history = deque([0.0] * HISTORY_LEN, maxlen=HISTORY_LEN)


def sample():
    """Return network speed dict. First call returns zeros (needs a baseline)."""
    global _prev_counters, _prev_time

    counters = psutil.net_io_counters()
    now = time.monotonic()

    if _prev_counters is None or _prev_time is None:
        _prev_counters = counters
        _prev_time = now
        return {
            "download_bps": 0,
            "upload_bps": 0,
            "download_str": "0 B/s",
            "upload_str": "0 B/s",
            "download_history": list(download_history),
            "upload_history": list(upload_history),
        }

    dt = now - _prev_time
    if dt <= 0:
        dt = 1

    down_bps = (counters.bytes_recv - _prev_counters.bytes_recv) / dt
    up_bps = (counters.bytes_sent - _prev_counters.bytes_sent) / dt

    _prev_counters = counters
    _prev_time = now

    download_history.append(down_bps)
    upload_history.append(up_bps)

    return {
        "download_bps": down_bps,
        "upload_bps": up_bps,
        "download_str": _format_speed(down_bps),
        "upload_str": _format_speed(up_bps),
        "download_history": list(download_history),
        "upload_history": list(upload_history),
    }


def _format_speed(bps):
    """Format bytes/sec into human-readable string."""
    if bps >= 1024 ** 3:
        return f"{bps / (1024 ** 3):.1f} GB/s"
    elif bps >= 1024 ** 2:
        return f"{bps / (1024 ** 2):.1f} MB/s"
    elif bps >= 1024:
        return f"{bps / 1024:.1f} KB/s"
    else:
        return f"{bps:.0f} B/s"
