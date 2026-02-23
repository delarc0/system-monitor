#!/usr/bin/env python3
"""System Monitor — macOS menu bar app for CPU, GPU, memory, and network stats."""

import signal
import sys

from AppKit import NSApplication, NSApplicationActivationPolicyAccessory
from PyObjCTools import AppHelper

from tray import Tray
from monitor import Monitor
from config import Config


def main():
    app = NSApplication.sharedApplication()
    app.setActivationPolicy_(NSApplicationActivationPolicyAccessory)

    config = Config()
    monitor = Monitor(config)
    tray = Tray(monitor, config)

    monitor.start()
    tray.setup()

    # Allow Ctrl-C to quit
    signal.signal(signal.SIGINT, lambda *_: AppHelper.stopEventLoop())

    AppHelper.runEventLoop()


if __name__ == "__main__":
    main()
