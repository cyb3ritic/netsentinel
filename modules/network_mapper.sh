#!/bin/bash

#############################################
# Reddit Network Mapper - ACCURACY FIXED
# Now detects actual user interactions
#############################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config/config.sh"
source "${SCRIPT_DIR}/utils/logger.sh"
source "${SCRIPT_DIR}/utils/reddit_api.sh"

map_reddit_user_network() {
    local seed_username=$1
    local depth=${2:-1}
    local max_users=${3:-20}
    local output_file="${DATA_DIR}/network_${seed_username}_$(date +%Y%m%d_%H%M%S).json"
    
    log_info "Mapping Reddit network for u/${seed_username} (depth: ${depth}, max users: ${max_users})"
    
    # Fetch seed user with retries
    local retry_count=0
    local seed_profile
    while [[ ${retry_count} -lt 3 ]]; do
        seed_profile=$(fetch_reddit_user "${seed_username}" 2>/dev/null)
        if [[ -n "${seed_profile}" ]] && [[ $(echo "${seed_profile}" | jq -r '.error' 2>/dev/null) == "null" ]]; then
            break
        fi
        log_warn "Retrying seed user fetch (attempt $((retry_count + 1)))"
        sleep $((retry_count + 1))
        ((retry_count++))
    done

    if [[ -z "${seed_profile}" ]]; then
        log_error "Failed to fetch seed user profile after retries"
        return 1
    fi

    # Initialize network structures
    declare -A nodes edges visited_users interaction_types
    nodes["${seed_username}"]="seed"
    visited_users["${seed_username}"]=1
    local total_nodes=1
    local total_edges=0

    # Fetch user activity
    log_info "Analyzing user interactions..."
    local comments_data posts_data
    
    comments_data=$(timeout $((CURL_TIMEOUT * 2)) fetch_reddit_user_comments "${seed_username}" 50)
    [[ $? -eq 124 ]] && log_warn "Comments fetch timed out"
    
    posts_data=$(timeout $((CURL_TIMEOUT * 2)) fetch_reddit_user_posts "${seed_username}" 50)
    [[ $? -eq 124 ]] && log_warn "Posts fetch timed out"

    echo ""
    log_info "Finding users who interacted with u/${seed_username}..."
    
    # METHOD 1: Find replies to seed user's comments
    local replies_found=0
    if [[ -n "${comments_data}" ]]; then
        while read -r comment; do
            local comment_id=$(echo "${comment}" | jq -r '.data.id' 2>/dev/null)
            local subreddit=$(echo "${comment}" | jq -r '.data.subreddit' 2>/dev/null)
            local permalink=$(echo "${comment}" | jq -r '.data.permalink' 2>/dev/null)
            
            [[ -z "${comment_id}" ]] || [[ "${comment_id}" == "null" ]] && continue
            
            # Fetch replies to this comment
            echo -n "  → Checking replies to comment ${comment_id}..."
            local replies=$(timeout 10 bash -c "source '${SCRIPT_DIR}/utils/subshell_init.sh'; fetch_reddit_api_endpoint 'https://oauth.reddit.com${permalink}.json'" 2>/dev/null)
            
            if [[ -n "${replies}" ]]; then
                # Extract reply authors
                local reply_count=0
                while read -r reply; do
                    local reply_author=$(echo "${reply}" | jq -r '.data.author' 2>/dev/null)
                    
                    if [[ "${reply_author}" != "[deleted]" ]] && \
                       [[ "${reply_author}" != "AutoModerator" ]] && \
                       [[ "${reply_author}" != "null" ]] && \
                       [[ "${reply_author}" != "${seed_username}" ]]; then
                        
                        # Add node
                        if [[ -z "${nodes[${reply_author}]}" ]]; then
                            if [[ ${total_nodes} -ge ${max_users} ]]; then
                                break 3
                            fi
                            nodes["${reply_author}"]="connected"
                            ((total_nodes++))
                        fi
                        
                        # Create edge with separator that won't appear in usernames
                        local edge_key="${reply_author}|||${seed_username}"
                        if [[ -z "${edges[${edge_key}]}" ]]; then
                            edges["${edge_key}"]="r/${subreddit}"
                            interaction_types["${edge_key}"]="replied_to_comment"
                            ((total_edges++))
                            ((reply_count++))
                            ((replies_found++))
                        fi
                    fi
                done < <(echo "${replies}" | jq -c '.[1].data.children[]? | select(.kind == "t1")' 2>/dev/null)
                
                if [[ ${reply_count} -gt 0 ]]; then
                    echo " found ${reply_count} replies"
                else
                    echo " no replies"
                fi
            else
                echo " failed"
            fi
            
            sleep 2  # Rate limiting
            
        done < <(echo "${comments_data}" | jq -c '.data.children[]?' 2>/dev/null | head -10)
    fi
    
    echo "  Found ${replies_found} users who replied to comments"
    
    # METHOD 2: Find commenters on seed user's posts
    local post_commenters=0
    if [[ -n "${posts_data}" ]]; then
        echo ""
        log_info "Finding users who commented on u/${seed_username}'s posts..."
        
        while read -r post; do
            local post_id=$(echo "${post}" | jq -r '.data.id' 2>/dev/null)
            local subreddit=$(echo "${post}" | jq -r '.data.subreddit' 2>/dev/null)
            local permalink=$(echo "${post}" | jq -r '.data.permalink' 2>/dev/null)
            local num_comments=$(echo "${post}" | jq -r '.data.num_comments' 2>/dev/null)
            
            [[ -z "${post_id}" ]] || [[ "${post_id}" == "null" ]] || [[ "${num_comments}" == "0" ]] && continue
            
            echo -n "  → Checking ${num_comments} comments on post ${post_id}..."
            local post_comments=$(timeout 10 bash -c "source '${SCRIPT_DIR}/utils/subshell_init.sh'; fetch_reddit_api_endpoint 'https://oauth.reddit.com${permalink}.json'" 2>/dev/null)
            
            if [[ -n "${post_comments}" ]]; then
                local commenter_count=0
                while read -r comment; do
                    local commenter=$(echo "${comment}" | jq -r '.data.author' 2>/dev/null)
                    
                    if [[ "${commenter}" != "[deleted]" ]] && \
                       [[ "${commenter}" != "AutoModerator" ]] && \
                       [[ "${commenter}" != "null" ]] && \
                       [[ "${commenter}" != "${seed_username}" ]]; then
                        
                        # Add node
                        if [[ -z "${nodes[${commenter}]}" ]]; then
                            if [[ ${total_nodes} -ge ${max_users} ]]; then
                                break 3
                            fi
                            nodes["${commenter}"]="connected"
                            ((total_nodes++))
                        fi
                        
                        # Create edge
                        local edge_key="${commenter}|||${seed_username}"
                        if [[ -z "${edges[${edge_key}]}" ]]; then
                            edges["${edge_key}"]="r/${subreddit}"
                            interaction_types["${edge_key}"]="commented_on_post"
                            ((total_edges++))
                            ((commenter_count++))
                            ((post_commenters++))
                        fi
                    fi
                done < <(echo "${post_comments}" | jq -c '.[1].data.children[]? | select(.kind == "t1")' 2>/dev/null)
                
                if [[ ${commenter_count} -gt 0 ]]; then
                    echo " found ${commenter_count} commenters"
                else
                    echo " no valid commenters"
                fi
            else
                echo " failed"
            fi
            
            sleep 2  # Rate limiting
            
        done < <(echo "${posts_data}" | jq -c '.data.children[]?' 2>/dev/null | head -10)
    fi
    
    echo "  Found ${post_commenters} users who commented on posts"
    
    echo ""
    log_info "Network collection complete: ${total_nodes} nodes, ${total_edges} edges"
    
    # Calculate accurate metrics
    declare -A in_degrees out_degrees node_degrees
    
    for edge_key in "${!edges[@]}"; do
        # Split using ||| separator
        local source="${edge_key%%|||*}"
        local target="${edge_key#*|||}"
        
        # Out-degree: edges going OUT from this user (they interacted)
        out_degrees["${source}"]=$((${out_degrees[${source}]:-0} + 1))
        
        # In-degree: edges coming IN to this user (others interacted with them)
        in_degrees["${target}"]=$((${in_degrees[${target}]:-0} + 1))
        
        # Total degree
        node_degrees["${source}"]=$((${node_degrees[${source}]:-0} + 1))
        node_degrees["${target}"]=$((${node_degrees[${target}]:-0} + 1))
    done
    
    # Find top 5 connected users
    local hubs=()
    for username in "${!node_degrees[@]}"; do
        local degree=${node_degrees[${username}]}
        hubs+=("${degree}:${username}")
    done
    local top_hubs=$(printf '%s\n' "${hubs[@]}" | sort -rn | head -5)
    
    # Calculate average
    local avg_connections=0
    if [[ ${total_nodes} -gt 0 ]]; then
        avg_connections=$(awk "BEGIN {printf \"%.2f\", ${total_edges}/${total_nodes}}")
    fi
    
    # Anomaly detection (revised thresholds)
    local anomaly_score=0
    declare -a anomalies
    
    for username in "${!node_degrees[@]}"; do
        local degree=${node_degrees[${username}]}
        local in_deg=${in_degrees[${username}]:-0}
        local out_deg=${out_degrees[${username}]:-0}
        
        # High interaction count
        if [[ ${degree} -gt 15 ]]; then
            anomaly_score=$((anomaly_score + 5))
            anomalies+=("User u/${username} has high interaction count: ${degree}")
        fi
        
        # Suspicious in-degree (many people interacting with them)
        if [[ ${in_deg} -gt 10 ]] && [[ ${username} != "${seed_username}" ]]; then
            anomaly_score=$((anomaly_score + 3))
            anomalies+=("User u/${username} receives many interactions: ${in_deg} in-degree")
        fi
    done
    
    # Network health
    local network_health="HEALTHY"
    if [[ ${anomaly_score} -ge 30 ]]; then
        network_health="SUSPICIOUS"
    elif [[ ${anomaly_score} -ge 15 ]]; then
        network_health="QUESTIONABLE"
    fi
    
    # Build JSON outputs with proper escaping
    local nodes_json="["
    local first=true
    for username in "${!nodes[@]}"; do
        [[ "${first}" == "false" ]] && nodes_json+=","
        local degree=${node_degrees[${username}]:-0}
        local in_deg=${in_degrees[${username}]:-0}
        local out_deg=${out_degrees[${username}]:-0}
        local node_type="${nodes[${username}]}"
        
        # Escape username for JSON
        local escaped_username=$(echo "${username}" | jq -R . | sed 's/^"//;s/"$//')
        
        nodes_json+="{\"id\":\"${escaped_username}\",\"label\":\"u/${escaped_username}\",\"degree\":${degree},\"in_degree\":${in_deg},\"out_degree\":${out_deg},\"type\":\"${node_type}\"}"
        first=false
    done
    nodes_json+="]"

    local edges_json="["
    first=true
    for edge_key in "${!edges[@]}"; do
        local source="${edge_key%%|||*}"
        local target="${edge_key#*|||}"
        local subreddit="${edges[${edge_key}]}"
        local interaction_type="${interaction_types[${edge_key}]}"
        
        # Escape for JSON
        local escaped_source=$(echo "${source}" | jq -R . | sed 's/^"//;s/"$//')
        local escaped_target=$(echo "${target}" | jq -R . | sed 's/^"//;s/"$//')
        
        [[ "${first}" == "false" ]] && edges_json+=","
        edges_json+="{\"source\":\"${escaped_source}\",\"target\":\"${escaped_target}\",\"location\":\"${subreddit}\",\"interaction_type\":\"${interaction_type}\"}"
        first=false
    done
    edges_json+="]"
    
    local hubs_json="["
    first=true
    while IFS=':' read -r degree username; do
        [[ -z "${username}" ]] && continue
        local in_deg=${in_degrees[${username}]:-0}
        local out_deg=${out_degrees[${username}]:-0}
        [[ "${first}" == "false" ]] && hubs_json+=","
        hubs_json+="{\"username\":\"${username}\",\"total_connections\":${degree},\"in_degree\":${in_deg},\"out_degree\":${out_deg}}"
        first=false
    done <<< "${top_hubs}"
    hubs_json+="]"
    
    local anomalies_json="[]"
    if [[ ${#anomalies[@]} -gt 0 ]]; then
        anomalies_json=$(printf '%s\n' "${anomalies[@]}" | jq -R . | jq -s .)
    fi
    
    # Network density (directed graph)
    local max_possible_edges=0
    if [[ ${total_nodes} -gt 1 ]]; then
        max_possible_edges=$((total_nodes * (total_nodes - 1)))
    fi
    
    local network_density=0
    if [[ ${max_possible_edges} -gt 0 ]]; then
        network_density=$(awk "BEGIN {printf \"%.6f\", ${total_edges}/${max_possible_edges}}")
    fi
    
    # Generate report
    cat > "${output_file}" << EOF
{
    "analysis_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "platform": "Reddit",
    "seed_user": "${seed_username}",
    "analysis_depth": ${depth},
    "max_users_limit": ${max_users},
    "methodology": "Detects actual interactions: replies to comments and comments on posts",
    "network_metrics": {
        "total_nodes": ${total_nodes},
        "total_edges": ${total_edges},
        "average_connections": ${avg_connections},
        "network_density": ${network_density},
        "network_health": "${network_health}"
    },
    "anomaly_detection": {
        "anomaly_score": ${anomaly_score},
        "detected_anomalies": ${anomalies_json}
    },
    "key_hubs": ${hubs_json},
    "graph_data": {
        "nodes": ${nodes_json},
        "edges": ${edges_json}
    }
}
EOF
    
    echo ""
    log_success "Network mapping complete!"
    echo ""
    echo "=== NETWORK SUMMARY ==="
    echo "  Users analyzed: ${total_nodes}"
    echo "  Actual interactions found: ${total_edges}"
    echo "  Network health: ${network_health}"
    echo "  Anomaly score: ${anomaly_score}/100"
    echo ""
    echo "Full report: ${output_file}"
    echo ""
    
    # Show top connections
    echo "Top Connected Users:"
    local rank=1
    while IFS=':' read -r degree username; do
        [[ -z "${username}" ]] && continue
        local in_deg=${in_degrees[${username}]:-0}
        local out_deg=${out_degrees[${username}]:-0}
        echo "  ${rank}. u/${username} - ${degree} total (${in_deg} in, ${out_deg} out)"
        ((rank++))
    done <<< "${top_hubs}"
}

# Quick network snapshot (unchanged)
quick_network_snapshot() {
    local username=$1
    local output_file="${DATA_DIR}/network_quick_${username}_$(date +%Y%m%d_%H%M%S).json"
    
    log_info "Quick network snapshot for u/${username}"
    
    echo -n "Fetching user data..."
    local user_data=$(timeout 10 bash -c "source '${SCRIPT_DIR}/utils/subshell_init.sh'; fetch_reddit_user '${username}'" 2>/dev/null)
    if [[ -z "${user_data}" ]]; then
        echo " ✗"
        log_error "Failed to fetch user"
        return 1
    fi
    echo " ✓"
    
    echo -n "Analyzing recent activity..."
    local comments=$(timeout 10 bash -c "source '${SCRIPT_DIR}/utils/subshell_init.sh'; fetch_reddit_user_comments '${username}' 50" 2>/dev/null)
    local posts=$(timeout 10 bash -c "source '${SCRIPT_DIR}/utils/subshell_init.sh'; fetch_reddit_user_posts '${username}' 50" 2>/dev/null)
    echo " ✓"
    
    declare -A subreddit_activity
    local total_activity=0
    
    if [[ -n "${comments}" ]]; then
        while read -r comment; do
            local sub=$(echo "${comment}" | jq -r '.data.subreddit' 2>/dev/null)
            [[ -n "${sub}" ]] && subreddit_activity["${sub}"]=$((${subreddit_activity["${sub}"]:-0} + 1))
            ((total_activity++))
        done < <(echo "${comments}" | jq -c '.data.children[]?' 2>/dev/null)
    fi
    
    if [[ -n "${posts}" ]]; then
        while read -r post; do
            local sub=$(echo "${post}" | jq -r '.data.subreddit' 2>/dev/null)
            [[ -n "${sub}" ]] && subreddit_activity["${sub}"]=$((${subreddit_activity["${sub}"]:-0} + 1))
            ((total_activity++))
        done < <(echo "${posts}" | jq -c '.data.children[]?' 2>/dev/null)
    fi
    
    local subreddit_json="["
    local first=true
    for sub in "${!subreddit_activity[@]}"; do
        [[ "${first}" == "false" ]] && subreddit_json+=","
        subreddit_json+="{\"subreddit\":\"${sub}\",\"activity_count\":${subreddit_activity["${sub}"]},\"percentage\":$(awk "BEGIN {printf \"%.1f\", (${subreddit_activity["${sub}"]}/${total_activity})*100}")}"
        first=false
    done
    subreddit_json+="]"
    
    cat > "${output_file}" << EOF
{
    "analysis_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "username": "${username}",
    "total_activities_analyzed": ${total_activity},
    "unique_subreddits": ${#subreddit_activity[@]},
    "subreddit_distribution": ${subreddit_json}
}
EOF
    
    echo ""
    log_success "Quick snapshot complete!"
    cat "${output_file}" | jq '.'
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <username> [depth] [max_users]"
        echo "       $0 --quick <username>"
        echo ""
        echo "Examples:"
        echo "  $0 Samip-Shah 1 20          # Standard (depth 1, max 20 users)"
        echo "  $0 Samip-Shah 2 50          # Deeper analysis"
        echo "  $0 --quick Samip-Shah       # Fast snapshot only"
        exit 1
    fi
    
    if [[ "$1" == "--quick" ]]; then
        quick_network_snapshot "$2"
    else
        map_reddit_user_network "$1" "${2:-1}" "${3:-20}"
    fi
fi