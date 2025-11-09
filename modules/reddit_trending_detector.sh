#!/bin/bash

#############################################
# Reddit Trending Posts Detector
# Identifies viral/trending content
#############################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config/config.sh"
source "${SCRIPT_DIR}/utils/logger.sh"
source "${SCRIPT_DIR}/utils/reddit_api.sh"

detect_trending_posts() {
    local subreddit=${1:-all}
    local output_file="${DATA_DIR}/trends/trending_posts_${subreddit}_$(date +%Y%m%d).json"
    
    log_info "Detecting trending posts in r/${subreddit}"
    
    # Fetch hot/rising posts
    local hot_posts=$(fetch_subreddit_posts "${subreddit}" "hot" 50)
    local rising_posts=$(fetch_subreddit_posts "${subreddit}" "rising" 50)
    
    if [[ -z "${hot_posts}" ]]; then
        log_error "Failed to fetch posts"
        return 1
    fi
    
    declare -a viral_posts
    local viral_count=0
    
    # Analyze hot posts for viral potential
    while read -r post; do
        local post_id=$(echo "${post}" | jq -r '.data.id')
        local title=$(echo "${post}" | jq -r '.data.title')
        local score=$(echo "${post}" | jq -r '.data.score')
        local num_comments=$(echo "${post}" | jq -r '.data.num_comments')
        local created_utc=$(echo "${post}" | jq -r '.data.created_utc' | xargs printf "%.0f")
        local upvote_ratio=$(echo "${post}" | jq -r '.data.upvote_ratio')
        local author=$(echo "${post}" | jq -r '.data.author')
        
        # Calculate post age in hours
        local current_time=$(date +%s)
        local post_age_hours=$(awk "BEGIN {printf \"%.2f\", (${current_time} - ${created_utc})/3600}")
        
        # Calculate engagement velocity
        local score_per_hour=0
        local comments_per_hour=0
        
        if awk "BEGIN {exit !(${post_age_hours} > 0)}"; then
            score_per_hour=$(awk "BEGIN {printf \"%.2f\", ${score}/${post_age_hours}}")
            comments_per_hour=$(awk "BEGIN {printf \"%.2f\", ${num_comments}/${post_age_hours}}")
        fi
        
        # Viral detection criteria
        local viral_score=0
        
        # High engagement rate
        if awk "BEGIN {exit !(${score_per_hour} > 100)}"; then
            viral_score=$((viral_score + 30))
        fi
        
        # High comment rate
        if awk "BEGIN {exit !(${comments_per_hour} > 20)}"; then
            viral_score=$((viral_score + 25))
        fi
        
        # High upvote ratio
        if awk "BEGIN {exit !(${upvote_ratio} > 0.9)}"; then
            viral_score=$((viral_score + 20))
        fi
        
        # Absolute numbers
        if [[ ${score} -gt 1000 ]]; then
            viral_score=$((viral_score + 15))
        fi
        
        if [[ ${num_comments} -gt 200 ]]; then
            viral_score=$((viral_score + 10))
        fi
        
        # If viral score is high enough
        if [[ ${viral_score} -ge 50 ]]; then
            ((viral_count++))
            
            viral_posts+=("{
                \"post_id\": \"${post_id}\",
                \"title\": $(echo "${title}" | jq -Rs .),
                \"author\": \"${author}\",
                \"score\": ${score},
                \"comments\": ${num_comments},
                \"age_hours\": ${post_age_hours},
                \"score_per_hour\": ${score_per_hour},
                \"comments_per_hour\": ${comments_per_hour},
                \"upvote_ratio\": ${upvote_ratio},
                \"viral_score\": ${viral_score},
                \"url\": \"https://reddit.com${$(echo "${post}" | jq -r '.data.permalink')}\"
            }")
        fi
        
    done < <(echo "${hot_posts}" | jq -c '.data.children[]')
    
    # Generate report
    cat > "${output_file}" << EOF
{
    "analysis_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "platform": "Reddit",
    "subreddit": "${subreddit}",
    "viral_posts_detected": ${viral_count},
    "viral_posts": [
        $(IFS=,; echo "${viral_posts[*]}")
    ]
}
EOF
    
    log_success "Found ${viral_count} trending/viral posts"
    cat "${output_file}" | jq '.'
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    detect_trending_posts "${1:-all}"
fi
