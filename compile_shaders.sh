#!/bin/bash

# Script to compile Metal shaders to .metallib format for use in Swift Package

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METAL_SOURCE="$SCRIPT_DIR/Sources/Filters/Shaders.metal"
OUTPUT_DIR="$SCRIPT_DIR/Sources/Filters"
OUTPUT_FILE="$OUTPUT_DIR/Shaders.metallib"

echo "Compiling Metal shader..."
echo "Source: $METAL_SOURCE"
echo "Output: $OUTPUT_FILE"

# Check if xcrun and metal compiler are available
if ! command -v xcrun &> /dev/null; then
    echo "Error: xcrun not found. Make sure Xcode is installed."
    exit 1
fi

# Compile Metal shader to AIR (Apple Intermediate Representation)
AIR_FILE="$OUTPUT_DIR/Shaders.air"
xcrun -sdk macosx metal -c "$METAL_SOURCE" -o "$AIR_FILE"

# Link AIR to metallib
xcrun -sdk macosx metallib "$AIR_FILE" -o "$OUTPUT_FILE"

# Clean up AIR file
rm "$AIR_FILE"

echo "✓ Metal shader compiled successfully to $OUTPUT_FILE"
