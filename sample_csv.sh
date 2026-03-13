#!/usr/bin/env bash

set -euo pipefail

usage() {
    echo "Usage: $(basename "$0") <file.csv> <count>"
    echo "  file.csv  Path to the input CSV file"
    echo "  count     Number of rows to randomly sample"
    exit 1
}

if [[ $# -ne 2 ]]; then
    usage
fi

file="$1"
count="$2"

if [[ ! -f "$file" ]]; then
    echo "Error: file not found: $file" >&2
    exit 1
fi

if ! [[ "$count" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: count must be a positive integer, got: $count" >&2
    exit 1
fi

# Print header
head -n 1 "$file"

# Sample random rows from the body (excluding header)
tail -n +2 "$file" | shuf -n "$count"
