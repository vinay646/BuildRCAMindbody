#!/usr/bin/env python3
"""CREATES a test quote "MR103 ramp probe" (Starter + Payments, 12 months) and ramps Starter 3 + 9 months (standard APIs)."""
import json, os, subprocess, time
exec(open("scripts/usage/mr103_test.py").read().split("# MR-103 AC2")[0])
exec(open("scripts/usage/ramp_lib.py").read())
qt = case("ramp probe", "probe", 12, [("MB-STR", "Term Monthly"), ("MB-PAY", "Evergreen Monthly")], None)
ramp(qt["Id"], TODAY, 3, 12, ["MB-STR"])
show(qt["Id"])
