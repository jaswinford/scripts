#!/bin/bash

# Check if the input file argument is provided
if [ $# -ne 1 ]; then
  echo "Usage: $0 <input_file>"
  exit 1
fi

input_file="$1"

# Check if the input file exists
if [ ! -f "$input_file" ]; then
  echo "Error: Input file '$input_file' not found."
  exit 1
fi

# Derive the output file name from the input file name
output_file="${input_file%.*}.csv" #removes extension and adds .csv

# Domain to append
domain="iel.local"

# Clear the output file if it exists
> "$output_file"

# Loop through each line in the input file
while IFS= read -r hostname; do
  # Resolve the IP address using 'host' or 'nslookup'
  # 'host' is generally preferred, but 'nslookup' might be necessary in some environments.
  # If host failed, try nslookup, and if nslookup failed, print error message.
  ip=$(host "$hostname.$domain" | awk '{print $4}' 2>/dev/null)

  if [ -z "$ip" ]; then
    ip=$(nslookup "$hostname.$domain" | awk '/Address: / {print $2}' 2>/dev/null)
  fi

  if [ -z "$ip" ]; then
    echo "Error resolving IP for $hostname.$domain"
    echo "$hostname.$domain,Error resolving IP" >> "$output_file"
  else
    # Output the hostname and IP address in CSV format
    echo "$hostname.$domain,$ip" >> "$output_file"
  fi
done < "$input_file"

echo "Hostname and IP addresses written to '$output_file'."
