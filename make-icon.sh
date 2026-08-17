#!/bin/bash
# Regenerates AppIcon.icns from chud.png. Run this only when the source art changes;
# build.sh just copies the committed .icns.
set -euo pipefail
cd "$(dirname "$0")"

swift make-icon.swift
iconutil -c icns AppIcon.iconset -o AppIcon.icns
rm -rf AppIcon.iconset

echo "Built AppIcon.icns ($(du -h AppIcon.icns | cut -f1))"
