#!/bin/bash

#############################################
# Installation & Setup Script
#############################################

echo "=== Social Threat Intelligence System - Installation ==="

# Check required dependencies
echo "Checking dependencies..."

dependencies=("curl" "jq" "bc" "awk" "sed" "date")
missing_deps=()

for dep in "${dependencies[@]}"; do
    if ! command -v "${dep}" &> /dev/null; then
        missing_deps+=("${dep}")
    fi
done

if [[ ${#missing_deps[@]} -gt 0 ]]; then
    echo "Missing dependencies: ${missing_deps[*]}"
    echo "Installing..."
    
    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y "${missing_deps[@]}"
    elif command -v yum &> /dev/null; then
        sudo yum install -y "${missing_deps[@]}"
    elif command -v brew &> /dev/null; then
        brew install "${missing_deps[@]}"
    else
        echo "Please manually install: ${missing_deps[*]}"
        exit 1
    fi
fi

# Make scripts executable
echo "Setting permissions..."
chmod +x main.sh
chmod +x modules/*.sh
chmod +x utils/*.sh

# Create directories
echo "Creating directory structure..."
mkdir -p data/{profiles,trends,reports,cache}
mkdir -p logs

# Setup configuration
echo "Setting up configuration..."
if [[ ! -f config/config.sh ]]; then
    cp config/config.sh.example config/config.sh 2>/dev/null || true
fi

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "1. Edit config/config.sh and add your API keys"
echo "2. Review and customize config/threat_keywords.txt"
echo "3. Run: ./main.sh"
echo ""
