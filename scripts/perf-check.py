#!/usr/bin/env python3
"""What Calm costs when nothing needs it to work: headless self-tests of the Debug app, each
measured with the kernel's own counters for the process (proc_pid_rusage) and held to a budget.

Retired instructions and interrupt wakeups are measured rather than CPU time: on a busy Mac the
same run took 3% to 13% of a core depending on which cores it landed on and how fast they ran,
while its instruction count stayed within a few percent (DESIGNS.md → Testing). A budget sits
well above what a run costs today and well below what the regressions it guards against cost:

- idle: an idle, focused shell. The cursor glide's animation loop running all the time
  (`custom-shader-animation = true`, before engine patch 0014) made this 940 wakeups a second.
- unseen: three working agents with the window out of sight. Their marks and the working light
  ticking anyway (before WindowPresence) cost about 300 M instructions a second.
- seen: the same three agents in view, measured without a budget, to watch the trend.

Usage: scripts/perf-check.py [scenario ...]   (after `mise run build`; about 35 s a scenario)
Exits 1 if any budget is exceeded.
"""

import ctypes
import os
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SELFTEST = os.path.join(ROOT, "scripts", "selftest.sh")
STANDIN = os.path.join(ROOT, "scripts", "fixtures", "agent-standin.sh")
APP = os.path.join(ROOT, "build", "DerivedData", "Build", "Products", "Debug", "Calm.app", "Contents", "MacOS", "Calm")

SETTLE = 10  # seconds after launch before measuring: startup reads state, indexes, lays out
MEASURE = 15

agent = f"bash {STANDIN} claude"
three_agents = ",".join([
    "calm.report:working",
    "calm.new_session", f"calm.type:{agent}", "calm.report:working",
    "calm.new_session", f"calm.type:{agent}", "calm.report:working",
])

# name: (typed command, actions after typing, budget: (M instructions/s, wakeups/s) or None)
SCENARIOS = {
    "idle": ("true", "calm.new_session", (40, 60)),
    "unseen": (agent, three_agents + ",calm.window_unseen", (40, 80)),
    "seen": (agent, three_agents, None),
}


class RUsage(ctypes.Structure):
    """rusage_info_v4 (<sys/resource.h>), as far as the fields read here."""

    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [
        (name, ctypes.c_uint64)
        for name in (
            "user_time", "system_time", "pkg_idle_wkups", "interrupt_wkups", "pageins", "wired_size",
            "resident_size", "phys_footprint", "proc_start_abstime", "proc_exit_abstime", "child_user_time",
            "child_system_time", "child_pkg_idle_wkups", "child_interrupt_wkups", "child_pageins",
            "child_elapsed_abstime", "diskio_bytesread", "diskio_byteswritten", "cpu_time_qos_default",
            "cpu_time_qos_maintenance", "cpu_time_qos_background", "cpu_time_qos_utility",
            "cpu_time_qos_legacy", "cpu_time_qos_user_initiated", "cpu_time_qos_user_interactive",
            "billed_system_time", "serviced_system_time", "logical_writes", "lifetime_max_phys_footprint",
            "instructions", "cycles", "billed_energy", "serviced_energy", "interval_max_phys_footprint",
            "runnable_time",
        )
    ]


libc = ctypes.CDLL("/usr/lib/libSystem.dylib")


class Timebase(ctypes.Structure):
    _fields_ = [("numer", ctypes.c_uint32), ("denom", ctypes.c_uint32)]


timebase = Timebase()
libc.mach_timebase_info(ctypes.byref(timebase))


def counters(pid):
    info = RUsage()
    if libc.proc_pid_rusage(pid, 4, ctypes.byref(info)) != 0:  # RUSAGE_INFO_V4
        raise RuntimeError(f"can't read the counters of pid {pid}")
    return info


def calm_under(driver):
    """The Debug Calm selftest.sh started: its child, not another session's run."""
    for _ in range(40):
        found = subprocess.run(["pgrep", "-P", str(driver), "-f", APP], capture_output=True, text=True).stdout.split()
        if found:
            return int(found[0])
        time.sleep(0.25)
    raise RuntimeError("the Debug Calm didn't start (run `mise run build` first?)")


def run(name, typed, after, out, home):
    env = dict(os.environ, CALM_SELFTEST_OUT=out, CFFIXED_USER_HOME=home)
    with open(os.path.join(out, f"{name}.driver.txt"), "w") as log:
        driver = subprocess.Popen(
            [SELFTEST, f"perf-{name}", "--type", typed, "--after", after, "--delay", str(SETTLE + MEASURE + 5)],
            env=env, stdout=log, stderr=subprocess.STDOUT,
        )
    try:
        pid = calm_under(driver.pid)
        time.sleep(SETTLE)
        before, start = counters(pid), time.monotonic()
        time.sleep(MEASURE)
        after_counters, seconds = counters(pid), time.monotonic() - start
    finally:
        driver.wait()
    cpu = (after_counters.user_time + after_counters.system_time - before.user_time - before.system_time)
    cpu_ns = cpu * timebase.numer / timebase.denom
    return {
        "instructions": (after_counters.instructions - before.instructions) / seconds / 1e6,
        "wakeups": (after_counters.interrupt_wkups - before.interrupt_wkups) / seconds,
        "cpu": 100 * cpu_ns / 1e9 / seconds,
    }


def main(names):
    if not os.path.exists(APP):
        sys.exit("no Debug build: run `mise run build` first")
    unknown = [n for n in names if n not in SCENARIOS]
    if unknown:
        sys.exit(f"unknown scenario {', '.join(unknown)}; known: {', '.join(SCENARIOS)}")
    out = tempfile.mkdtemp(prefix="calm-perf-")
    home = os.path.join(out, "home")  # agents' folders stay empty: nothing real is read
    os.makedirs(home)
    failed = False
    print(f"{'scenario':<8} {'M instr/s':>10} {'wakeups/s':>10} {'CPU':>7}   budget")
    for name in names or list(SCENARIOS):
        typed, after, budget = SCENARIOS[name]
        result = run(name, typed, after, out, home)
        verdict = "(no budget)"
        if budget:
            over = result["instructions"] > budget[0] or result["wakeups"] > budget[1]
            failed |= over
            verdict = f"{'OVER' if over else 'ok'}  (at most {budget[0]} M instr/s, {budget[1]} wakeups/s)"
        print(f"{name:<8} {result['instructions']:>10.1f} {result['wakeups']:>10.1f} {result['cpu']:>6.1f}%   {verdict}")
    print(f"logs: {out}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
