#!/bin/bash

#############################################
# API Request Handler with Rate Limiting
#############################################

# Rate limiting state
RATE_LIMIT_FILE="${CACHE_DIR}/rate_limit.dat"
mkdir -p "${CACHE_DIR}"

# Initialize rate limit tracker
init_rate_limiter() {
    if [[ ! -f "${RATE_LIMIT_FILE}" ]]; then
        echo "0:$(date +%s)" > "${RATE_LIMIT_FILE}"
    fi
}

# Check rate limit
check_rate_limit() {
    init_rate_limiter
    
    local current_time=$(date +%s)
    local rate_data=$(cat "${RATE_LIMIT_FILE}")
    local request_count=$(echo "${rate_data}" | cut -d: -f1)
    local window_start=$(echo "${rate_data}" | cut -d: -f2)
    local elapsed=$((current_time - window_start))
    
    if [[ ${elapsed} -ge ${RATE_LIMIT_WINDOW} ]]; then
        # Reset window
        echo "1:${current_time}" > "${RATE_LIMIT_FILE}"
        return 0
    fi
    
    if [[ ${request_count} -ge ${API_RATE_LIMIT} ]]; then
        local wait_time=$((RATE_LIMIT_WINDOW - elapsed))
        log_warn "Rate limit reached. Waiting ${wait_time} seconds..."
        sleep "${wait_time}"
        echo "1:$(date +%s)" > "${RATE_LIMIT_FILE}"
        return 0
    fi
    
    # Increment counter
    echo "$((request_count + 1)):${window_start}" > "${RATE_LIMIT_FILE}"
    return 0
}

# Make API request with error handling
api_request() {
    local method=$1
    local url=$2
    local data=$3
    local headers=$4
    
    check_rate_limit
    
    local response
    local http_code
    local temp_file=$(mktemp)
    
    log_debug "API Request: ${method} ${url}"
    
    if [[ "${method}" == "GET" ]]; then
        http_code=$(curl -s -w "%{http_code}" -o "${temp_file}" \
            -X GET \
            -H "Authorization: Bearer ${TWITTER_BEARER_TOKEN}" \
            -H "User-Agent: ${USER_AGENT}" \
            --connect-timeout "${CURL_TIMEOUT}" \
            "${url}")
    elif [[ "${method}" == "POST" ]]; then
        http_code=$(curl -s -w "%{http_code}" -o "${temp_file}" \
            -X POST \
            -H "Authorization: Bearer ${TWITTER_BEARER_TOKEN}" \
            -H "Content-Type: application/json" \
            -H "User-Agent: ${USER_AGENT}" \
            --connect-timeout "${CURL_TIMEOUT}" \
            -d "${data}" \
            "${url}")
    fi
    
    response=$(cat "${temp_file}")
    rm -f "${temp_file}"
    
    # Handle HTTP errors
    case ${http_code} in
        200|201)
            echo "${response}"
            return 0
            ;;
        429)
            log_error "Rate limit exceeded (HTTP 429)"
            return 1
            ;;
        401|403)
            log_error "Authentication failed (HTTP ${http_code})"
            return 1
            ;;
        404)
            log_warn "Resource not found (HTTP 404)"
            return 1
            ;;
        500|502|503)
            log_error "Server error (HTTP ${http_code})"
            return 1
            ;;
        *)
            log_error "Unexpected HTTP code: ${http_code}"
            return 1
            ;;
    esac
}

# Fetch user profile data
fetch_user_profile() {
    local username=$1
    local url="https://api.twitter.com/2/users/by/username/${username}?user.fields=created_at,description,public_metrics,verified,profile_image_url"
    
    api_request "GET" "${url}"
}

# Fetch user tweets
fetch_user_tweets() {
    local user_id=$1
    local max_results=${2:-100}
    local url="https://api.twitter.com/2/users/${user_id}/tweets?max_results=${max_results}&tweet.fields=created_at,public_metrics,entities"
    
    api_request "GET" "${url}"
}

# Search tweets by keyword/hashtag
search_tweets() {
    local query=$1
    local max_results=${2:-100}
    local encoded_query=$(echo "${query}" | jq -sRr @uri)
    local url="https://api.twitter.com/2/tweets/search/recent?query=${encoded_query}&max_results=${max_results}&tweet.fields=created_at,author_id,public_metrics,entities"
    
    api_request "GET" "${url}"
}

# Fetch user followers
fetch_followers() {
    local user_id=$1
    local max_results=${2:-100}
    local url="https://api.twitter.com/2/users/${user_id}/followers?max_results=${max_results}&user.fields=created_at,public_metrics"
    
    api_request "GET" "${url}"
}

# Fetch user following
fetch_following() {
    local user_id=$1
    local max_results=${2:-100}
    local url="https://api.twitter.com/2/users/${user_id}/following?max_results=${max_results}&user.fields=created_at,public_metrics"
    
    api_request "GET" "${url}"
}
