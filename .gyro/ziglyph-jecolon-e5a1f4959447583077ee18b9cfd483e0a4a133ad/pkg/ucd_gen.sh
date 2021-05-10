#!/bin/sh
if [ ! -d ./src/data/ucd ]; then
    echo "Creating directory structure..."
    mkdir -pv ./src/data/ucd
fi
cd ./src/data/ucd
if [ ! -f ./UCD.zip ]; then
    echo "Downloading Unicode Character Database..."
    wget -q https://www.unicode.org/Public/UCD/latest/ucd/UCD.zip
fi
echo "Extracting Unicode Character Database..."
unzip -qu UCD.zip
cd - > /dev/null
cd ./src
echo "Generating Zig code..."
./ucd_gen
cd - > /dev/null
echo "Done!"
