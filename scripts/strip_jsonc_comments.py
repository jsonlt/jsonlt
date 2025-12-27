#!/usr/bin/env python3
"""Strip // and /* */ comments from JSONC files."""

import re
import sys


def strip_comments(jsonc_text: str) -> str:
    """Strip // and /* */ comments from JSONC, preserving content in strings."""
    result = []
    i = 0
    in_string = False
    escape_next = False

    while i < len(jsonc_text):
        char = jsonc_text[i]

        if escape_next:
            result.append(char)
            escape_next = False
            i += 1
            continue

        if char == "\\" and in_string:
            result.append(char)
            escape_next = True
            i += 1
            continue

        if char == '"' and not escape_next:
            in_string = not in_string
            result.append(char)
            i += 1
            continue

        if not in_string:
            # Check for // comment
            if jsonc_text[i : i + 2] == "//":
                # Skip until end of line
                while i < len(jsonc_text) and jsonc_text[i] != "\n":
                    i += 1
                continue

            # Check for /* */ comment
            if jsonc_text[i : i + 2] == "/*":
                # Skip until */
                i += 2
                while i < len(jsonc_text) - 1:
                    if jsonc_text[i : i + 2] == "*/":
                        i += 2
                        break
                    i += 1
                continue

        result.append(char)
        i += 1

    return "".join(result)


if __name__ == "__main__":
    content = sys.stdin.read()
    print(strip_comments(content))
