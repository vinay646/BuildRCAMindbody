#!/usr/bin/env python3
"""CREATES a test quote "MR103 ramp probe": Payments, ramp 3 + 9 months, then Starter added to segment 1."""
import json, os, subprocess, time
exec(open("scripts/usage/mr103_test.py").read().split("# MR-103 AC2")[0])
exec(open("scripts/usage/ramp_lib.py").read())
qt = case("ramp probe", "probe", 12, [("MB-PAY", "Evergreen Monthly")], None)
ramp_then_add(qt["Id"], TODAY, 3, 12, "MB-STR", "Term Monthly", PB, LE)
show(qt["Id"])
