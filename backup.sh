#!/usr/bin/env bash

set -euo pipefail

# ---------------------------------------------------------------------------
# backup.sh — create a timestamped tar.gz backup of a folder and prune old
# backups beyond a maximum count.
#
# Usage: ./backup.sh <source_folder> <backup_dest> <max_backups>
# ---------------------------------------------------------------------------

usage() {
    echo "Usage: $0 <source_folder> <backup_dest> <max_backups>"
    echo ""
    echo "  source_folder  Path to the folder to back up"
    echo "  backup_dest    Directory where backups will be stored"
    echo "  max_backups    Maximum number of backups to keep (must be >= 1)"
    exit 1
}

# --- Validate arguments ----------------------------------------------------

if [[ $# -ne 3 ]]; then
    echo "Error: Expected 3 arguments, got $#." >&2
    usage
fi

SOURCE="$1"
DEST="$2"
MAX="$3"

# Strip any trailing slash from source so basename works correctly
SOURCE="${SOURCE%/}"

if [[ ! -d "$SOURCE" ]]; then
    echo "Error: Source folder '$SOURCE' does not exist or is not a directory." >&2
    exit 1
fi

if ! [[ "$MAX" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: max_backups must be a positive integer, got '$MAX'." >&2
    exit 1
fi

# --- Prepare destination ---------------------------------------------------

if [[ ! -d "$DEST" ]]; then
    echo "Destination '$DEST' does not exist. Creating it..."
    mkdir -p "$DEST"
fi

# --- Create backup ---------------------------------------------------------

PREFIX="$(basename "$SOURCE")"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
ARCHIVE_NAME="${PREFIX}_${TIMESTAMP}.tar.gz"
ARCHIVE_PATH="${DEST}/${ARCHIVE_NAME}"

echo "Backing up '$SOURCE' -> '$ARCHIVE_PATH' ..."

# -C changes into the parent directory so the archive contains only the
# folder itself (not the full absolute path).
if ! tar -czf "$ARCHIVE_PATH" -C "$(dirname "$SOURCE")" "$PREFIX"; then
    echo "Error: tar failed. Removing incomplete archive." >&2
    rm -f "$ARCHIVE_PATH"
    exit 1
fi

echo "Backup created: $ARCHIVE_NAME"

# --- Prune old backups -----------------------------------------------------

# Collect backups for this prefix, sorted newest-first (ls -t).
mapfile -t BACKUPS < <(ls -t "${DEST}/${PREFIX}_"*.tar.gz 2>/dev/null)

TOTAL=${#BACKUPS[@]}

if [[ $TOTAL -gt $MAX ]]; then
    DELETE_COUNT=$(( TOTAL - MAX ))
    echo "Pruning $DELETE_COUNT old backup(s) (keeping $MAX of $TOTAL)..."
    # The oldest files are at the end of the array.
    for (( i = MAX; i < TOTAL; i++ )); do
        echo "  Removing '${BACKUPS[$i]}'"
        rm -f "${BACKUPS[$i]}"
    done
else
    echo "Backup count is $TOTAL of $MAX max — no pruning needed."
fi

echo "Done."
