#!/usr/bin/env python3
"""Find things in a `uiautomator dump`, for tool/screenshots.sh.

    ui.py find <dump.xml> <regex> [nth]   "cx cy x1 y1 x2 y2" of the nth match
    ui.py grep <dump.xml> <regex>         the first matching label itself

A node is matched on its content-desc, its text and its hint. Flutter merges a
row of buttons into one semantics node, so a match is often a whole row: the
caller taps a fraction of the node's width. `.` does not match the newline
Flutter puts between a node's own label and its children's.
"""
import re
import sys
import xml.etree.ElementTree as ET


def labelled(path):
    for node in ET.parse(path).getroot().iter("node"):
        for field in ("content-desc", "text", "hint"):
            value = node.get(field)
            if value:
                yield node, value


def main():
    command, path, pattern = sys.argv[1:4]
    expression = re.compile(pattern)
    hits = []
    for node, label in labelled(path):
        if expression.search(label):
            hits.append((node, label))
    if command == "grep":
        for _, label in hits:
            for line in label.split("\n"):
                if expression.search(line):
                    print(line)
                    return
        sys.exit(1)
    nth = int(sys.argv[4]) if len(sys.argv) > 4 else 0
    # One node can match through two of its fields; keep it once.
    seen, unique = set(), []
    for node, _ in hits:
        bounds = node.get("bounds")
        if bounds in seen and node.get("class") == "android.view.View":
            continue
        seen.add(bounds)
        unique.append(node)
    if nth >= len(unique):
        sys.exit(1)
    x1, y1, x2, y2 = map(int, re.findall(r"-?\d+", unique[nth].get("bounds")))
    print(f"{(x1 + x2) // 2} {(y1 + y2) // 2} {x1} {y1} {x2} {y2}")


main()
