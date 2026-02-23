"""Memory metrics: RAM usage, swap, pressure."""

import psutil


def sample():
    """Return memory snapshot dict."""
    vm = psutil.virtual_memory()
    sw = psutil.swap_memory()

    return {
        "total_gb": round(vm.total / (1024 ** 3), 1),
        "used_gb": round(vm.used / (1024 ** 3), 1),
        "available_gb": round(vm.available / (1024 ** 3), 1),
        "percent": vm.percent,
        "swap_total_gb": round(sw.total / (1024 ** 3), 1),
        "swap_used_gb": round(sw.used / (1024 ** 3), 1),
        "swap_percent": sw.percent,
        "pressure": _pressure_level(vm.percent),
    }


def _pressure_level(percent):
    """Return pressure label based on usage %."""
    if percent < 60:
        return "normal"
    elif percent < 80:
        return "warning"
    else:
        return "critical"
