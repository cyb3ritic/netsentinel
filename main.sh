#!/bin/bash

#############################################
# Reddit Social Threat Intelligence System
# Main Control Script - Updated for Reddit
#############################################

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration and utilities
source "${SCRIPT_DIR}/config/config.sh"
source "${SCRIPT_DIR}/utils/logger.sh"
source "${SCRIPT_DIR}/utils/reddit_api.sh"

# Initialize directories
initialize_directories() {
    log_info "Initializing directory structure..."
    mkdir -p "${DATA_DIR}/"{profiles,trends,reports,cache,networks}
    mkdir -p "${LOG_DIR}"
    mkdir -p "${REPORT_DIR}"
    
    # Initialize JSON databases if they don't exist
    [[ ! -f "${DATA_DIR}/profiles/suspicious_profiles.json" ]] && echo "[]" > "${DATA_DIR}/profiles/suspicious_profiles.json"
    [[ ! -f "${DATA_DIR}/scams_detected.json" ]] && echo "[]" > "${DATA_DIR}/scams_detected.json"
    
    chmod 755 "${DATA_DIR}" "${LOG_DIR}" "${REPORT_DIR}"
}

# Display banner
show_banner() {
    echo -e "${BLUE}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║   Reddit Social Threat Intelligence System               ║
║   Scam Detection & Network Analysis Platform             ║
║   Version 2.0 - November 2025                            ║
╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo -e "${CYAN}Platform: Reddit | Mode: Free API | Status: Active${NC}"
    echo ""
}

# Main menu
show_menu() {
    echo -e "\n${GREEN}╔════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          MAIN MENU                 ║${NC}"
    echo -e "${GREEN}╔════════════════════════════════════╗${NC}"
    echo -e "${CYAN}1.${NC} Profile Analysis (Fake Account Detection)"
    echo -e "${CYAN}2.${NC} Keyword & Trend Monitoring"
    echo -e "${CYAN}3.${NC} Scam Pattern Detection"
    echo -e "${CYAN}4.${NC} Network Mapping & Analysis"
    echo -e "${CYAN}5.${NC} Generate Threat Intelligence Report"
    echo -e "${CYAN}6.${NC} Run Full System Scan"
    echo -e "${CYAN}7.${NC} Batch Operations"
    echo -e "${CYAN}8.${NC} Configuration & Settings"
    echo -e "${CYAN}9.${NC} View Logs & Statistics"
    echo -e "${RED}0.${NC} Exit"
    echo -e "${GREEN}╚════════════════════════════════════╝${NC}"
    echo -n "Select option [0-9]: "
}

# Profile analysis module
run_profile_analysis() {
    log_info "Starting Reddit profile analysis module..."
    
    if [[ -f "${SCRIPT_DIR}/modules/reddit_profile_analyzer.sh" ]]; then
        bash "${SCRIPT_DIR}/modules/reddit_profile_analyzer.sh" "$@"
    elif [[ -f "${SCRIPT_DIR}/modules/profile_analyzer.sh" ]]; then
        bash "${SCRIPT_DIR}/modules/profile_analyzer.sh" "$@"
    else
        log_error "Profile analyzer module not found!"
        return 1
    fi
}

# Keyword monitoring module
run_keyword_monitor() {
    log_info "Starting Reddit keyword monitoring module..."
    
    if [[ -f "${SCRIPT_DIR}/modules/hashtag_monitor.sh" ]]; then
        bash "${SCRIPT_DIR}/modules/hashtag_monitor.sh" "$@"
    else
        log_error "Keyword monitor module not found!"
        return 1
    fi
}

# Scam detection module
run_scam_detector() {
    log_info "Starting Reddit scam detection module..."
    
    if [[ -f "${SCRIPT_DIR}/modules/scam_detector.sh" ]]; then
        bash "${SCRIPT_DIR}/modules/scam_detector.sh" "$@"
    else
        log_error "Scam detector module not found!"
        return 1
    fi
}

# Network mapping module
run_network_mapper() {
    log_info "Starting Reddit network mapping module..."
    
    if [[ -f "${SCRIPT_DIR}/modules/network_mapper.sh" ]]; then
        bash "${SCRIPT_DIR}/modules/network_mapper.sh" "$@"
    else
        log_error "Network mapper module not found!"
        return 1
    fi
}

# Generate comprehensive report
generate_report() {
    log_info "Generating comprehensive threat intelligence report..."
    
    local report_file="${REPORT_DIR}/threat_intel_report_$(date +%Y%m%d_%H%M%S).html"
    local report_json="${REPORT_DIR}/threat_intel_report_$(date +%Y%m%d_%H%M%S).json"
    
    # Count statistics
    local total_profiles=$(find "${DATA_DIR}/profiles" -name "reddit_*.json" -type f 2>/dev/null | wc -l)
    local suspicious_profiles=$(jq 'length' "${DATA_DIR}/profiles/suspicious_profiles.json" 2>/dev/null || echo 0)
    local total_scans=$(jq 'length' "${DATA_DIR}/scams_detected.json" 2>/dev/null || echo 0)
    local total_scams=0
    
    # Calculate total scams from all scam reports
    if [[ -f "${DATA_DIR}/scams_detected.json" ]]; then
        total_scams=$(jq '[.[].detection_summary.scams_detected] | add' "${DATA_DIR}/scams_detected.json" 2>/dev/null || echo 0)
    fi
    
    local network_analyses=$(find "${DATA_DIR}" -name "network_*.json" -type f 2>/dev/null | wc -l)
    
    # Generate HTML report
    cat > "${report_file}" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Reddit Threat Intelligence Report</title>
    <meta charset="UTF-8">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f5f5f5; padding: 20px; }
        .container { max-width: 1200px; margin: 0 auto; background: white; box-shadow: 0 0 20px rgba(0,0,0,0.1); }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; }
        .header h1 { font-size: 2em; margin-bottom: 10px; }
        .header p { opacity: 0.9; font-size: 0.9em; }
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; padding: 30px; }
        .stat-card { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 25px; border-radius: 10px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
        .stat-card h3 { font-size: 0.9em; opacity: 0.9; margin-bottom: 10px; }
        .stat-card .number { font-size: 2.5em; font-weight: bold; }
        .section { margin: 20px 30px; padding: 20px; border-left: 4px solid #667eea; background: #f8f9fa; }
        .critical { border-color: #e74c3c; background: #fadbd8; }
        .warning { border-color: #f39c12; background: #fdebd0; }
        .info { border-color: #3498db; background: #d6eaf8; }
        .success { border-color: #27ae60; background: #d5f4e6; }
        table { width: 100%; border-collapse: collapse; margin: 15px 0; }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background-color: #667eea; color: white; font-weight: 600; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        .timestamp { font-size: 0.85em; color: #666; margin-top: 10px; }
        .footer { background: #2c3e50; color: white; padding: 20px 30px; text-align: center; }
        pre { background: #282c34; color: #abb2bf; padding: 15px; border-radius: 5px; overflow-x: auto; font-size: 0.85em; }
        .badge { display: inline-block; padding: 5px 10px; border-radius: 15px; font-size: 0.8em; font-weight: bold; margin: 2px; }
        .badge-critical { background: #e74c3c; color: white; }
        .badge-high { background: #f39c12; color: white; }
        .badge-medium { background: #3498db; color: white; }
        .badge-low { background: #27ae60; color: white; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔍 Reddit Threat Intelligence Report</h1>
            <p>Generated: $(date '+%B %d, %Y at %H:%M:%S %Z')</p>
            <p>Platform: Reddit | Analysis Type: Comprehensive Security Assessment</p>
        </div>
        
        <div class="stats-grid">
            <div class="stat-card">
                <h3>PROFILES ANALYZED</h3>
                <div class="number">${total_profiles}</div>
            </div>
            <div class="stat-card">
                <h3>SUSPICIOUS ACCOUNTS</h3>
                <div class="number">${suspicious_profiles}</div>
            </div>
            <div class="stat-card">
                <h3>SCAMS DETECTED</h3>
                <div class="number">${total_scams}</div>
            </div>
            <div class="stat-card">
                <h3>NETWORK ANALYSES</h3>
                <div class="number">${network_analyses}</div>
            </div>
        </div>
EOF

    # Add suspicious profiles section
    if [[ ${suspicious_profiles} -gt 0 ]]; then
        echo "<div class='section critical'>" >> "${report_file}"
        echo "<h2>🚨 Suspicious Profiles Detected</h2>" >> "${report_file}"
        echo "<p><span class='badge badge-critical'>CRITICAL</span> ${suspicious_profiles} suspicious account(s) identified</p>" >> "${report_file}"
        echo "<table><tr><th>Username</th><th>Risk Level</th><th>Suspicion Score</th><th>Classification</th></tr>" >> "${report_file}"
        
        jq -r '.[] | "<tr><td>u/\(.username)</td><td>\(.risk_level)</td><td>\(.suspicion_score)/100</td><td>\(.classification)</td></tr>"' \
            "${DATA_DIR}/profiles/suspicious_profiles.json" 2>/dev/null >> "${report_file}" || echo "<tr><td colspan='4'>No data available</td></tr>" >> "${report_file}"
        
        echo "</table></div>" >> "${report_file}"
    else
        echo "<div class='section success'><h2>✅ Profile Analysis</h2><p>No suspicious profiles detected in recent analyses.</p></div>" >> "${report_file}"
    fi
    
    # Add scam detection section
    if [[ ${total_scams} -gt 0 ]]; then
        echo "<div class='section warning'>" >> "${report_file}"
        echo "<h2>⚠️ Scam Campaigns Identified</h2>" >> "${report_file}"
        echo "<p><span class='badge badge-high'>HIGH PRIORITY</span> ${total_scams} scam post(s) detected across ${total_scans} scan(s)</p>" >> "${report_file}"
        
        if [[ -f "${DATA_DIR}/scams_detected.json" ]]; then
            echo "<h3>Recent Scam Detections:</h3>" >> "${report_file}"
            jq -r '.[-5:] | .[] | "<div style=\"margin: 10px 0; padding: 10px; background: white; border-radius: 5px;\"><strong>Keyword:</strong> \(.keyword_searched)<br><strong>Threat Level:</strong> <span class=\"badge badge-\(.detection_summary.threat_level | ascii_downcase)\">\(.detection_summary.threat_level)</span><br><strong>Detection Rate:</strong> \(.detection_summary.detection_rate_percentage)%<br><strong>Timestamp:</strong> \(.analysis_timestamp)</div>"' \
                "${DATA_DIR}/scams_detected.json" 2>/dev/null >> "${report_file}"
        fi
        
        echo "</div>" >> "${report_file}"
    else
        echo "<div class='section info'><h2>🛡️ Scam Detection</h2><p>No scams detected in recent scans.</p></div>" >> "${report_file}"
    fi
    
    # Add network analysis section
    if [[ ${network_analyses} -gt 0 ]]; then
        echo "<div class='section info'>" >> "${report_file}"
        echo "<h2>🕸️ Network Analysis Summary</h2>" >> "${report_file}"
        echo "<p>${network_analyses} network mapping(s) completed</p>" >> "${report_file}"
        
        # Get latest network analysis
        local latest_network=$(find "${DATA_DIR}" -name "network_*.json" -type f 2>/dev/null | sort -r | head -1)
        if [[ -n "${latest_network}" ]]; then
            echo "<h3>Latest Network Analysis:</h3>" >> "${report_file}"
            echo "<pre>$(jq '.network_metrics' "${latest_network}" 2>/dev/null || echo "No data")</pre>" >> "${report_file}"
        fi
        
        echo "</div>" >> "${report_file}"
    fi
    
    # Footer
    cat >> "${report_file}" << EOF
        <div class="footer">
            <p>Reddit Social Threat Intelligence System v2.0</p>
            <p>Report generated automatically by threat intelligence platform</p>
            <div class="timestamp">$(date -u '+%Y-%m-%d %H:%M:%S UTC')</div>
        </div>
    </div>
</body>
</html>
EOF
    
    # Generate JSON report for programmatic access
    cat > "${report_json}" << EOF
{
    "report_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "platform": "Reddit",
    "statistics": {
        "total_profiles_analyzed": ${total_profiles},
        "suspicious_profiles": ${suspicious_profiles},
        "total_scams_detected": ${total_scams},
        "scam_scans_performed": ${total_scans},
        "network_analyses": ${network_analyses}
    },
    "suspicious_profiles": $(cat "${DATA_DIR}/profiles/suspicious_profiles.json" 2>/dev/null || echo "[]"),
    "recent_scam_detections": $(jq '.[-5:]' "${DATA_DIR}/scams_detected.json" 2>/dev/null || echo "[]")
}
EOF
    
    log_success "Reports generated successfully!"
    echo ""
    echo -e "${GREEN}📊 HTML Report:${NC} ${report_file}"
    echo -e "${GREEN}📋 JSON Report:${NC} ${report_json}"
    echo ""
    
    # Try to open HTML report
    if command -v xdg-open &> /dev/null; then
        read -p "Open HTML report in browser? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            xdg-open "${report_file}" 2>/dev/null &
        fi
    fi
}

# Full system scan
run_full_scan() {
    echo ""
    echo -e "${MAGENTA}╔════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║      FULL SYSTEM SCAN              ║${NC}"
    echo -e "${MAGENTA}╔════════════════════════════════════╗${NC}"
    echo ""
    
    echo -n "Enter Reddit username OR keyword to scan: "
    read -r target
    
    if [[ -z "${target}" ]]; then
        log_error "Target cannot be empty"
        return 1
    fi
    
    echo -n "Enter subreddit to focus on (or 'all'): "
    read -r subreddit
    subreddit=${subreddit:-all}
    
    log_info "Starting comprehensive scan for: ${target}"
    echo ""
    
    # Module 1: Profile Analysis
    echo -e "${CYAN}[1/4]${NC} Running Profile Analysis..."
    run_profile_analysis "${target}" 2>/dev/null
    sleep 2
    
    # Module 2: Keyword Monitoring
    echo -e "${CYAN}[2/4]${NC} Running Keyword Monitoring..."
    run_keyword_monitor "${target}" "${subreddit}" 2>/dev/null
    sleep 2
    
    # Module 3: Scam Detection
    echo -e "${CYAN}[3/4]${NC} Running Scam Detection..."
    run_scam_detector "${target}" "${subreddit}" 2>/dev/null
    sleep 2
    
    # Module 4: Network Analysis
    echo -e "${CYAN}[4/4]${NC} Running Network Analysis..."
    run_network_mapper "${target}" 1 20 2>/dev/null
    
    echo ""
    log_success "Full system scan completed!"
    
    # Generate comprehensive report
    echo ""
    read -p "Generate comprehensive report? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        generate_report
    fi
}

# Batch operations
batch_operations() {
    echo ""
    echo -e "${YELLOW}╔════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║      BATCH OPERATIONS              ║${NC}"
    echo -e "${YELLOW}╔════════════════════════════════════╗${NC}"
    echo "1. Batch Profile Analysis (from file)"
    echo "2. Batch Scam Detection (common keywords)"
    echo "3. Monitor Multiple Subreddits"
    echo "4. Back to Main Menu"
    echo -n "Select option: "
    read -r batch_option
    
    case ${batch_option} in
        1)
            echo -n "Enter file with usernames (one per line): "
            read -r userfile
            if [[ -f "${userfile}" ]]; then
                while read -r username; do
                    log_info "Analyzing u/${username}..."
                    run_profile_analysis "${username}"
                    sleep 3
                done < "${userfile}"
            else
                log_error "File not found: ${userfile}"
            fi
            ;;
        2)
            log_info "Running batch scam detection with common keywords..."
            bash "${SCRIPT_DIR}/modules/scam_detector.sh" --batch
            ;;
        3)
            echo -n "Enter subreddits (comma-separated): "
            read -r subreddits
            echo -n "Enter keyword to monitor: "
            read -r keyword
            
            IFS=',' read -ra SUBS <<< "${subreddits}"
            for sub in "${SUBS[@]}"; do
                log_info "Monitoring r/${sub}..."
                run_keyword_monitor "${keyword}" "${sub}"
                sleep 2
            done
            ;;
        4)
            return
            ;;
    esac
}

# Configuration menu
configure_system() {
    echo ""
    echo -e "${YELLOW}╔════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║      CONFIGURATION                 ║${NC}"
    echo -e "${YELLOW}╔════════════════════════════════════╗${NC}"
    echo "1. Set Reddit API Credentials"
    echo "2. Configure Detection Thresholds"
    echo "3. Update Threat Keywords"
    echo "4. Test API Connection"
    echo "5. View Current Configuration"
    echo "6. Back to Main Menu"
    echo -n "Select option: "
    read -r config_option
    
    case ${config_option} in
        1)
            echo ""
            echo "Enter Reddit API credentials:"
            echo -n "Client ID: "
            read -r client_id
            echo -n "Client Secret: "
            read -rs client_secret
            echo ""
            echo -n "Reddit Username: "
            read -r username
            echo -n "Reddit Password: "
            read -rs password
            echo ""
            
            # Update config file
            sed -i "s/REDDIT_CLIENT_ID=.*/REDDIT_CLIENT_ID=\"${client_id}\"/" "${SCRIPT_DIR}/config/config.sh"
            sed -i "s/REDDIT_CLIENT_SECRET=.*/REDDIT_CLIENT_SECRET=\"${client_secret}\"/" "${SCRIPT_DIR}/config/config.sh"
            sed -i "s/REDDIT_USERNAME=.*/REDDIT_USERNAME=\"${username}\"/" "${SCRIPT_DIR}/config/config.sh"
            sed -i "s/REDDIT_PASSWORD=.*/REDDIT_PASSWORD=\"${password}\"/" "${SCRIPT_DIR}/config/config.sh"
            
            log_success "API credentials updated"
            ;;
        2)
            echo ""
            echo -n "Fake profile detection threshold (0-100) [current: ${FAKE_PROFILE_THRESHOLD}]: "
            read -r threshold
            if [[ -n "${threshold}" ]]; then
                sed -i "s/FAKE_PROFILE_THRESHOLD=.*/FAKE_PROFILE_THRESHOLD=${threshold}/" "${SCRIPT_DIR}/config/config.sh"
                log_success "Threshold updated to ${threshold}"
            fi
            
            echo -n "Scam confidence threshold (0-100) [current: ${SCAM_CONFIDENCE_THRESHOLD}]: "
            read -r scam_threshold
            if [[ -n "${scam_threshold}" ]]; then
                sed -i "s/SCAM_CONFIDENCE_THRESHOLD=.*/SCAM_CONFIDENCE_THRESHOLD=${scam_threshold}/" "${SCRIPT_DIR}/config/config.sh"
                log_success "Scam threshold updated to ${scam_threshold}"
            fi
            ;;
        3)
            ${EDITOR:-nano} "${SCRIPT_DIR}/config/threat_keywords.txt"
            log_success "Threat keywords file opened for editing"
            ;;
        4)
            log_info "Testing Reddit API connection..."
            local test_result=$(get_reddit_token 2>&1)
            if [[ $? -eq 0 ]]; then
                log_success "✓ API connection successful!"
            else
                log_error "✗ API connection failed. Please check credentials."
            fi
            ;;
        5)
            echo ""
            echo -e "${CYAN}Current Configuration:${NC}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "Platform: Reddit"
            echo "Client ID: ${REDDIT_CLIENT_ID:0:10}..."
            echo "Username: ${REDDIT_USERNAME}"
            echo "Fake Profile Threshold: ${FAKE_PROFILE_THRESHOLD}"
            echo "Scam Threshold: ${SCAM_CONFIDENCE_THRESHOLD}"
            echo "API Rate Limit: ${API_RATE_LIMIT} req/min"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            ;;
        6)
            return
            ;;
    esac
}

# View logs and statistics
view_logs() {
    echo ""
    echo -e "${YELLOW}╔════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║      LOGS & STATISTICS             ║${NC}"
    echo -e "${YELLOW}╔════════════════════════════════════╗${NC}"
    echo "1. View Recent Logs"
    echo "2. View Error Logs"
    echo "3. View Detailed Statistics"
    echo "4. Clear Logs"
    echo "5. Export Statistics (JSON)"
    echo "6. Back to Main Menu"
    echo -n "Select option: "
    read -r log_option
    
    case ${log_option} in
        1)
            if [[ -f "${LOG_FILE}" ]]; then
                tail -n 50 "${LOG_FILE}" | less
            else
                log_warn "No log file found"
            fi
            ;;
        2)
            if [[ -f "${LOG_FILE}" ]]; then
                grep "ERROR" "${LOG_FILE}" | tail -n 50 | less
            else
                log_warn "No error logs found"
            fi
            ;;
        3)
            show_statistics
            ;;
        4)
            read -p "Are you sure you want to clear all logs? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                > "${LOG_FILE}"
                > "${ERROR_LOG}"
                log_info "Logs cleared successfully"
            fi
            ;;
        5)
            local stats_file="${REPORT_DIR}/statistics_$(date +%Y%m%d_%H%M%S).json"
            cat > "${stats_file}" << EOF
{
    "generated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "total_profiles": $(find "${DATA_DIR}/profiles" -name "reddit_*.json" -type f 2>/dev/null | wc -l),
    "suspicious_profiles": $(jq 'length' "${DATA_DIR}/profiles/suspicious_profiles.json" 2>/dev/null || echo 0),
    "scam_scans": $(jq 'length' "${DATA_DIR}/scams_detected.json" 2>/dev/null || echo 0),
    "network_analyses": $(find "${DATA_DIR}" -name "network_*.json" -type f 2>/dev/null | wc -l),
    "reports_generated": $(find "${REPORT_DIR}" -name "*.html" -type f 2>/dev/null | wc -l)
}
EOF
            log_success "Statistics exported to: ${stats_file}"
            cat "${stats_file}" | jq '.'
            ;;
        6)
            return
            ;;
    esac
}

# Show statistics
show_statistics() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          SYSTEM STATISTICS                     ║${NC}"
    echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
    echo ""
    
    local total_profiles=$(find "${DATA_DIR}/profiles" -name "reddit_*.json" -type f 2>/dev/null | wc -l)
    local suspicious_profiles=$(jq 'length' "${DATA_DIR}/profiles/suspicious_profiles.json" 2>/dev/null || echo 0)
    local scam_scans=$(jq 'length' "${DATA_DIR}/scams_detected.json" 2>/dev/null || echo 0)
    local network_analyses=$(find "${DATA_DIR}" -name "network_*.json" -type f 2>/dev/null | wc -l)
    local reports=$(find "${REPORT_DIR}" -name "*.html" -type f 2>/dev/null | wc -l)
    
    echo -e "${CYAN}Profile Analysis:${NC}"
    echo "  • Total Profiles Analyzed: ${total_profiles}"
    echo "  • Suspicious Accounts Found: ${suspicious_profiles}"
    if [[ ${total_profiles} -gt 0 ]]; then
        local suspicion_rate=$(awk "BEGIN {printf \"%.1f\", (${suspicious_profiles}/${total_profiles})*100}")
        echo "  • Suspicion Rate: ${suspicion_rate}%"
    fi
    echo ""
    
    echo -e "${CYAN}Scam Detection:${NC}"
    echo "  • Total Scam Scans: ${scam_scans}"
    if [[ -f "${DATA_DIR}/scams_detected.json" ]]; then
        local total_scams=$(jq '[.[].detection_summary.scams_detected] | add' "${DATA_DIR}/scams_detected.json" 2>/dev/null || echo 0)
        echo "  • Scams Detected: ${total_scams}"
    fi
    echo ""
    
    echo -e "${CYAN}Network Analysis:${NC}"
    echo "  • Network Mappings: ${network_analyses}"
    echo ""
    
    echo -e "${CYAN}Reports & Logs:${NC}"
    echo "  • HTML Reports Generated: ${reports}"
    echo "  • Log File Size: $(du -h "${LOG_FILE}" 2>/dev/null | cut -f1 || echo "0B")"
    echo ""
    
    echo -e "${CYAN}System Info:${NC}"
    echo "  • Platform: Reddit"
    echo "  • API Status: $(get_reddit_token &>/dev/null && echo "✓ Connected" || echo "✗ Not Connected")"
    echo "  • Uptime: $(uptime -p 2>/dev/null || echo "N/A")"
    echo ""
    echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
}

# Main execution
main() {
    show_banner
    initialize_directories
    
    while true; do
        show_menu
        read -r choice
        
        case ${choice} in
            1)
                echo ""
                echo -n "Enter Reddit username to analyze (without u/): "
                read -r username
                if [[ -n "${username}" ]]; then
                    run_profile_analysis "${username}"
                    echo ""
                    read -p "Press Enter to continue..."
                fi
                ;;
            2)
                echo ""
                echo -n "Enter keyword/topic to monitor: "
                read -r keyword
                echo -n "Enter subreddit (or 'all'): "
                read -r subreddit
                subreddit=${subreddit:-all}
                if [[ -n "${keyword}" ]]; then
                    run_keyword_monitor "${keyword}" "${subreddit}"
                    echo ""
                    read -p "Press Enter to continue..."
                fi
                ;;
            3)
                echo ""
                echo -n "Enter scam keyword to detect: "
                read -r keyword
                echo -n "Enter subreddit (or 'all'): "
                read -r subreddit
                subreddit=${subreddit:-all}
                if [[ -n "${keyword}" ]]; then
                    run_scam_detector "${keyword}" "${subreddit}"
                    echo ""
                    read -p "Press Enter to continue..."
                fi
                ;;
            4)
                echo ""
                echo -n "Enter username for network analysis: "
                read -r target
                if [[ -n "${target}" ]]; then
                    echo -n "Enter depth (1-3, recommended: 1): "
                    read -r depth
                    depth=${depth:-1}
                    echo -n "Max users to analyze (recommended: 20): "
                    read -r max_users
                    max_users=${max_users:-20}
                    run_network_mapper "${target}" "${depth}" "${max_users}"
                    echo ""
                    read -p "Press Enter to continue..."
                fi
                ;;
            5)
                generate_report
                echo ""
                read -p "Press Enter to continue..."
                ;;
            6)
                run_full_scan
                echo ""
                read -p "Press Enter to continue..."
                ;;
            7)
                batch_operations
                ;;
            8)
                configure_system
                ;;
            9)
                view_logs
                ;;
            0)
                echo ""
                log_info "Shutting down system..."
                echo -e "${GREEN}Thank you for using Reddit Threat Intelligence System!${NC}"
                echo -e "${CYAN}Stay safe! 🛡️${NC}"
                exit 0
                ;;
            *)
                log_error "Invalid option. Please select 0-9."
                sleep 1
                ;;
        esac
    done
}

# Run main function
main "$@"
