#!/bin/bash

#############################################
# Reddit Scam Detection Module
# Comprehensive scam pattern detection
#############################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config/config.sh"
source "${SCRIPT_DIR}/utils/logger.sh"
source "${SCRIPT_DIR}/utils/reddit_api.sh"

detect_reddit_scams() {
    local keyword=$1
    local subreddit=${2:-all}
    local output_file="${DATA_DIR}/reddit_scams_${keyword// /_}_$(date +%Y%m%d_%H%M%S).json"
    
    log_info "Detecting scams related to: '${keyword}' in r/${subreddit}"
    
    # Search Reddit for potential scam content
    local search_data=$(search_reddit "${keyword}" "${subreddit}" 100)
    
    if [[ -z "${search_data}" ]]; then
        log_error "Failed to search for scam patterns"
        return 1
    fi
    
    local result_count=$(echo "${search_data}" | jq '.data.children | length' 2>/dev/null || echo 0)
    
    if [[ ${result_count} -eq 0 ]]; then
        log_warn "No posts found matching keyword: ${keyword}"
        return 1
    fi
    
    log_info "Analyzing ${result_count} posts for scam patterns..."
    
    # Initialize tracking
    local total_analyzed=0
    local scams_detected=0
    declare -a scam_instances
    declare -A scam_types_count
    
    # Scam type categories
    scam_types_count["phishing"]=0
    scam_types_count["crypto_scam"]=0
    scam_types_count["fake_giveaway"]=0
    scam_types_count["investment_fraud"]=0
    scam_types_count["fake_support"]=0
    scam_types_count["romance_scam"]=0
    scam_types_count["job_scam"]=0
    
    # Analyze each post
    while read -r post; do
        ((total_analyzed++))
        
        local post_id=$(echo "${post}" | jq -r '.data.id')
        local title=$(echo "${post}" | jq -r '.data.title')
        local selftext=$(echo "${post}" | jq -r '.data.selftext')
        local author=$(echo "${post}" | jq -r '.data.author')
        local url=$(echo "${post}" | jq -r '.data.url')
        local created_utc=$(echo "${post}" | jq -r '.data.created_utc' | xargs printf "%.0f")
        local score=$(echo "${post}" | jq -r '.data.score')
        local subreddit_name=$(echo "${post}" | jq -r '.data.subreddit')
        local num_comments=$(echo "${post}" | jq -r '.data.num_comments')
        
        # Combine text for analysis
        local combined_text="${title} ${selftext}"
        
        # Initialize scam detection
        local scam_score=0
        declare -a detected_patterns
        declare -a scam_categories
        
        # ===== PATTERN DETECTION =====
        
        # Pattern 1: Urgent/Pressure Language (FOMO tactics)
        if echo "${combined_text}" | grep -iE "(urgent|act now|limited time|expires|hurry|last chance|don't miss|ending soon|quick|immediate)" > /dev/null; then
            scam_score=$((scam_score + 15))
            detected_patterns+=("Urgent/pressure language detected")
        fi
        
        # Pattern 2: Unrealistic Financial Promises
        if echo "${combined_text}" | grep -iE "(free money|guaranteed profit|100% return|double.*bitcoin|passive income|financial freedom|get rich|easy money|risk.?free|huge profit)" > /dev/null; then
            scam_score=$((scam_score + 30))
            detected_patterns+=("Unrealistic financial promises")
            scam_categories+=("investment_fraud")
        fi
        
        # Pattern 3: Cryptocurrency Scams
        if echo "${combined_text}" | grep -iE "(send.*btc|send.*eth|wallet address|crypto.*giveaway|airdrop|token presale|ICO opportunity|mining pool|double.*crypto)" > /dev/null; then
            scam_score=$((scam_score + 25))
            detected_patterns+=("Cryptocurrency scam indicators")
            scam_categories+=("crypto_scam")
        fi
        
        # Pattern 4: Fake Giveaways
        if echo "${combined_text}" | grep -iE "(giveaway|winner|claim.*prize|congratulations.*won|you've been selected|free.*(iphone|gift card|gpu|ps5|xbox))" > /dev/null; then
            scam_score=$((scam_score + 20))
            detected_patterns+=("Fake giveaway pattern")
            scam_categories+=("fake_giveaway")
        fi
        
        # Pattern 5: Phishing/Account Verification
        if echo "${combined_text}" | grep -iE "(verify.*account|confirm.*identity|security alert|unusual activity|suspended.*account|update.*payment|billing problem|click here to|account.*locked)" > /dev/null; then
            scam_score=$((scam_score + 25))
            detected_patterns+=("Phishing/verification scam")
            scam_categories+=("phishing")
        fi
        
        # Pattern 6: Off-Platform Contact Requests
        if echo "${combined_text}" | grep -iE "(dm.*me|direct message|message.*me|whatsapp|telegram|discord|signal|kik|snapchat|contact.*outside)" > /dev/null; then
            scam_score=$((scam_score + 15))
            detected_patterns+=("Off-platform contact request")
        fi
        
        # Pattern 7: Investment/Trading Schemes
        if echo "${combined_text}" | grep -iE "(investment.*opportunity|trading.*signal|forex.*profit|binary option|crypto.*trading|guaranteed.*return|investment.*manager)" > /dev/null; then
            scam_score=$((scam_score + 20))
            detected_patterns+=("Investment scheme indicators")
            scam_categories+=("investment_fraud")
        fi
        
        # Pattern 8: Fake Support/Moderator
        if echo "${combined_text}" | grep -iE "(reddit support|admin.*contact|moderator.*warning|official.*support|customer.*service|support.*team|ban.*warning)" > /dev/null; then
            scam_score=$((scam_score + 25))
            detected_patterns+=("Fake support/moderator impersonation")
            scam_categories+=("fake_support")
        fi
        
        # Pattern 9: Romance/Relationship Scams
        if echo "${combined_text}" | grep -iE "(lonely|looking for.*love|find.*soulmate|sugar.*daddy|sugar.*mommy|arrangement|companionship.*money)" > /dev/null; then
            scam_score=$((scam_score + 15))
            detected_patterns+=("Romance scam indicators")
            scam_categories+=("romance_scam")
        fi
        
        # Pattern 10: Job/Employment Scams
        if echo "${combined_text}" | grep -iE "(work from home|easy job|make.*working|no experience|upfront.*fee|pay.*training|job.*opportunity)" > /dev/null; then
            scam_score=$((scam_score + 15))
            detected_patterns+=("Job scam indicators")
            scam_categories+=("job_scam")
        fi
        
        # Pattern 11: Suspicious URLs/Links
        local suspicious_url_count=0
        
        if [[ "${url}" != "null" ]] && [[ -n "${url}" ]]; then
            for pattern in "${SUSPICIOUS_LINK_PATTERNS[@]}"; do
                if [[ "${url}" == *"${pattern}"* ]]; then
                    scam_score=$((scam_score + 15))
                    detected_patterns+=("Shortened/suspicious URL detected")
                    ((suspicious_url_count++))
                    break
                fi
            done
            
            # Check for lookalike domains
            if echo "${url}" | grep -iE "(redd[il]t|paypai|arnazon|g00gle|rnicr0soft)" > /dev/null; then
                scam_score=$((scam_score + 30))
                detected_patterns+=("Lookalike/typosquatting domain detected")
                scam_categories+=("phishing")
            fi
        fi
        
        # Pattern 12: Payment-Only Methods
        if echo "${combined_text}" | grep -iE "(crypto only|bitcoin only|gift card|prepaid card|western union|moneygram|wire transfer|no refund)" > /dev/null; then
            scam_score=$((scam_score + 20))
            detected_patterns+=("Suspicious payment method requirements")
        fi
        
        # Pattern 13: Celebrity/Authority Endorsement
        if echo "${combined_text}" | grep -iE "(elon musk|bill gates|celebrity|endorsed by|recommended by|as seen on)" > /dev/null; then
            scam_score=$((scam_score + 15))
            detected_patterns+=("Celebrity endorsement (likely fake)")
        fi
        
        # Pattern 14: Upfront Fees/Withdrawal Fees
        if echo "${combined_text}" | grep -iE "(upfront fee|processing fee|unlock.*account|withdrawal fee|verification fee|pay.*withdraw|release.*fund)" > /dev/null; then
            scam_score=$((scam_score + 25))
            detected_patterns+=("Upfront fee request (advance-fee fraud)")
            scam_categories+=("investment_fraud")
        fi
        
        # Pattern 15: Poor Grammar/Spelling (common in scams)
        local grammar_issues=0
        if echo "${combined_text}" | grep -E "(kindly|do the needful|revert back|ur |u r)" > /dev/null; then
            scam_score=$((scam_score + 10))
            detected_patterns+=("Non-native grammar patterns")
            ((grammar_issues++))
        fi
        
        # Pattern 16: Account Analysis (check if author is suspicious)
        # Note: This would require additional API call, adding basic check
        if [[ "${author}" == "[deleted]" ]] || [[ "${author}" == "null" ]]; then
            scam_score=$((scam_score + 5))
            detected_patterns+=("Deleted or hidden author")
        fi
        
        # Pattern 17: No Comments (Scammers often post and delete quickly)
        if [[ ${num_comments} -eq 0 ]] && [[ ${score} -lt 2 ]]; then
            scam_score=$((scam_score + 5))
            detected_patterns+=("No engagement (possible quick-delete scam)")
        fi
        
        # ===== SCAM CLASSIFICATION =====
        
        if [[ ${scam_score} -ge ${SCAM_CONFIDENCE_THRESHOLD} ]]; then
            ((scams_detected++))
            
            # Determine primary scam type
            local primary_scam_type="unknown"
            if [[ ${#scam_categories[@]} -gt 0 ]]; then
                primary_scam_type="${scam_categories[0]}"
                scam_types_count["${primary_scam_type}"]=$((${scam_types_count["${primary_scam_type}"]} + 1))
            fi
            
            # Calculate confidence level
            local confidence="MEDIUM"
            if [[ ${scam_score} -ge 90 ]]; then
                confidence="CRITICAL"
            elif [[ ${scam_score} -ge 80 ]]; then
                confidence="HIGH"
            fi
            
            # Convert detected_patterns to JSON-safe format
            local patterns_json=$(printf '%s\n' "${detected_patterns[@]}" | jq -R . | jq -s .)
            
            # Create scam instance record
            scam_instances+=("{
                \"post_id\": \"${post_id}\",
                \"title\": $(echo "${title}" | jq -Rs .),
                \"author\": \"${author}\",
                \"subreddit\": \"${subreddit_name}\",
                \"url\": \"${url}\",
                \"reddit_link\": \"https://reddit.com/comments/${post_id}\",
                \"score\": ${score},
                \"num_comments\": ${num_comments},
                \"created_utc\": ${created_utc},
                \"scam_score\": ${scam_score},
                \"confidence_level\": \"${confidence}\",
                \"primary_scam_type\": \"${primary_scam_type}\",
                \"detected_patterns\": ${patterns_json},
                \"text_preview\": $(echo "${combined_text:0:200}" | jq -Rs .)
            }")
        fi
        
    done < <(echo "${search_data}" | jq -c '.data.children[]')
    
    # Calculate detection rate
    local detection_rate=0
    if [[ ${total_analyzed} -gt 0 ]]; then
        detection_rate=$(awk "BEGIN {printf \"%.2f\", (${scams_detected}/${total_analyzed})*100}")
    fi
    
    # Generate scam type distribution
    local scam_type_dist_json="{"
    local first=true
    for scam_type in "${!scam_types_count[@]}"; do
        [[ "${first}" == "false" ]] && scam_type_dist_json+=","
        scam_type_dist_json+="\"${scam_type}\": ${scam_types_count["${scam_type}"]}"
        first=false
    done
    scam_type_dist_json+="}"
    
    # Determine threat assessment
    local threat_level=$(get_threat_level ${scams_detected})
    local campaign_detected="false"
    
    # Check if this looks like a coordinated scam campaign
    if [[ ${scams_detected} -ge 10 ]] && awk "BEGIN {exit !(${detection_rate} > 50)}"; then
        campaign_detected="true"
    fi
    
    # Generate comprehensive scam report
    cat > "${output_file}" << EOF
{
    "analysis_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "platform": "Reddit",
    "keyword_searched": "${keyword}",
    "search_scope": "${subreddit}",
    "detection_summary": {
        "total_posts_analyzed": ${total_analyzed},
        "scams_detected": ${scams_detected},
        "detection_rate_percentage": ${detection_rate},
        "threat_level": "${threat_level}",
        "coordinated_campaign_detected": ${campaign_detected}
    },
    "scam_type_distribution": ${scam_type_dist_json},
    "detected_scams": [
        $(IFS=,; echo "${scam_instances[*]}")
    ],
    "recommendations": [
        "$(get_scam_recommendations ${scams_detected} ${campaign_detected})"
    ],
    "alert_priority": "$(get_alert_priority ${threat_level})"
}
EOF
    
    # Append to global scams database
    local scams_db="${DATA_DIR}/scams_detected.json"
    
    if [[ ! -f "${scams_db}" ]] || [[ ! -s "${scams_db}" ]]; then
        echo "[]" > "${scams_db}"
    fi
    
    # Append properly using jq
    jq ". += [$(cat "${output_file}")]" "${scams_db}" > "${scams_db}.tmp" && mv "${scams_db}.tmp" "${scams_db}"
    
    log_success "Scam detection complete: ${scams_detected}/${total_analyzed} scams found (${detection_rate}%)"
    echo ""
    echo "=== SCAM DETECTION REPORT ==="
    cat "${output_file}" | jq '.'
    echo ""
    echo "Report saved to: ${output_file}"
    
    # Send alert if critical
    if [[ "${threat_level}" == "CRITICAL" ]] && [[ "${ENABLE_ALERTS}" == "true" ]]; then
        send_scam_alert "CRITICAL: Major scam campaign detected for '${keyword}' - ${scams_detected} scams found"
    fi
}

get_threat_level() {
    local count=$1
    
    if [[ ${count} -ge 20 ]]; then
        echo "CRITICAL"
    elif [[ ${count} -ge 10 ]]; then
        echo "HIGH"
    elif [[ ${count} -ge 5 ]]; then
        echo "MEDIUM"
    elif [[ ${count} -gt 0 ]]; then
        echo "LOW"
    else
        echo "MINIMAL"
    fi
}

get_alert_priority() {
    local threat_level=$1
    
    case ${threat_level} in
        "CRITICAL") echo "P1 - IMMEDIATE ACTION REQUIRED" ;;
        "HIGH") echo "P2 - URGENT RESPONSE NEEDED" ;;
        "MEDIUM") echo "P3 - MONITOR CLOSELY" ;;
        "LOW") echo "P4 - ROUTINE MONITORING" ;;
        *) echo "P5 - INFORMATIONAL" ;;
    esac
}

get_scam_recommendations() {
    local count=$1
    local campaign=$2
    
    if [[ "${campaign}" == "true" ]]; then
        echo "CRITICAL: Coordinated scam campaign detected. Immediate actions: 1) Report all scam posts to Reddit admins 2) Notify affected subreddit moderators 3) Create public warning post 4) Document attack patterns for future detection 5) Monitor for similar campaigns"
    elif [[ ${count} -ge 10 ]]; then
        echo "HIGH PRIORITY: Significant scam activity detected. Actions: 1) Report scam posts to relevant subreddit moderators 2) Alert community members through appropriate channels 3) Document common patterns 4) Increase monitoring frequency"
    elif [[ ${count} -ge 5 ]]; then
        echo "MEDIUM PRIORITY: Moderate scam presence. Actions: 1) Report identified scams 2) Monitor for escalation 3) Share findings with relevant communities"
    else
        echo "LOW PRIORITY: Limited scam activity. Continue routine monitoring and report individual cases as identified."
    fi
}

send_scam_alert() {
    local message=$1
    
    if [[ -n "${ALERT_WEBHOOK_URL}" ]]; then
        curl -s -X POST "${ALERT_WEBHOOK_URL}" \
            -H "Content-Type: application/json" \
            -d "{\"text\": \"🚨 SCAM ALERT: ${message}\", \"priority\": \"high\"}" \
            2>/dev/null
    fi
    
    log_warn "ALERT: ${message}"
}

# Batch scam detection across multiple keywords
batch_scam_detection() {
    log_info "Starting batch scam detection..."
    
    # Common scam keywords
    local scam_keywords=(
        "free money"
        "crypto giveaway"
        "guaranteed profit"
        "investment opportunity"
        "double your bitcoin"
        "verify account"
        "claim prize"
        "urgent action required"
    )
    
    for keyword in "${scam_keywords[@]}"; do
        log_info "Scanning for: ${keyword}"
        detect_reddit_scams "${keyword}" "all"
        sleep 3  # Rate limiting
    done
    
    log_success "Batch scam detection completed"
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <keyword> [subreddit|all]"
        echo ""
        echo "Examples:"
        echo "  $0 'crypto giveaway' all"
        echo "  $0 'free money' cryptocurrency"
        echo "  $0 'guaranteed profit' wallstreetbets"
        echo ""
        echo "Or run batch detection:"
        echo "  $0 --batch"
        exit 1
    fi
    
    if [[ "$1" == "--batch" ]]; then
        batch_scam_detection
    else
        detect_reddit_scams "$1" "${2:-all}"
    fi
fi
