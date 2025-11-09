#!/bin/bash

# This script is sourced by 'bash -c' commands to load the full environment.

# SCRIPT_DIR is inherited because it was exported in config.sh
if [[ -z "${SCRIPT_DIR}" ]]; then
    echo "[ERROR] SCRIPT_DIR not set for subshell" >&2
    exit 1
fi

# Source all dependencies
source "${SCRIPT_DIR}/config/config.sh"
source "${SCRIPT_DIR}/utils/logger.sh"
source "${SCRIPT_DIR}/utils/reddit_api.sh"