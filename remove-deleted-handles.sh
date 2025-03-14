#!/bin/bash

# Script to attempt to free up file handles by deleting entries in /proc.
# WARNING: This is a risky operation and can cause process instability or crashes.
# Use with extreme caution and at your own risk.

# Check if lsof is installed
if ! command -v lsof &> /dev/null; then
  echo "lsof could not be found. Please install it."
  exit 1
fi

# Check if xargs is installed
if ! command -v xargs &> /dev/null; then
  echo "xargs could not be found. Please install it."
  exit 1
fi

# Find processes with deleted files open, and get the file descriptor.
lsof +L1 2>/dev/null | grep '(deleted)' | grep /var/log/apache | awk '{split($4, a, /[^0-9]/); print $2, a[1], $10}' | while read pid fd filepath; do
  proc_path="/proc/$pid/fd/$fd"

  if [[ -e "$proc_path" ]]; then
    echo "Attempting to remove: $proc_path (PID: $pid, FD: $fd, File: $filepath)"
    truncate -s0 $proc_path
    if [[ $? -eq 0 ]]; then
      echo "Successfully removed: $proc_path"
    else
      echo "Failed to remove: $proc_path"
    fi

  else
    echo "Warning: $proc_path does not exist. (PID: $pid, FD: $fd, File: $filepath)"
  fi
done

echo "Finished attempting to remove /proc entries."

exit 0
