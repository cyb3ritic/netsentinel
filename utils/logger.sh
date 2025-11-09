#!/bin/bash

#############################################
# Logging Utilities
#############################################

# Ensure log directory exists
mkdir -p "${LOG_DIR}"

# Log levels
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3
readonly LOG_LEVEL_CRITICAL=4

# Current log level (set from config or default to INFO)
LOG_LEVEL=${LOG_LEVEL:-$LOG_LEVEL_INFO}

# Logging function
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local color=$3
    
    # Write to log file
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
    
    # Display to console with color
    echo -e "${color}[${level}]${NC} ${message}"
}

# Log debug message
log_debug() {
    [[ ${LOG_LEVEL} -le ${LOG_LEVEL_DEBUG} ]] && log_message "DEBUG" "$1" "${BLUE}"
}

# Log info message
log_info() {
    [[ ${LOG_LEVEL} -le ${LOG_LEVEL_INFO} ]] && log_message "INFO" "$1" "${GREEN}"
}

# Log warning message
log_warn() {
    [[ ${LOG_LEVEL} -le ${LOG_LEVEL_WARN} ]] && log_message "WARN" "$1" "${YELLOW}"
}

# Log error message
log_error() {
    [[ ${LOG_LEVEL} -le ${LOG_LEVEL_ERROR} ]] && log_message "ERROR" "$1" "${RED}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "${ERROR_LOG}"
}

# Log critical message
log_critical() {
    log_message "CRITICAL" "$1" "${RED}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CRITICAL] $1" >> "${ERROR_LOG}"
}

# Log success message
log_success() {
    log_message "SUCCESS" "$1" "${GREEN}"
}

# Log with custom level
log_custom() {
    local level=$1
    local message=$2
    log_message "${level}" "${message}" "${NC}"
}
