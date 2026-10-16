#!/bin/sh
# Rebuild the browser build into web/ (Vercel serves it, vercel.json); then commit web/ and push.
cd "$(dirname "$0")/game" && "/c/Users/ferth/Downloads/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe" --headless --path . --export-release "Web" ../web/index.html
