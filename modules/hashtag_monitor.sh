#!/bin/bash

#############################################
# Reddit Keyword & Trend Monitoring Module
# (Replaces hashtag monitoring for Reddit)
#############################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config/config.sh"
source "${SCRIPT_DIR}/utils/logger.sh"
source "${SCRIPT_DIR}/utils/reddit_api.sh"

monitor_reddit_keyword() {
    local keyword=$1
    local subreddit=${2:-all}
    local output_file="${DATA_DIR}/trends/reddit_${keyword// /_}_$(date +%Y%m%d_%H%M%S).json"
    
    log_info "Monitoring Reddit keyword: '${keyword}' in r/${subreddit}"
    
    # Search Reddit for the keyword
    local search_results=$(search_reddit "${keyword}" "${subreddit}" 100)
    
    if [[ -z "${search_results}" ]]; then
        log_error "Failed to fetch search results"
        return 1
    fi
    
    # Check if we got actual results
    local result_count=$(echo "${search_results}" | jq '.data.children | length' 2>/dev/null || echo 0)
    
    if [[ ${result_count} -eq 0 ]]; then
        log_warn "No posts found for keyword: ${keyword}"
        echo "{\"error\": \"No results found\", \"keyword\": \"${keyword}\"}" | jq '.'
        return 1
    fi
    
    log_info "Found ${result_count} posts matching '${keyword}'"
    
    # Initialize metrics
    local total_posts=${result_count}
    local unique_authors=0
    local total_score=0
    local total_comments=0
    local avg_score=0
    local avg_comments=0
    
    # Time-based analysis
    local current_time=$(date +%s)
    local posts_last_hour=0
    local posts_last_24h=0
    local posts_last_week=0
    
    # Bot detection metrics
    local bot_score=0
    declare -a bot_indicators
    declare -A author_post_count
    declare -A subreddit_distribution
    
    # Analyze each post
    while read -r post; do
        local author=$(echo "${post}" | jq -r '.data.author')
        local score=$(echo "${post}" | jq -r '.data.score')
        local num_comments=$(echo "${post}" | jq -r '.data.num_comments')
        local created_utc=$(echo "${post}" | jq -r '.data.created_utc' | xargs printf "%.0f")
        local post_subreddit=$(echo "${post}" | jq -r '.data.subreddit')
        local upvote_ratio=$(echo "${post}" | jq -r '.data.upvote_ratio')
        
        # Accumulate metrics
        total_score=$((total_score + score))
        total_comments=$((total_comments + num_comments))
        
        # Count posts per author
        author_post_count["${author}"]=$((${author_post_count["${author}"]:-0} + 1))
        
        # Track subreddit distribution
        subreddit_distribution["${post_subreddit}"]=$((${subreddit_distribution["${post_subreddit}"]:-0} + 1))
        
        # Time-based categorization
        local post_age=$((current_time - created_utc))
        
        if [[ ${post_age} -le 3600 ]]; then
            ((posts_last_hour++))
        fi
        
        if [[ ${post_age} -le 86400 ]]; then
            ((posts_last_24h++))
        fi
        
        if [[ ${post_age} -le 604800 ]]; then
            ((posts_last_week++))
        fi
        
    done < <(echo "${search_results}" | jq -c '.data.children[]')
    
    # Calculate unique authors
    unique_authors=${#author_post_count[@]}
    
    # Calculate averages
    if [[ ${total_posts} -gt 0 ]]; then
        avg_score=$(awk "BEGIN {printf \"%.2f\", ${total_score}/${total_posts}}")
        avg_comments=$(awk "BEGIN {printf \"%.2f\", ${total_comments}/${total_posts}}")
    fi
    
    # Calculate author diversity
    local author_diversity=0
    if [[ ${total_posts} -gt 0 ]]; then
        author_diversity=$(awk "BEGIN {printf \"%.2f\", ${unique_authors}/${total_posts}}")
    fi
    
    # Calculate posting velocity (posts per hour)
    local posting_velocity=0
    if [[ ${posts_last_24h} -gt 0 ]]; then
        posting_velocity=$(awk "BEGIN {printf \"%.2f\", ${posts_last_24h}/24}")
    fi
    
    # Bot/Coordinated Activity Detection
    
    # Check 1: Low author diversity (coordinated campaign)
    if awk "BEGIN {exit !(${author_diversity} < 0.3)}"; then
        bot_score=$((bot_score + 30))
        bot_indicators+=("Low author diversity: ${author_diversity} (possible bot network)")
    fi
    
    # Check 2: High posting velocity (spam/coordinated)
    if awk "BEGIN {exit !(${posting_velocity} > 10)}"; then
        bot_score=$((bot_score + 25))
        bot_indicators+=("High posting velocity: ${posting_velocity} posts/hour")
    fi
    
    # Check 3: Single author dominance
    local max_posts_by_author=0
    local dominant_author=""
    
    for author in "${!author_post_count[@]}"; do
        if [[ ${author_post_count["${author}"]} -gt ${max_posts_by_author} ]]; then
            max_posts_by_author=${author_post_count["${author}"]}
            dominant_author="${author}"
        fi
    done
    
    local author_dominance=0
    if [[ ${total_posts} -gt 0 ]]; then
        author_dominance=$(awk "BEGIN {printf \"%.2f\", ${max_posts_by_author}/${total_posts}}")
    fi
    
    if awk "BEGIN {exit !(${author_dominance} > 0.4)}"; then
        bot_score=$((bot_score + 20))
        bot_indicators+=("Single author (${dominant_author}) posted ${author_dominance}% of content")
    fi
    
    # Check 4: Sudden spike detection
    local spike_ratio=0
    if [[ ${posts_last_week} -gt 0 ]]; then
        spike_ratio=$(awk "BEGIN {printf \"%.2f\", (${posts_last_24h}/${posts_last_week})*7}")
    fi
    
    if awk "BEGIN {exit !(${spike_ratio} > 3)}"; then
        bot_score=$((bot_score + 25))
        bot_indicators+=("Abnormal spike: ${spike_ratio}x normal volume")
    fi
    
    # Check 5: Content analysis for scam patterns
    local scam_content_count=0
    
    while read -r post; do
        local title=$(echo "${post}" | jq -r '.data.title')
        local selftext=$(echo "${post}" | jq -r '.data.selftext')
        local combined="${title} ${selftext}"
        
        if grep -qif "${THREAT_KEYWORDS_FILE}" <<< "${combined}" 2>/dev/null; then
            ((scam_content_count++))
        fi
    done < <(echo "${search_results}" | jq -c '.data.children[]')
    
    if [[ ${scam_content_count} -gt $((total_posts / 4)) ]]; then
        bot_score=$((bot_score + 20))
        bot_indicators+=("${scam_content_count} posts contain threat keywords")
    fi
    
    # Trend Classification
    local trend_classification="ORGANIC"
    local threat_level="LOW"
    local trend_status="NORMAL"
    
    if [[ ${bot_score} -ge 70 ]]; then
        trend_classification="COORDINATED/ARTIFICIAL"
        threat_level="CRITICAL"
        trend_status="SUSPICIOUS"
    elif [[ ${bot_score} -ge 50 ]]; then
        trend_classification="HIGHLY SUSPICIOUS"
        threat_level="HIGH"
        trend_status="ABNORMAL"
    elif [[ ${bot_score} -ge 30 ]]; then
        trend_classification="QUESTIONABLE"
        threat_level="MEDIUM"
        trend_status="UNUSUAL"
    fi
    
    # Identify top contributors
    local top_contributors=()
    for author in "${!author_post_count[@]}"; do
        top_contributors+=("{\"username\": \"${author}\", \"post_count\": ${author_post_count["${author}"]}, \"percentage\": $(awk "BEGIN {printf \"%.1f\", (${author_post_count["${author}"]}/${total_posts})*100}")}")
    done
    
    # Sort and get top 5
    local top_5_contributors=$(printf '%s\n' "${top_contributors[@]}" | jq -s 'sort_by(.post_count) | reverse | .[0:5]')
    
    # Subreddit distribution
    local subreddit_dist_json="["
    local first=true
    for sub in "${!subreddit_distribution[@]}"; do
        [[ "${first}" == "false" ]] && subreddit_dist_json+=","
        subreddit_dist_json+="{\"subreddit\": \"${sub}\", \"count\": ${subreddit_distribution["${sub}"]}, \"percentage\": $(awk "BEGIN {printf \"%.1f\", (${subreddit_distribution["${sub}"]}/${total_posts})*100}")}"
        first=false
    done
    subreddit_dist_json+="]"
    
    # Convert bot_indicators to JSON
    local bot_indicators_json="[]"
    if [[ ${#bot_indicators[@]} -gt 0 ]]; then
        bot_indicators_json=$(printf '%s\n' "${bot_indicators[@]}" | jq -R . | jq -s .)
    fi
    
    # Determine trending status
    local is_trending="false"
    if [[ ${posts_last_hour} -gt 5 ]] || [[ ${posts_last_24h} -gt 50 ]]; then
        is_trending="true"
    fi
    
    # Generate comprehensive report
    cat > "${output_file}" << EOF
{
    "analysis_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "platform": "Reddit",
    "keyword": "${keyword}",
    "search_scope": "${subreddit}",
    "trend_classification": "${trend_classification}",
    "threat_level": "${threat_level}",
    "trend_status": "${trend_status}",
    "is_trending": ${is_trending},
    "bot_suspicion_score": ${bot_score},
    "volume_metrics": {
        "total_posts_found": ${total_posts},
        "unique_authors": ${unique_authors},
        "author_diversity": ${author_diversity},
        "posts_last_hour": ${posts_last_hour},
        "posts_last_24h": ${posts_last_24h},
        "posts_last_week": ${posts_last_week},
        "posting_velocity_per_hour": ${posting_velocity},
        "spike_ratio": ${spike_ratio}
    },
    "engagement_metrics": {
        "total_score": ${total_score},
        "total_comments": ${total_comments},
        "average_score": ${avg_score},
        "average_comments": ${avg_comments}
    },
    "content_analysis": {
        "scam_keyword_matches": ${scam_content_count},
        "scam_percentage": $(awk "BEGIN {printf \"%.1f\", (${scam_content_count}/${total_posts})*100}")
    },
    "distribution_analysis": {
        "subreddit_distribution": ${subreddit_dist_json},
        "top_contributors": ${top_5_contributors},
        "dominant_author": "${dominant_author}",
        "author_dominance_percentage": $(awk "BEGIN {printf \"%.1f\", ${author_dominance}*100}")
    },
    "bot_indicators": ${bot_indicators_json},
    "recommendation": "$(get_trend_recommendation "${trend_classification}")",
    "alert_required": $(if [[ "${threat_level}" == "CRITICAL" ]] || [[ "${threat_level}" == "HIGH" ]]; then echo "true"; else echo "false"; fi)
}
EOF
    
    log_success "Keyword monitoring complete: ${trend_classification} (Bot Score: ${bot_score}/100)"
    echo ""
    echo "=== TREND ANALYSIS REPORT ==="
    cat "${output_file}" | jq '.'
    echo ""
    echo "Report saved to: ${output_file}"
    
    # Send alert if critical
    if [[ "${threat_level}" == "CRITICAL" ]] && [[ "${ENABLE_ALERTS}" == "true" ]]; then
        send_trend_alert "CRITICAL: Coordinated campaign detected for keyword '${keyword}'"
    fi
}

get_trend_recommendation() {
    local classification=$1
    
    case ${classification} in
        "COORDINATED/ARTIFICIAL")
            echo "CRITICAL: Likely bot-driven or coordinated campaign. Immediate investigation required."
            ;;
        "HIGHLY SUSPICIOUS")
            echo "HIGH PRIORITY: Abnormal patterns detected. Manual review and deeper analysis recommended."
            ;;
        "QUESTIONABLE")
            echo "MONITOR CLOSELY: Some suspicious indicators present. Continue surveillance."
            ;;
        *)
            echo "Trend appears organic. Normal monitoring sufficient."
            ;;
    esac
}

send_trend_alert() {
    local message=$1
    
    if [[ -n "${ALERT_WEBHOOK_URL}" ]]; then
        curl -s -X POST "${ALERT_WEBHOOK_URL}" \
            -H "Content-Type: application/json" \
            -d "{\"text\": \"🚨 Reddit Alert: ${message}\"}" \
            2>/dev/null
    fi
    
    log_warn "ALERT: ${message}"
}

# Monitor multiple subreddits for a keyword
monitor_cross_subreddit() {
    local keyword=$1
    
    log_info "Cross-subreddit analysis for: ${keyword}"
    
    # Monitor in multiple high-risk subreddits
    local subreddits=("cryptocurrency" "wallstreetbets" "investing" "technology" "news")
    
    for subreddit in "${subreddits[@]}"; do
        log_info "Analyzing r/${subreddit}..."
        monitor_reddit_keyword "${keyword}" "${subreddit}"
        sleep 2  # Rate limiting
    done
    
    log_success "Cross-subreddit analysis complete"
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <keyword> [subreddit|all]"
        echo ""
        echo "Examples:"
        echo "  $0 'crypto giveaway' all"
        echo "  $0 'free money' cryptocurrency"
        echo "  $0 'bitcoin' wallstreetbets"
        exit 1
    fi
    
    monitor_reddit_keyword "$1" "${2:-all}"
fi
