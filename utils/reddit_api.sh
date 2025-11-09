#!/bin/bash

#############################################
# Reddit API Handler with OAuth
#############################################

# Token management
TOKEN_FILE="${CACHE_DIR}/reddit_token.dat"
RATE_LIMIT_FILE="${CACHE_DIR}/reddit_rate_limit.dat"
mkdir -p "${CACHE_DIR}"

# Get OAuth access token
get_reddit_token() {
    # Check if we have a valid cached token
    if [[ -f "${TOKEN_FILE}" ]]; then
        local token_data=$(cat "${TOKEN_FILE}")
        local token=$(echo "${token_data}" | cut -d: -f1)
        local timestamp=$(echo "${token_data}" | cut -d: -f2)
        local current_time=$(date +%s)
        local elapsed=$((current_time - timestamp))
        
        # Tokens expire after 1 hour (3600 seconds)
        if [[ ${elapsed} -lt 3500 ]]; then
            echo "${token}"
            return 0
        fi
    fi
    
    log_debug "Obtaining new Reddit OAuth token..."
    
    # Get new token
    local response=$(curl -s -X POST \
        -u "${REDDIT_CLIENT_ID}:${REDDIT_CLIENT_SECRET}" \
        -H "User-Agent: ${REDDIT_USER_AGENT}" \
        -d "grant_type=password&username=${REDDIT_USERNAME}&password=${REDDIT_PASSWORD}" \
        "${REDDIT_AUTH_URL}")
    
    local access_token=$(echo "${response}" | jq -r '.access_token')
    
    if [[ "${access_token}" == "null" ]] || [[ -z "${access_token}" ]]; then
        log_error "Failed to obtain Reddit access token"
        echo "${response}" | jq '.' >&2
        return 1
    fi
    
    # Cache token with timestamp
    echo "${access_token}:$(date +%s)" > "${TOKEN_FILE}"
    
    echo "${access_token}"
    return 0
}

# Rate limiting for Reddit
check_reddit_rate_limit() {
    if [[ ! -f "${RATE_LIMIT_FILE}" ]]; then
        echo "0:$(date +%s)" > "${RATE_LIMIT_FILE}"
    fi
    
    local current_time=$(date +%s)
    local rate_data=$(cat "${RATE_LIMIT_FILE}")
    local request_count=$(echo "${rate_data}" | cut -d: -f1)
    local window_start=$(echo "${rate_data}" | cut -d: -f2)
    local elapsed=$((current_time - window_start))
    
    if [[ ${elapsed} -ge ${RATE_LIMIT_WINDOW} ]]; then
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
    
    echo "$((request_count + 1)):${window_start}" > "${RATE_LIMIT_FILE}"
    return 0
}

# Make Reddit API request
reddit_api_request() {
    local endpoint=$1
    local method=${2:-GET}
    
    check_reddit_rate_limit
    
    local token=$(get_reddit_token)
    if [[ -z "${token}" ]]; then
        return 1
    fi
    
    local url="${REDDIT_OAUTH_URL}${endpoint}"
    local temp_file=$(mktemp)
    
    log_debug "Reddit API: ${method} ${endpoint}"
    
    local http_code=$(curl -s -w "%{http_code}" -o "${temp_file}" \
        -X "${method}" \
        -H "Authorization: Bearer ${token}" \
        -H "User-Agent: ${REDDIT_USER_AGENT}" \
        --connect-timeout "${CURL_TIMEOUT}" \
        "${url}")
    
    local response=$(cat "${temp_file}")
    rm -f "${temp_file}"
    
    case ${http_code} in
        200)
            echo "${response}"
            return 0
            ;;
        401)
            log_warn "Token expired, retrying..."
            rm -f "${TOKEN_FILE}"
            return 1
            ;;
        429)
            log_error "Rate limit exceeded"
            return 1
            ;;
        *)
            log_error "HTTP ${http_code}: ${response}"
            return 1
            ;;
    esac
}

# Fetch user profile
fetch_reddit_user() {
    local username=$1
    reddit_api_request "/user/${username}/about.json"
}

# Fetch user posts
fetch_reddit_user_posts() {
    local username=$1
    local limit=${2:-100}
    reddit_api_request "/user/${username}/submitted.json?limit=${limit}"
}

# Fetch user comments
fetch_reddit_user_comments() {
    local username=$1
    local limit=${2:-100}
    reddit_api_request "/user/${username}/comments.json?limit=${limit}"
}

# Search Reddit
search_reddit() {
    local query=$1
    local subreddit=${2:-all}
    local limit=${3:-100}
    local encoded_query=$(echo "${query}" | jq -sRr @uri)
    
    if [[ "${subreddit}" == "all" ]]; then
        reddit_api_request "/search.json?q=${encoded_query}&limit=${limit}&sort=new"
    else
        reddit_api_request "/r/${subreddit}/search.json?q=${encoded_query}&limit=${limit}&restrict_sr=on&sort=new"
    fi
}

# Fetch subreddit posts
fetch_subreddit_posts() {
    local subreddit=$1
    local sort=${2:-new}
    local limit=${3:-100}
    reddit_api_request "/r/${subreddit}/${sort}.json?limit=${limit}"
}

# Fetch post comments
fetch_post_comments() {
    local subreddit=$1
    local post_id=$2
    reddit_api_request "/r/${subreddit}/comments/${post_id}.json"
}
