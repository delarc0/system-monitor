"""User configuration — JSON stored in ~/Library/Application Support/SystemMonitor/."""

import json
import os

_APP_DIR = os.path.expanduser("~/Library/Application Support/SystemMonitor")
_CONFIG_PATH = os.path.join(_APP_DIR, "config.json")

_DEFAULTS = {
    "update_interval": 2,       # seconds
    "menu_bar_display": "cpu",  # "cpu", "cpu+mem", "cpu+gpu", "all"
    "show_sparkline": False,
    "launch_on_login": False,
}


class Config:
    def __init__(self):
        self._data = dict(_DEFAULTS)
        self._load()

    def _load(self):
        if os.path.exists(_CONFIG_PATH):
            try:
                with open(_CONFIG_PATH) as f:
                    saved = json.load(f)
                self._data.update(saved)
            except Exception:
                pass

    def save(self):
        os.makedirs(_APP_DIR, exist_ok=True)
        with open(_CONFIG_PATH, "w") as f:
            json.dump(self._data, f, indent=2)

    def get(self, key, default=None):
        return self._data.get(key, default)

    def set(self, key, value):
        self._data[key] = value
        self.save()