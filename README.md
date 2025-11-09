# NetSentinel: Reddit Social Threat Intelligence System

NetSentinel is a Bash-based platform for Reddit threat intelligence, scam detection, profile analysis, network mapping, and trend monitoring. It leverages the Reddit API to analyze posts, users, and networks for suspicious activity and generates comprehensive reports.

## Features

- **Profile Analysis:** Detects fake, bot, or suspicious Reddit accounts.
- **Keyword & Trend Monitoring:** Monitors keywords across subreddits for coordinated campaigns or abnormal trends.
- **Scam Pattern Detection:** Identifies scam posts using advanced pattern matching and threat keyword lists.
- **Network Mapping:** Maps user connections and subreddit interactions, detects network anomalies.
- **Comprehensive Reporting:** Generates HTML and JSON reports with statistics, findings, and recommendations.
- **Secure Credential Management:** Supports encrypted storage of API credentials.
- **Batch Operations:** Analyze multiple users, keywords, or subreddits in one go.

## Directory Structure

```
.env
.gitignore
install.sh
main.sh
config/
  config.sh
  threat_keywords.txt
data/
  cache/
  networks/
  profiles/
  reports/
  scams/
  trends/
logs/
modules/
  hashtag_monitor.sh
  network_mapper.sh
  profile_analyzer.sh
  reddit_trending_detector.sh
  scam_detector.sh
utils/
  api_handler.sh
  env_manager.sh
  logger.sh
  network_visualizer.sh
  reddit_api.sh
```

## Installation

1. **Clone the repository:**
   ```sh
   git clone https://github.com/cyb3ritic/netsentinel.git
   cd netsentinel
   ```

2. **Run the installer:**
   ```sh
   ./install.sh
   ```

3. **Configure Reddit API credentials:**
   - Edit `.env` and add your Reddit API keys (see [config/config.sh](config/config.sh)).
   - You can also use the configuration menu in the app.

4. **Customize threat keywords:**
   - Edit [config/threat_keywords.txt](config/threat_keywords.txt) as needed.

## Usage

Start the main control script:

```sh
./main.sh
```

Follow the interactive menu to:

- Analyze Reddit profiles
- Monitor keywords/trends
- Detect scams
- Map user networks
- Generate reports
- Run batch operations
- Configure system settings

### Example Commands

- **Profile Analysis:**  
  `./modules/profile_analyzer.sh <username>`
- **Keyword Monitoring:**  
  `./modules/hashtag_monitor.sh "<keyword>" [subreddit|all]`
- **Scam Detection:**  
  `./modules/scam_detector.sh "<keyword>" [subreddit|all]`
- **Network Mapping:**  
  `./modules/network_mapper.sh <username> [depth] [max_users]`
- **Trend Detection:**  
  `./modules/reddit_trending_detector.sh [subreddit|all]`

## Dependencies

- `curl`
- `jq`
- `awk`
- `sed`
- `bc`
- `openssl` (for encrypted credentials)

## Security

- Store API credentials securely using [utils/env_manager.sh](utils/env_manager.sh).
- Sensitive data and logs are excluded from version control via [.gitignore](.gitignore).

## Reports

- HTML and JSON reports are generated in `data/reports/`.
- View statistics and logs via the main menu.

## Contributing

Pull requests and issues are welcome! Please follow best practices for Bash scripting and security.


---

**Authors:**  
NetSentinel Team  
2025
