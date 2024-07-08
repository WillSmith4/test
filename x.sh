#!/data/data/com.termux/files/usr/bin/bash

# Colors
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
cyan='\033[0;36m'
rest='\033[0m'

# Function to install necessary packages
install_packages() {
    local packages=(curl jq bc)
    local missing_packages=()

    for pkg in "${packages[@]}"; do
        if ! command -v "$pkg" &> /dev/null; then
            missing_packages+=("$pkg")
        fi
    done

    if [ ${#missing_packages[@]} -gt 0 ]; then
        echo -e "${yellow}Installing missing packages: ${missing_packages[*]}${rest}"
        pkg update -y
        pkg install "${missing_packages[@]}" -y
    fi
}

# Install the necessary packages
install_packages

# Variables to keep track of total spent and total profit
total_spent=0
total_profit=0

# Function to purchase upgrade
purchase_upgrade() {
    upgrade_id="$1"
    timestamp=$(date +%s%3N)
    response=$(curl -s -X POST \
      -H "Content-Type: application/json" \
      -H "Authorization: $Authorization" \
      -H "Origin: https://hamsterkombat.io" \
      -H "Referer: https://hamsterkombat.io/" \
      -d "{\"upgradeId\": \"$upgrade_id\", \"timestamp\": $timestamp}" \
      https://api.hamsterkombat.io/clicker/buy-upgrade)
    echo "$response"
}

# Function to get the best upgrade item
get_best_item() {
    curl -s -X POST -H "User-Agent: Mozilla/5.0 (Android 12; Mobile; rv:102.0) Gecko/102.0 Firefox/102.0" \
        -H "Accept: */*" \
        -H "Accept-Language: en-US,en;q=0.5" \
        -H "Referer: https://hamsterkombat.io/" \
        -H "Authorization: $Authorization" \
        -H "Origin: https://hamsterkombat.io" \
        -H "Connection: keep-alive" \
        -H "Sec-Fetch-Dest: empty" \
        -H "Sec-Fetch-Mode: cors" \
        -H "Sec-Fetch-Site: same-site" \
        -H "Priority: u=4" \
        https://api.hamsterkombat.io/clicker/upgrades-for-buy | jq -r '.upgradesForBuy | map(select(.isExpired == false and .isAvailable)) | map(select(.profitPerHourDelta != 0 and .price != 0)) | sort_by(-(.profitPerHourDelta / .price))[:1] | .[0] | {id: .id, section: .section, price: .price, profitPerHourDelta: .profitPerHourDelta, cooldownSeconds: .cooldownSeconds}'
}

# Function to wait for cooldown period with countdown
wait_for_cooldown() {
    cooldown_seconds="$1"
    echo -e "${yellow}Upgrade is on cooldown. Waiting for cooldown period of ${cyan}$cooldown_seconds${yellow} seconds...${rest}"
    while [ $cooldown_seconds -gt 0 ]; do
        echo -ne "${cyan}$cooldown_seconds\033[0K\r${rest}"
        sleep 1
        ((cooldown_seconds--))
    done
    echo
}

# Function for auto-login
auto_login() {
    echo -e "${green}Starting auto-login...${rest}"
    while true; do
        timestamp=$(date +%s)
        response=$(curl -s -X POST \
            -H "Content-Type: application/json" \
            -H "Authorization: $Authorization" \
            -H "Origin: https://hamsterkombat.io" \
            -H "Referer: https://hamsterkombat.io/" \
            -d "{\"lastSyncUpdate\": $timestamp}" \
            https://api.hamsterkombat.io/clicker/sync)

        if echo "$response" | grep -q "clickerUser"; then
            echo -e "${green}Successfully logged in at $(date)${rest}"
        else
            echo -e "${red}Login failed at $(date). Response: $response${rest}"
        fi

        # Check current time and set sleep duration accordingly
        current_hour=$(date +%H)
        if [ $current_hour -ge 2 ] && [ $current_hour -lt 7 ]; then
            # Night time (2:00 AM to 6:59 AM)
            sleep_duration=$(awk -v min=18000 -v max=21600 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')
        else
            # Day time
            sleep_duration=$(awk -v min=7200 -v max=10800 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')
        fi
        echo -e "${yellow}Waiting ${cyan}$sleep_duration${yellow} seconds before next login...${rest}"
        sleep $sleep_duration
    done
}

# Function for auto card buy
auto_card_buy() {
    echo -e "${green}Starting upgrade purchases...${rest}"
    
    while true; do
        echo -e "${cyan}Fetching available upgrades...${rest}"
        best_item=$(get_best_item)
        best_item_id=$(echo "$best_item" | jq -r '.id')
        section=$(echo "$best_item" | jq -r '.section')
        price=$(echo "$best_item" | jq -r '.price')
        profit=$(echo "$best_item" | jq -r '.profitPerHourDelta')
        cooldown=$(echo "$best_item" | jq -r '.cooldownSeconds')

        echo -e "${yellow}Best item to buy: ${cyan}$best_item_id${yellow} in section: ${cyan}$section${rest}"
        echo -e "${yellow}Price: ${cyan}$price${rest}"
        echo -e "${yellow}Profit per Hour Delta: ${cyan}$profit${rest}"
        echo -e "${yellow}Cooldown Seconds: ${cyan}$cooldown${rest}"
        echo

        echo -e "${cyan}Fetching current balance...${rest}"
        current_balance=$(curl -s -X POST \
            -H "Authorization: $Authorization" \
            -H "Origin: https://hamsterkombat.io" \
            -H "Referer: https://hamsterkombat.io/" \
            https://api.hamsterkombat.io/clicker/sync | jq -r '.clickerUser.balanceCoins')

        if (( $(echo "$current_balance - $price > $min_balance_threshold" | bc -l) )); then
            if [ -n "$best_item_id" ]; then
                echo -e "${green}Attempting to purchase upgrade '$best_item_id'...${rest}"
                purchase_status=$(purchase_upgrade "$best_item_id")

                if echo "$purchase_status" | grep -q "error_code"; then
                    wait_for_cooldown "$cooldown"
                else
                    purchase_time=$(date +"%Y-%m-%d %H:%M:%S")
                    total_spent=$(echo "$total_spent + $price" | bc)
                    total_profit=$(echo "$total_profit + $profit" | bc)
                    current_balance=$(echo "$current_balance - $price" | bc)

                    echo -e "${green}Upgrade '$best_item_id' purchased successfully at $purchase_time.${rest}"
                    echo -e "${yellow}Total spent so far: ${cyan}$total_spent${yellow} coins.${rest}"
                    echo -e "${yellow}Total profit added: ${cyan}$total_profit${yellow} coins per hour.${rest}"
                    echo -e "${yellow}Current balance: ${cyan}$current_balance${yellow} coins.${rest}"
                    
                    sleep_duration=$(awk -v min=8 -v max=12 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')
                    echo -e "${green}Waiting ${yellow}$sleep_duration${green} seconds before next purchase...${rest}"
                    sleep $sleep_duration
                fi
            else
                echo -e "${red}No valid item found to buy.${rest}"
                break
            fi
        else
            echo -e "${red}Current balance ($current_balance) minus price of item ($price) is below the threshold ($min_balance_threshold). Stopping purchases.${rest}"
            break
        fi

        # Check if user wants to stop
        if read -t 0.1 input; then
            if [ "$input" = "stop" ]; then
                echo -e "${yellow}Stopping auto card buy process...${rest}"
                break
            fi
        fi
    done
}

# Main menu function
show_menu() {
    echo -e "${green}=== Hamster Kombat Auto Tool ===${rest}"
    echo -e "${cyan}1. Auto Login${rest}"
    echo -e "${cyan}2. Auto Card Buy${rest}"
    echo -e "${cyan}3. Exit${rest}"
    echo -e "${yellow}Enter your choice (1-3): ${rest}"
}

# Main script logic
main() {
    while true; do
        show_menu
        read -r choice

        case $choice in
            1)
                auto_login
                ;;
            2)
                read -p "Enter minimum balance threshold: " min_balance_threshold
                auto_card_buy
                ;;
            3)
                echo -e "${green}Exiting. Goodbye!${rest}"
                exit 0
                ;;
            *)
                echo -e "${red}Invalid choice. Please try again.${rest}"
                ;;
        esac
    done
}

# Text-based UI for input
read -p "Enter Authorization [Example: Bearer 171852....]: " Authorization

# Clear screen after input
clear

# Execute the main function
main