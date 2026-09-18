#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/portable
swiftc -o .build/portable/core-checks Sources/MrCalenderCore/*.swift Tests/Portable/ICSChecks.swift Tests/Portable/main.swift
.build/portable/core-checks
