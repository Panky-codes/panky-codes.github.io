#!/usr/bin/env bash
# This script sets up the environment and runs the Jekyll server

# Check if we are already in a nix-shell
if [ -z "$IN_NIX_SHELL" ]; then
    echo "Entering Nix shell..."
    exec nix-shell --run "$0 $@"
fi

echo "Checking dependencies..."
bundle check || bundle install

echo "Starting Jekyll server..."
# Add --host 0.0.0.0 if you need to access it from another machine/VM
bundle exec jekyll serve --livereload
