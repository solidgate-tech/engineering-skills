#!/usr/bin/env python3
"""Working hours (Mon-Fri, local time; default 09:00-18:00) elapsed since an ISO timestamp.

Env: MR_TOOLKIT_WORK_HOURS="9-18" sets the working day (whole hours, local time).

Usage: working_hours.py 2026-09-28T14:05:00Z   -> prints e.g. 6.9
       working_hours.py --self-test
"""
import os
import sys
from datetime import datetime, timedelta

START, END = map(int, os.environ.get("MR_TOOLKIT_WORK_HOURS", "9-18").split("-"))  # ponytail: no holidays; add a calendar if nudges misfire


def working_hours(since, now):
    total, day = 0.0, since.replace(hour=0, minute=0, second=0, microsecond=0)
    while day <= now:
        if day.weekday() < 5:
            lo = max(since, day.replace(hour=START))
            hi = min(now, day.replace(hour=END))
            total += max(0.0, (hi - lo).total_seconds() / 3600)
        day += timedelta(days=1)
    return total


def self_test():
    fri_17 = datetime(2026, 9, 25, 17, 0)
    assert working_hours(fri_17, datetime(2026, 9, 28, 10, 0)) == 2.0  # 1h Fri + 1h Mon, weekend skipped
    assert working_hours(datetime(2026, 9, 28, 20, 0), datetime(2026, 9, 29, 12, 0)) == 3.0  # after hours → next morning
    assert working_hours(datetime(2026, 9, 29, 12, 0), datetime(2026, 9, 29, 11, 0)) == 0.0  # future timestamp
    print("ok")


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        self_test()
    else:
        since = datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00")).astimezone().replace(tzinfo=None)
        print(round(working_hours(since, datetime.now()), 1))
