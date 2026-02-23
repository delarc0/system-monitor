"""CPU metrics: overall %, per-core %, P/E core split, top processes."""

import subprocess
import psutil


def _get_core_layout():
    """Return (p_core_count, e_core_count) on Apple Silicon."""
    try:
        p = subprocess.run(
            ["sysctl", "-n", "hw.perflevel0.logicalcpu"],
            capture_output=True, text=True, timeout=2,
        )
        p_cores = int(p.stdout.strip()) if p.returncode == 0 else 0
    except Exception:
        p_cores = 0

    try:
        e = subprocess.run(
            ["sysctl", "-n", "hw.perflevel1.logicalcpu"],
            capture_output=True, text=True, timeout=2,
        )
        e_cores = int(e.stdout.strip()) if e.returncode == 0 else 0
    except Exception:
        e_cores = 0

    if p_cores == 0 and e_cores == 0:
        # Fallback: treat all cores as P-cores (Intel or unknown)
        p_cores = psutil.cpu_count(logical=True)
    return p_cores, e_cores


# Cache the layout — it doesn't change at runtime
P_CORES, E_CORES = _get_core_layout()


def sample():
    """Return a CPU snapshot dict."""
    per_core = psutil.cpu_percent(percpu=True)
    overall = psutil.cpu_percent()

    # Split per-core into P and E groups
    # macOS reports P-cores first, then E-cores
    p_core_pcts = per_core[:P_CORES]
    e_core_pcts = per_core[P_CORES:P_CORES + E_CORES] if E_CORES else []

    return {
        "overall": overall,
        "per_core": per_core,
        "p_cores": p_core_pcts,
        "e_cores": e_core_pcts,
        "p_count": P_CORES,
        "e_count": E_CORES,
    }


def top_processes(n=5):
    """Return top N processes by CPU usage: [(name, cpu%), ...]."""
    procs = []
    for p in psutil.process_iter(["name", "cpu_percent"]):
        try:
            info = p.info
            if info["cpu_percent"] and info["cpu_percent"] > 0:
                procs.append((info["name"], info["cpu_percent"]))
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue

    procs.sort(key=lambda x: x[1], reverse=True)
    return procs[:n]
