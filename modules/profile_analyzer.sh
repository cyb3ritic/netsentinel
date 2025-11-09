#!/bin/bash

#############################################
# Reddit Profile Analysis Module (FULLY FIXED)
#############################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config/config.sh"
source "${SCRIPT_DIR}/utils/logger.sh"
source "${SCRIPT_DIR}/utils/reddit_api.sh"

analyze_reddit_profile() {
    local username=$1
    local output_file="${DATA_DIR}/profiles/reddit_${username}_analysis.json"
    
    log_info "Analyzing Reddit profile: u/${username}"
    
    # Fetch user data
    local user_data=$(fetch_reddit_user "${username}")
    
    if [[ -z "${user_data}" ]] || [[ $(echo "${user_data}" | jq -r '.error' 2>/dev/null) != "null" ]]; then
        log_error "Failed to fetch user data for u/${username}"
        return 1
    fi
    
    # Extract user metrics
    local user_info=$(echo "${user_data}" | jq -r '.data')
    local created_utc=$(echo "${user_info}" | jq -r '.created_utc')
    local link_karma=$(echo "${user_info}" | jq -r '.link_karma')
    local comment_karma=$(echo "${user_info}" | jq -r '.comment_karma')
    local is_employee=$(echo "${user_info}" | jq -r '.is_employee')
    local is_mod=$(echo "${user_info}" | jq -r '.is_mod')
    local verified=$(echo "${user_info}" | jq -r '.verified')
    local has_verified_email=$(echo "${user_info}" | jq -r '.has_verified_email')
    local is_gold=$(echo "${user_info}" | jq -r '.is_gold // false')
    
    # Convert floating point timestamp to integer
    created_utc=$(printf "%.0f" "${created_utc}")
    
    # Calculate account age
    local current_time=$(date +%s)
    local account_age_days=$(( (current_time - created_utc) / 86400 ))
    [[ ${account_age_days} -lt 0 ]] && account_age_days=0
    
    # Calculate karma ratio using awk (bc alternative)
    local karma_ratio=0
    if [[ ${comment_karma} -gt 0 ]]; then
        karma_ratio=$(awk "BEGIN {printf \"%.2f\", ${link_karma}/${comment_karma}}")
    elif [[ ${link_karma} -gt 0 ]]; then
        karma_ratio="999.00"
    fi
    
    # Fetch posts and comments
    log_debug "Fetching user activity..."
    local posts_data=$(fetch_reddit_user_posts "${username}" 100)
    local comments_data=$(fetch_reddit_user_comments "${username}" 100)
    
    local post_count=0
    local comment_count=0
    
    [[ -n "${posts_data}" ]] && post_count=$(echo "${posts_data}" | jq '.data.children | length' 2>/dev/null || echo 0)
    [[ -n "${comments_data}" ]] && comment_count=$(echo "${comments_data}" | jq '.data.children | length' 2>/dev/null || echo 0)
    
    # Calculate activity rate using awk
    local total_activity=$((post_count + comment_count))
    local activity_rate="0.00"
    if [[ ${account_age_days} -gt 0 ]]; then
        activity_rate=$(awk "BEGIN {printf \"%.2f\", ${total_activity}/${account_age_days}}")
    fi
    
    # Calculate total karma
    local total_karma=$((link_karma + comment_karma))
    
    # Initialize analysis
    local suspicion_score=0
    declare -a red_flags
    
    # Check 1: Very new account
    if [[ ${account_age_days} -lt ${MAX_ACCOUNT_AGE_DAYS} ]]; then
        suspicion_score=$((suspicion_score + 20))
        red_flags+=("Account is only ${account_age_days} days old")
    fi
    
    # Check 2: No verified email
    if [[ "${has_verified_email}" == "false" ]]; then
        suspicion_score=$((suspicion_score + 15))
        red_flags+=("Email not verified")
    fi
    
    # Check 3: Low karma
    if [[ ${total_karma} -lt 10 ]]; then
        suspicion_score=$((suspicion_score + 20))
        red_flags+=("Very low karma: ${total_karma}")
    elif [[ ${total_karma} -lt 0 ]]; then
        suspicion_score=$((suspicion_score + 30))
        red_flags+=("Negative karma: ${total_karma}")
    fi
    
    # Check 4: Abnormal karma ratio (using awk for comparison)
    if awk "BEGIN {exit !(${karma_ratio} > 10)}"; then
        suspicion_score=$((suspicion_score + 15))
        red_flags+=("Unusual karma ratio: ${karma_ratio}")
    fi
    
    # Check 5: High posting rate
    if awk "BEGIN {exit !(${activity_rate} > ${SUSPICIOUS_POST_RATE})}"; then
        suspicion_score=$((suspicion_score + 25))
        red_flags+=("Excessive posting rate: ${activity_rate} posts/day")
    fi
    
    # Check 6: Content analysis
    local suspicious_links=0
    local scam_keyword_count=0
    local unique_titles=0
    
    if [[ ${post_count} -gt 0 ]] && [[ -n "${posts_data}" ]]; then
        # Check URLs
        while read -r url; do
            if [[ "${url}" != "null" ]] && [[ -n "${url}" ]]; then
                for pattern in "${SUSPICIOUS_LINK_PATTERNS[@]}"; do
                    if [[ "${url}" == *"${pattern}"* ]]; then
                        ((suspicious_links++))
                        break
                    fi
                done
            fi
        done < <(echo "${posts_data}" | jq -r '.data.children[].data.url' 2>/dev/null)
        
        # Check title uniqueness
        unique_titles=$(echo "${posts_data}" | jq -r '.data.children[].data.title' 2>/dev/null | sort -u | wc -l)
        
        if [[ ${post_count} -gt 5 ]] && [[ ${unique_titles} -lt $((post_count / 2)) ]]; then
            suspicion_score=$((suspicion_score + 20))
            red_flags+=("High content duplication")
        fi
        
        # Check for scam keywords
        while read -r title; do
            [[ -n "${title}" ]] && grep -qif "${THREAT_KEYWORDS_FILE}" <<< "${title}" 2>/dev/null && ((scam_keyword_count++))
        done < <(echo "${posts_data}" | jq -r '.data.children[].data.title' 2>/dev/null)
    fi
    
    [[ ${suspicious_links} -gt 5 ]] && {
        suspicion_score=$((suspicion_score + 15))
        red_flags+=("${suspicious_links} suspicious URLs detected")
    }
    
    [[ ${scam_keyword_count} -gt 3 ]] && {
        suspicion_score=$((suspicion_score + 20))
        red_flags+=("${scam_keyword_count} posts with threat keywords")
    }
    
    # Check 7: Bot-like behavior
    if [[ ${post_count} -gt 10 ]] && [[ ${comment_count} -eq 0 ]]; then
        suspicion_score=$((suspicion_score + 15))
        red_flags+=("Only posts, never comments (bot behavior)")
    fi
    
    # Classification
    local classification="LEGITIMATE"
    local risk_level="LOW"
    
    if [[ ${suspicion_score} -ge ${FAKE_PROFILE_THRESHOLD} ]]; then
        classification="SUSPICIOUS/BOT"
        risk_level="CRITICAL"
    elif [[ ${suspicion_score} -ge 50 ]]; then
        classification="QUESTIONABLE"
        risk_level="HIGH"
    elif [[ ${suspicion_score} -ge 30 ]]; then
        classification="MONITOR"
        risk_level="MEDIUM"
    fi
    
    # Convert red_flags array to JSON properly
    local red_flags_json="[]"
    if [[ ${#red_flags[@]} -gt 0 ]]; then
        red_flags_json=$(printf '%s\n' "${red_flags[@]}" | jq -R . | jq -s .)
    fi
    
    # Generate report
    cat > "${output_file}" << EOF
{
    "analysis_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "platform": "Reddit",
    "username": "${username}",
    "classification": "${classification}",
    "risk_level": "${risk_level}",
    "suspicion_score": ${suspicion_score},
    "account_metrics": {
        "created_utc": ${created_utc},
        "account_age_days": ${account_age_days},
        "link_karma": ${link_karma},
        "comment_karma": ${comment_karma},
        "total_karma": ${total_karma},
        "karma_ratio": ${karma_ratio},
        "is_verified": ${verified},
        "has_verified_email": ${has_verified_email},
        "is_moderator": ${is_mod},
        "is_gold": ${is_gold}
    },
    "activity_metrics": {
        "total_posts": ${post_count},
        "total_comments": ${comment_count},
        "total_activity": ${total_activity},
        "activity_rate_per_day": ${activity_rate},
        "unique_post_titles": ${unique_titles},
        "suspicious_links_found": ${suspicious_links},
        "scam_keywords_found": ${scam_keyword_count}
    },
    "red_flags": ${red_flags_json},
    "recommendation": "$(get_recommendation "${classification}")"
}
EOF
    
    # Properly append to suspicious profiles (FIXED JSON append)
    if [[ "${classification}" != "LEGITIMATE" ]]; then
        local suspicious_file="${DATA_DIR}/profiles/suspicious_profiles.json"
        
        # Initialize file if it doesn't exist or is empty
        if [[ ! -f "${suspicious_file}" ]] || [[ ! -s "${suspicious_file}" ]]; then
            echo "[]" > "${suspicious_file}"
        fi
        
        # Append using jq properly
        jq ". += [$(cat "${output_file}")]" "${suspicious_file}" > "${suspicious_file}.tmp" && mv "${suspicious_file}.tmp" "${suspicious_file}"
    fi
    
    log_success "Profile analysis complete: ${classification} (Score: ${suspicion_score}/100)"
    echo ""
    echo "=== ANALYSIS REPORT ==="
    cat "${output_file}" | jq '.'
    echo ""
    echo "Report saved to: ${output_file}"
}

get_recommendation() {
    local classification=$1
    
    case ${classification} in
        "SUSPICIOUS/BOT")
            echo "CRITICAL: Likely spam/bot account. Report to Reddit moderators."
            ;;
        "QUESTIONABLE")
            echo "INVESTIGATE: Manual review recommended. Multiple suspicious indicators."
            ;;
        "MONITOR")
            echo "MONITOR: Continue surveillance. Some red flags present."
            ;;
        *)
            echo "Account appears legitimate. No immediate action required."
            ;;
    esac
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <username>"
        exit 1
    fi
    
    analyze_reddit_profile "$1"
fi
