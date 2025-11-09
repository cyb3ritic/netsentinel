#!/bin/bash

#############################################
# Configuration with .env Support
#############################################

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load environment variables from .env file
load_env_file() {
    local env_file="${SCRIPT_DIR}/.env"
    
    if [[ -f "${env_file}" ]]; then
        # Load .env file safely
        set -a  # Automatically export all variables
        source <(grep -v '^#' "${env_file}" | grep -v '^[[:space:]]*$' | sed 's/\r$//')
        set +a  # Stop auto-export
        
        echo "[INFO] Loaded environment variables from .env" >&2
    else
        echo "[WARN] .env file not found at ${env_file}" >&2
        echo "[WARN] Using default/fallback values" >&2
    fi
}

# Load .env file
load_env_file

# Directories
export SCRIPT_DIR
export DATA_DIR="${SCRIPT_DIR}/data"
export LOG_DIR="${SCRIPT_DIR}/logs"
export REPORT_DIR="${DATA_DIR}/reports"
export CACHE_DIR="${DATA_DIR}/cache"

# Log files
export LOG_FILE="${LOG_DIR}/system.log"
export ERROR_LOG="${LOG_DIR}/error.log"

# Reddit API Configuration (with fallbacks)
export REDDIT_CLIENT_ID="${REDDIT_CLIENT_ID:-your_client_id_here}"
export REDDIT_CLIENT_SECRET="${REDDIT_CLIENT_SECRET:-your_client_secret_here}"
export REDDIT_USERNAME="${REDDIT_USERNAME:-your_reddit_username}"
export REDDIT_PASSWORD="${REDDIT_PASSWORD:-your_reddit_password}"
export REDDIT_USER_AGENT="ThreatIntel/2.0 by ${REDDIT_USERNAME}"

# Reddit API endpoints
export REDDIT_OAUTH_URL="https://oauth.reddit.com"
export REDDIT_AUTH_URL="https://www.reddit.com/api/v1/access_token"

# Detection Thresholds (with fallbacks)
export FAKE_PROFILE_THRESHOLD="${FAKE_PROFILE_THRESHOLD:-75}"
export SCAM_CONFIDENCE_THRESHOLD="${SCAM_CONFIDENCE_THRESHOLD:-70}"
export NETWORK_ANOMALY_THRESHOLD="${NETWORK_ANOMALY_THRESHOLD:-65}"
export SUSPICIOUS_POST_RATE="${SUSPICIOUS_POST_RATE:-50}"

# Analysis Parameters
export MAX_ACCOUNT_AGE_DAYS="${MAX_ACCOUNT_AGE_DAYS:-30}"
export MIN_KARMA_RATIO="${MIN_KARMA_RATIO:-0.1}"
export SUSPICIOUS_LINK_PATTERNS=("bit.ly" "tinyurl" "goo.gl" "t.co" "rebrand.ly")

# Rate Limiting (Reddit: 100 req/min for OAuth)
export API_RATE_LIMIT="${API_RATE_LIMIT:-90}"
export RATE_LIMIT_WINDOW="${RATE_LIMIT_WINDOW:-60}"

# Monitored subreddits
export MONITORED_SUBREDDITS="${MONITORED_SUBREDDITS:-cryptocurrency,wallstreetbets,investing,technology}"

# Threat Keywords File
export THREAT_KEYWORDS_FILE="${SCRIPT_DIR}/config/threat_keywords.txt"

# User Agent
export USER_AGENT="${REDDIT_USER_AGENT}"

# Timeout settings
export CURL_TIMEOUT="${CURL_TIMEOUT:-30}"
export ANALYSIS_TIMEOUT="${ANALYSIS_TIMEOUT:-300}"

# Output format
export OUTPUT_FORMAT="${OUTPUT_FORMAT:-json}"

# Enable/Disable Modules
export ENABLE_PROFILE_ANALYSIS="${ENABLE_PROFILE_ANALYSIS:-true}"
export ENABLE_SUBREDDIT_MONITORING="${ENABLE_SUBREDDIT_MONITORING:-true}"
export ENABLE_SCAM_DETECTION="${ENABLE_SCAM_DETECTION:-true}"
export ENABLE_NETWORK_MAPPING="${ENABLE_NETWORK_MAPPING:-true}"

# Notification settings
export ENABLE_ALERTS="${ENABLE_ALERTS:-false}"
export ALERT_WEBHOOK_URL="${ALERT_WEBHOOK_URL:-}"
export ALERT_EMAIL="${ALERT_EMAIL:-}"

# Validate critical credentials
validate_credentials() {
    local errors=0
    
    if [[ "${REDDIT_CLIENT_ID}" == "your_client_id_here" ]]; then
        echo "[ERROR] REDDIT_CLIENT_ID not configured" >&2
        ((errors++))
    fi
    
    if [[ "${REDDIT_CLIENT_SECRET}" == "your_client_secret_here" ]]; then
        echo "[ERROR] REDDIT_CLIENT_SECRET not configured" >&2
        ((errors++))
    fi
    
    if [[ "${REDDIT_USERNAME}" == "your_reddit_username" ]]; then
        echo "[ERROR] REDDIT_USERNAME not configured" >&2
        ((errors++))
    fi
    
    if [[ "${REDDIT_PASSWORD}" == "your_reddit_password" ]]; then
        echo "[ERROR] REDDIT_PASSWORD not configured" >&2
        ((errors++))
    fi
    
    if [[ ${errors} -gt 0 ]]; then
        echo "[ERROR] Please configure your .env file with Reddit API credentials" >&2
        echo "[INFO] Copy .env.example to .env and fill in your credentials" >&2
        return 1
    fi
    
    return 0
}

# Only validate in interactive mode (not during sourcing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    validate_credentials
fi
