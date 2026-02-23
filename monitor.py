"""Background monitor thread — polls metrics and pushes snapshots to a callback."""

import threading
import time

import cpu
import gpu
import memory
import network


class Monitor:
    def __init__(self, config):
        self._config = config
        self._interval = config.get("update_interval", 2)
        self._running = False
        self._thread = None
        self._lock = threading.Lock()
        self._snapshot = {}
        self._callbacks = []

        # Prime psutil's cpu_percent (first call always returns 0)
        import psutil
        psutil.cpu_percent(percpu=True)

    def start(self):
        self._running = True
        self._thread = threading.Thread(target=self._poll_loop, daemon=True)
        self._thread.start()

    def stop(self):
        self._running = False

    def on_update(self, callback):
        """Register a callback(snapshot) to be called on each poll."""
        self._callbacks.append(callback)

    @property
    def snapshot(self):
        with self._lock:
            return dict(self._snapshot)

    def _poll_loop(self):
        while self._running:
            snap = {
                "cpu": cpu.sample(),
                "gpu": gpu.sample(),
                "memory": memory.sample(),
                "network": network.sample(),
                "processes": cpu.top_processes(5),
            }

            with self._lock:
                self._snapshot = snap

            for cb in self._callbacks:
                try:
                    cb(snap)
                except Exception:
                    pass

            time.sleep(self._interval)
