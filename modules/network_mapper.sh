#!/bin/bash

#############################################
# Reddit Network Mapper - OPTIMIZED VERSION
# With progress indicators and timeouts
#############################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config/config.sh"
source "${SCRIPT_DIR}/utils/logger.sh"
source "${SCRIPT_DIR}/utils/reddit_api.sh"

# Progress spinner
show_spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    
    while ps -p $pid > /dev/null 2>&1; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

map_reddit_user_network() {
    local seed_username=$1
    local depth=${2:-1}  # Reduced default depth to 1 for faster execution
    local max_users=${3:-20}  # Limit total users to analyze
    local output_file="${DATA_DIR}/network_${seed_username}_$(date +%Y%m%d_%H%M%S).json"
    
    log_info "Mapping Reddit network for u/${seed_username} (depth: ${depth}, max users: ${max_users})"
    
    # Fetch seed user profile with timeout
    log_info "Fetching seed user profile..."
    local seed_profile=$(timeout 10 fetch_reddit_user "${seed_username}" 2>/dev/null)
    
    if [[ -z "${seed_profile}" ]] || [[ $? -ne 0 ]]; then
        log_error "Failed to fetch seed user profile (timeout or API error)"
        return 1
    fi
    
    # Initialize network data structures
    declare -A nodes
    declare -A edges
    declare -A visited_users
    declare -A user_subreddits
    declare -A interaction_count
    
    # Add seed node
    nodes["${seed_username}"]="seed"
    visited_users["${seed_username}"]=1
    
    # Counters
    local total_nodes=1
    local total_edges=0
    local users_processed=0
    
    log_info "Analyzing user activity patterns..."
    
    # Analyze seed user's activity (limited to recent)
    echo -n "  → Fetching comments..."
    local comments_data=$(timeout 10 fetch_reddit_user_comments "${seed_username}" 25 2>/dev/null)
    echo " ✓"
    
    echo -n "  → Fetching posts..."
    local posts_data=$(timeout 10 fetch_reddit_user_posts "${seed_username}" 25 2>/dev/null)
    echo " ✓"
    
    if [[ -z "${comments_data}" ]] && [[ -z "${posts_data}" ]]; then
        log_warn "No activity data found for user"
    fi
    
    # Extract subreddits from user activity
    local top_subreddits=()
    
    if [[ -n "${comments_data}" ]]; then
        while read -r comment; do
            local subreddit=$(echo "${comment}" | jq -r '.data.subreddit' 2>/dev/null)
            [[ -n "${subreddit}" ]] && user_subreddits["${seed_username}:${subreddit}"]=$((${user_subreddits["${seed_username}:${subreddit}"]:-0} + 1))
        done < <(echo "${comments_data}" | jq -c '.data.children[]?' 2>/dev/null)
    fi
    
    if [[ -n "${posts_data}" ]]; then
        while read -r post; do
            local subreddit=$(echo "${post}" | jq -r '.data.subreddit' 2>/dev/null)
            [[ -n "${subreddit}" ]] && user_subreddits["${seed_username}:${subreddit}"]=$((${user_subreddits["${seed_username}:${subreddit}"]:-0} + 1))
        done < <(echo "${posts_data}" | jq -c '.data.children[]?' 2>/dev/null)
    fi
    
    # Get top 2 most active subreddits (reduced from 3)
    for key in "${!user_subreddits[@]}"; do
        if [[ "${key}" == "${seed_username}:"* ]]; then
            local sub=$(echo "${key}" | cut -d: -f2)
            local count=${user_subreddits["${key}"]}
            top_subreddits+=("${count}:${sub}")
        fi
    done
    
    # Sort and limit
    local sorted_subs=$(printf '%s\n' "${top_subreddits[@]}" | sort -rn | head -2)
    
    log_info "Found ${#top_subreddits[@]} active subreddits, analyzing top 2..."
    
    # Analyze connections in top subreddits
    local sub_count=0
    while IFS=':' read -r count subreddit; do
        [[ -z "${subreddit}" ]] && continue
        
        ((sub_count++))
        echo ""
        log_info "[${sub_count}/2] Analyzing r/${subreddit} (${count} activities)..."
        
        # Fetch recent posts from subreddit (reduced limit)
        echo -n "  → Fetching recent posts..."
        local subreddit_posts=$(timeout 15 fetch_subreddit_posts "${subreddit}" "new" 15 2>/dev/null)
        
        if [[ -z "${subreddit_posts}" ]] || [[ $? -ne 0 ]]; then
            echo " ✗ (timeout/failed)"
            continue
        fi
        echo " ✓"
        
        # Extract authors and create connections
        local authors_found=0
        while read -r post; do
            # Check if we've reached max users
            if [[ ${total_nodes} -ge ${max_users} ]]; then
                log_warn "Reached maximum user limit (${max_users}), stopping..."
                break 2
            fi
            
            local author=$(echo "${post}" | jq -r '.data.author' 2>/dev/null)
            
            # Skip invalid authors
            if [[ "${author}" == "[deleted]" ]] || [[ "${author}" == "AutoModerator" ]] || [[ "${author}" == "null" ]] || [[ "${author}" == "${seed_username}" ]]; then
                continue
            fi
            
            # Add to nodes
            if [[ -z "${nodes[${author}]}" ]]; then
                nodes["${author}"]="connected"
                ((total_nodes++))
                ((authors_found++))
            fi
            
            # Create edge
            local edge_key="${seed_username}->${author}"
            if [[ -z "${edges[${edge_key}]}" ]]; then
                edges["${edge_key}"]="${subreddit}"
                interaction_count["${edge_key}"]=1
                ((total_edges++))
            else
                interaction_count["${edge_key}"]=$((${interaction_count["${edge_key}"]} + 1))
            fi
            
        done < <(echo "${subreddit_posts}" | jq -c '.data.children[]?' 2>/dev/null)
        
        echo "  → Found ${authors_found} connected users in r/${subreddit}"
        
        # Rate limiting
        sleep 2
        
    done <<< "${sorted_subs}"
    
    echo ""
    log_info "Network collection complete: ${total_nodes} nodes, ${total_edges} edges"
    
    # Calculate metrics
    declare -A node_degrees
    declare -A in_degrees
    declare -A out_degrees
    
    for edge_key in "${!edges[@]}"; do
        local source=$(echo "${edge_key}" | cut -d'>' -f1 | tr -d '-')
        local target=$(echo "${edge_key}" | cut -d'>' -f2)
        
        node_degrees["${source}"]=$((${node_degrees[${source}]:-0} + 1))
        node_degrees["${target}"]=$((${node_degrees[${target}]:-0} + 1))
        out_degrees["${source}"]=$((${out_degrees[${source}]:-0} + 1))
        in_degrees["${target}"]=$((${in_degrees[${target}]:-0} + 1))
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
    
    # Anomaly detection
    local anomaly_score=0
    declare -a anomalies
    
    for username in "${!node_degrees[@]}"; do
        local degree=${node_degrees[${username}]}
        if [[ ${degree} -gt 20 ]]; then
            anomaly_score=$((anomaly_score + 5))
            anomalies+=("User u/${username} has high connections: ${degree}")
        fi
    done
    
    # Network health
    local network_health="HEALTHY"
    if [[ ${anomaly_score} -ge 30 ]]; then
        network_health="SUSPICIOUS"
    elif [[ ${anomaly_score} -ge 15 ]]; then
        network_health="QUESTIONABLE"
    fi
    
    # Build JSON outputs
    local nodes_json="["
    local first=true
    for username in "${!nodes[@]}"; do
        [[ "${first}" == "false" ]] && nodes_json+=","
        local degree=${node_degrees[${username}]:-0}
        local in_deg=${in_degrees[${username}]:-0}
        local out_deg=${out_degrees[${username}]:-0}
        local node_type="${nodes[${username}]}"
        
        nodes_json+="{\"id\":\"${username}\",\"label\":\"u/${username}\",\"degree\":${degree},\"in_degree\":${in_deg},\"out_degree\":${out_deg},\"type\":\"${node_type}\"}"
        first=false
    done
    nodes_json+="]"
    
    local edges_json="["
    first=true
    for edge_key in "${!edges[@]}"; do
        local source=$(echo "${edge_key}" | cut -d'>' -f1 | tr -d '-')
        local target=$(echo "${edge_key}" | cut -d'>' -f2)
        local subreddit="${edges[${edge_key}]}"
        local weight=${interaction_count[${edge_key}]:-1}
        
        [[ "${first}" == "false" ]] && edges_json+=","
        edges_json+="{\"source\":\"${source}\",\"target\":\"${target}\",\"subreddit\":\"${subreddit}\",\"weight\":${weight}}"
        first=false
    done
    edges_json+="]"
    
    local hubs_json="["
    first=true
    while IFS=':' read -r degree username; do
        [[ -z "${username}" ]] && continue
        [[ "${first}" == "false" ]] && hubs_json+=","
        hubs_json+="{\"username\":\"${username}\",\"connections\":${degree}}"
        first=false
    done <<< "${top_hubs}"
    hubs_json+="]"
    
    local anomalies_json="[]"
    if [[ ${#anomalies[@]} -gt 0 ]]; then
        anomalies_json=$(printf '%s\n' "${anomalies[@]}" | jq -R . | jq -s .)
    fi
    
    # Network density
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
    echo "  Connections found: ${total_edges}"
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
        echo "  ${rank}. u/${username} - ${degree} connections"
        ((rank++))
    done <<< "${top_hubs}"
}

# Quick network snapshot (fast mode)
quick_network_snapshot() {
    local username=$1
    local output_file="${DATA_DIR}/network_quick_${username}_$(date +%Y%m%d_%H%M%S).json"
    
    log_info "Quick network snapshot for u/${username}"
    
    echo -n "Fetching user data..."
    local user_data=$(timeout 10 fetch_reddit_user "${username}" 2>/dev/null)
    
    if [[ -z "${user_data}" ]]; then
        echo " ✗"
        log_error "Failed to fetch user"
        return 1
    fi
    echo " ✓"
    
    echo -n "Analyzing recent activity..."
    local comments=$(timeout 10 fetch_reddit_user_comments "${username}" 50 2>/dev/null)
    local posts=$(timeout 10 fetch_reddit_user_posts "${username}" 50 2>/dev/null)
    echo " ✓"
    
    declare -A subreddit_activity
    local total_activity=0
    
    # Process comments
    if [[ -n "${comments}" ]]; then
        while read -r comment; do
            local sub=$(echo "${comment}" | jq -r '.data.subreddit' 2>/dev/null)
            [[ -n "${sub}" ]] && subreddit_activity["${sub}"]=$((${subreddit_activity["${sub}"]:-0} + 1))
            ((total_activity++))
        done < <(echo "${comments}" | jq -c '.data.children[]?' 2>/dev/null)
    fi
    
    # Process posts
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
