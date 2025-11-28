#!/bin/bash
# Convert AKWF waveform data from C header files to JSON files
# Outputs one JSON file per bank plus a manifest.json
#
# Usage: ./convert.sh [path-to-AKWF-c-directory]
#
# Adventure Kid Waveforms(AKWF) Open waveforms library
# https://www.adventurekid.se/akrt/waveforms/adventure-kid-waveforms/
#
# This code is in the public domain, CC0 1.0 Universal (CC0 1.0)
# https://creativecommons.org/publicdomain/zero/1.0/

set -e

WORK_DIR="${1:-.}"
OUTPUT_DIR="$(dirname "$0")"

# Validate working directory exists
if [ ! -d "$WORK_DIR" ]; then
    echo "Error: Directory '$WORK_DIR' not found" >&2
    exit 1
fi

# Check for .h files before proceeding
if ! find "$WORK_DIR" -name "*.h" -type f | grep -q .; then
    echo "Error: No .h files found in '$WORK_DIR'" >&2
    exit 1
fi

# Function to process a single file and normalize values
process_file() {
    local file="$1"
    grep -A 300 "AKWF_[0-9a-zA-Z_]* \[\] = {" "$file" | \
        sed -n '/\[\] = {/,/};/p' | \
        sed 's/^const.*\[\] = {//; s/};$//' | \
        tr -d ',' | \
        tr '\n' ' ' | \
        sed 's/^ *//;s/ *$//' | \
        tr -s ' ' | \
        awk '{
            for (i=1; i<=NF; i++) {
                # Convert from unsigned (0-65535) to signed (-1 to 1) range
                printf "%.6f", ($i - 32768)/32768
                if (i < NF) printf ","
            }
        }'
}

# Track bank names for manifest
bank_names=()
bank_count=0

# Find and process AKWF_* directories
for dir in $(find "$WORK_DIR" -maxdepth 1 -type d -name "AKWF_*" | sort -V); do
    dir_name=$(basename "$dir")
    bank_names+=("\"$dir_name\"")

    echo "Processing $dir_name..." >&2

    output_file="$OUTPUT_DIR/$dir_name.json"

    # Start the JSON object
    echo "{" > "$output_file"

    # Process all .h files in this directory
    first_file=true
    for file in "$dir"/*.h; do
        if [ -f "$file" ]; then
            data=$(process_file "$file")

            if [ ! -z "$data" ]; then
                # Get filename without path and .h extension
                filename=$(basename "$file" .h)

                # Add comma for all but first entry
                if [ "$first_file" = true ]; then
                    first_file=false
                else
                    echo "," >> "$output_file"
                fi

                # Write key-value pair for this waveform
                echo -n "  \"$filename\": [$data]" >> "$output_file"
            fi
        fi
    done

    # Close the JSON object
    echo "" >> "$output_file"
    echo "}" >> "$output_file"

    ((bank_count++))
done

# Check that we actually generated some banks
if [ $bank_count -eq 0 ]; then
    echo "Error: No waveforms were generated" >&2
    exit 1
fi

# Generate manifest.json
manifest_file="$OUTPUT_DIR/manifest.json"
echo "{" > "$manifest_file"
echo "  \"banks\": [" >> "$manifest_file"

# Join bank names with commas
first=true
for name in "${bank_names[@]}"; do
    if [ "$first" = true ]; then
        first=false
        echo -n "    $name" >> "$manifest_file"
    else
        echo "," >> "$manifest_file"
        echo -n "    $name" >> "$manifest_file"
    fi
done

echo "" >> "$manifest_file"
echo "  ]" >> "$manifest_file"
echo "}" >> "$manifest_file"

echo "Generated $bank_count bank files and manifest.json in $OUTPUT_DIR" >&2
