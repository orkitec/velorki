#!/usr/bin/env python3
"""Find things in a `uiautomator dump`, for tool/screenshots.sh.

    ui.py find <dump.xml> <regex> [nth]   "cx cy x1 y1 x2 y2" of the nth match
    ui.py grep <dump.xml> <regex>         the first matching label itself
    ui.py class <dump.xml> <class> [nth]  "cx cy x1 y1 x2 y2" of the nth node
                                          of that class (a text field whose
                                          hint the dump leaves out)
    ui.py slot <dump.xml> <regex> <label> "x y" of <label> in the first node
                                          matching <regex>: a row of buttons
                                          Flutter merged into one node, one
                                          label per line, equally wide

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
    if command == "slot":
        expression = re.compile(pattern)
        for node, label in labelled(path):
            if not expression.search(label):
                continue
            items = label.split("\n")
            if sys.argv[4] not in items:
                continue
            i, n = items.index(sys.argv[4]), len(items)
            x1, y1, x2, y2 = map(int, re.findall(r"-?\d+", node.get("bounds")))
            print(f"{x1 + (x2 - x1) * (2 * i + 1) // (2 * n)} {y1 + (y2 - y1) * 35 // 100}")
            return
        sys.exit(1)
    if command == "class":
        nodes = [n for n in ET.parse(path).getroot().iter("node")
                 if n.get("class") == pattern]
        hits = [(n, "") for n in nodes]
    else:
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
