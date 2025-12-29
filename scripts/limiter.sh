#!/bin/bash

# Limiter Installation Script
# https://github.com/MatinDehghanian/PG-Limiter

set -e

REPO_OWNER="MatinDehghanian"
REPO_NAME="PG-Limiter"

# Check required commands
check_dependencies() {
    local missing=()
    
    command -v screen &>/dev/null || missing+=("screen")
    command -v curl &>/dev/null || missing+=("curl")
    command -v jq &>/dev/null || missing+=("jq")
    
    if [ ${#missing[@]} -ne 0 ]; then
        echo "Missing required commands: ${missing[*]}"
        echo "Install with: sudo apt install ${missing[*]}"
        exit 1
    fi
}

# Detect architecture and set filename
get_binary_name() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64) echo "limiter_amd64" ;;
        aarch64) echo "limiter_arm64" ;;
        *) echo ""; return 1 ;;
    esac
}

# Download the latest release binary
download_program() {
    local filename=$(get_binary_name)
    
    if [ -z "$filename" ]; then
        echo "Unsupported architecture: $(uname -m)"
        return 1
    fi
    
    if [ -f "$filename" ]; then
        echo "Binary already exists: $filename"
        return 0
    fi
    
    echo "Downloading $filename..."
    
    # Try to get the download URL from release assets
    local api_response=$(curl -s "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/latest")
    
    # Check if we got a valid response
    if echo "$api_response" | jq -e '.assets' > /dev/null 2>&1; then
        local download_url=$(echo "$api_response" | jq -r ".assets[] | select(.name == \"$filename\") | .browser_download_url")
        
        if [ -n "$download_url" ] && [ "$download_url" != "null" ]; then
            curl -L "$download_url" -o "$filename"
            chmod +x "$filename"
            echo "Download complete: $filename"
            return 0
        fi
    fi
    
    echo "No pre-built binary found. Running from source instead."
    return 1
}

# Update the binary
update_program() {
    local filename=$(get_binary_name)
    [ -f "$filename" ] && rm "$filename"
    download_program
}

# Check if limiter is running
is_running() {
    screen -list 2>/dev/null | grep -q "Limiter"
}

# Start the limiter with startup verification
start_program() {
    local filename=$(get_binary_name)
    
    # Check config - use config.json in current directory
    if [ ! -f "config.json" ]; then
        echo "Config not found. Creating configuration..."
        create_config
    fi
    
    if is_running; then
        echo "Limiter is already running."
        return
    fi
    
    # Create log file for error tracking
    local log_file="limiter_startup.log"
    
    # Try binary first, fall back to Python
    local mode=""
    if [ -f "$filename" ]; then
        mode="binary"
        screen -Sdm Limiter bash -c "./$filename 2>&1 | tee $log_file"
        echo "Limiter starting (binary mode)..."
    elif [ -f "limiter.py" ]; then
        mode="python"
        screen -Sdm Limiter bash -c "python3 limiter.py 2>&1 | tee $log_file"
        echo "Limiter starting (Python mode)..."
    else
        echo "No executable found. Downloading..."
        if download_program; then
            mode="binary"
            screen -Sdm Limiter bash -c "./$filename 2>&1 | tee $log_file"
            echo "Limiter starting..."
        else
            echo "Please clone the repository and run from source:"
            echo "  git clone https://github.com/$REPO_OWNER/$REPO_NAME.git"
            echo "  cd $REPO_NAME"
            echo "  pip install -r requirements.txt"
            echo "  python3 limiter.py"
            return 1
        fi
    fi
    
    # Wait briefly and verify startup
    sleep 2
    
    if is_running; then
        echo "✅ Limiter started successfully!"
        return 0
    fi
    
    # Startup failed - check for GLIBC error and try Python fallback
    if [ "$mode" = "binary" ] && grep -q "GLIBC" "$log_file" 2>/dev/null; then
        echo ""
        echo "⚠️  Binary incompatible with your system (GLIBC version mismatch)."
        
        if [ -f "limiter.py" ]; then
            echo "Trying Python mode instead..."
            echo ""
            
            # Check if Python dependencies are installed
            if ! python3 -c "import httpx" 2>/dev/null; then
                echo "Installing Python dependencies..."
                pip3 install -r requirements.txt 2>/dev/null || pip install -r requirements.txt 2>/dev/null
            fi
            
            screen -Sdm Limiter bash -c "python3 limiter.py 2>&1 | tee $log_file"
            sleep 2
            
            if is_running; then
                echo "✅ Limiter started successfully (Python mode)!"
                echo ""
                echo "Note: Python mode is recommended for your system."
                echo "You can remove the binary: rm $filename"
                return 0
            fi
        else
            echo ""
            echo "To run from source, install Python dependencies:"
            echo "  git clone https://github.com/$REPO_OWNER/$REPO_NAME.git"
            echo "  cd $REPO_NAME"
            echo "  pip3 install -r requirements.txt"
            echo "  python3 limiter.py"
            return 1
        fi
    fi
    
    # Show error details
    echo ""
    echo "❌ Limiter failed to start!"
    echo ""
    if [ -f "$log_file" ] && [ -s "$log_file" ]; then
        echo "=== Error Log ==="
        tail -30 "$log_file"
        echo "================="
    fi
    echo ""
    echo "Common issues:"
    echo "  - Invalid config.json (check JSON syntax)"
    echo "  - Wrong panel domain/credentials"
    echo "  - Invalid Telegram bot token"
    echo "  - Panel not reachable"
    echo ""
    echo "Fix config with option 6, or view logs with option 4."
}

# Stop the limiter
stop_program() {
    if is_running; then
        screen -S Limiter -X quit
        echo "Limiter stopped."
    else
        echo "Limiter is not running."
    fi
}

# Attach to the running screen session
attach_program() {
    if is_running; then
        echo "Attaching to Limiter... (Press Ctrl-A then D to detach)"
        screen -r Limiter
    else
        echo "Limiter is not running."
        echo ""
        # Show recent logs if available
        if [ -f "limiter_startup.log" ] && [ -s "limiter_startup.log" ]; then
            echo "=== Recent Log (last 20 lines) ==="
            tail -20 limiter_startup.log
            echo "==================================="
            echo ""
        fi
        echo "Start limiter with option 1."
    fi
}

# View logs without attaching
view_logs() {
    local log_file="limiter_startup.log"
    
    if [ -f "$log_file" ] && [ -s "$log_file" ]; then
        echo "=== Limiter Logs ==="
        tail -50 "$log_file"
        echo "===================="
    else
        echo "No logs found."
    fi
    
    if is_running; then
        echo ""
        echo "Limiter is currently running."
        echo "Use option 3 to attach to live logs."
    fi
}

# Create or update configuration
create_config() {
    echo ""
    echo "===== Limiter Configuration ====="
    echo ""
    
    # Check if config already exists
    if [ -f "config.json" ]; then
        echo "Current config.json found."
        read -p "Overwrite existing config? (y/N): " overwrite
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            echo "Keeping existing config."
            return 0
        fi
        echo ""
    fi
    
    echo "Panel Settings:"
    read -p "  Domain (e.g., panel.example.com:8443): " domain
    read -p "  Username: " username
    read -sp "  Password: " password
    echo ""
    echo ""
    
    echo "Telegram Settings:"
    read -p "  Bot Token: " bot_token
    read -p "  Admin Chat ID: " admin_id
    echo ""
    
    echo "Limiter Settings:"
    read -p "  General IP Limit (default: 2): " limit
    limit=${limit:-2}
    
    # Validate inputs
    if [ -z "$domain" ] || [ -z "$username" ] || [ -z "$password" ]; then
        echo "❌ Error: Panel domain, username, and password are required!"
        return 1
    fi
    
    if [ -z "$bot_token" ] || [ -z "$admin_id" ]; then
        echo "❌ Error: Telegram bot token and admin ID are required!"
        return 1
    fi
    
    # Create config.json in current directory (not config/)
    cat > config.json << EOF
{
    "panel": {
        "domain": "$domain",
        "username": "$username",
        "password": "$password"
    },
    "telegram": {
        "bot_token": "$bot_token",
        "admins": [$admin_id]
    },
    "limits": {
        "general": $limit,
        "special": {}
    },
    "except_users": [],
    "check_interval": 60,
    "time_to_active_users": 900,
    "country_code": ""
}
EOF
    
    echo ""
    echo "✅ Configuration saved to config.json"
    echo ""
    echo "You can now start the limiter with option 1."
}

# Update Telegram bot token
update_token() {
    if [ ! -f "config/config.json" ]; then
        echo "Config not found. Please create configuration first."
        return 1
    fi
    
    read -p "Enter new Telegram bot token: " token
    jq --arg token "$token" '.telegram.bot_token = $token' config/config.json > config/tmp.json
    mv config/tmp.json config/config.json
    echo "Bot token updated."
}

# Update admin list
update_admins() {
    if [ ! -f "config/config.json" ]; then
        echo "Config not found. Please create configuration first."
        return 1
    fi
    
    read -p "Enter admin Telegram chat ID: " admin_id
    jq --argjson admin "$admin_id" '.telegram.admins = [$admin]' config/config.json > config/tmp.json
    mv config/tmp.json config/config.json
    echo "Admin updated."
}

# Main menu
show_menu() {
    echo ""
    echo "========== PG-Limiter =========="
    echo "1. Start"
    echo "2. Stop"
    echo "3. Attach to logs (live)"
    echo "4. View recent logs"
    echo "5. Update binary"
    echo "6. Create/Edit config"
    echo "7. Update bot token"
    echo "8. Update admins"
    echo "9. Exit"
    echo "================================"
}

# Main
check_dependencies

if [ $# -eq 0 ]; then
    while true; do
        show_menu
        read -p "Choice: " choice
        
        case $choice in
            1) start_program ;;
            2) stop_program ;;
            3) attach_program ;;
            4) view_logs ;;
            5) update_program ;;
            6) create_config ;;
            7) update_token ;;
            8) update_admins ;;
            9) exit 0 ;;
            *) echo "Invalid choice" ;;
        esac
    done
else
    case $1 in
        start) start_program ;;
        stop) stop_program ;;
        update) update_program ;;
        attach) attach_program ;;
        logs) view_logs ;;
        *) echo "Usage: $0 {start|stop|update|attach|logs}" ;;
    esac
fi
