#!/bin/bash

# Colors
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
cyan='\033[0;36m'
reset='\033[0m'

# Function to install required packages
install_packages() {
    local packages=(curl jq bc)
    local missing_packages=()
    for pkg in "${packages[@]}"; do
        if ! command -v "$pkg" &> /dev/null; then
            missing_packages+=("$pkg")
        fi
    done

    if [ ${#missing_packages[@]} -gt 0 ]; then
        echo -e "${yellow}Installing missing packages: ${missing_packages[*]}${reset}"
        pkg update -y
        pkg install "${missing_packages[@]}" -y
    fi
}

# Install required packages
install_packages

# Function for single login
single_login() {
    local auth="$1"
    local account="$2"
    echo -e "${cyan}($account) Sending request...${reset}"

    response=$(curl -s -X POST \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" \
        -H "Accept: */*" \
        -H "Accept-Language: en-US,en;q=0.5" \
        -H "Referer: https://hamsterkombatgame.io/" \
        -H "Authorization: $auth" \
        -H "Origin: https://hamsterkombatgame.io" \
        -H "Connection: keep-alive" \
        -H "Sec-Fetch-Dest: empty" \
        -H "Sec-Fetch-Mode: cors" \
        -H "Sec-Fetch-Site: same-site" \
        -H "Content-Type: application/json" \
        -d "{\"lastSyncUpdate\": $(date +%s)}" \
        https://api.hamsterkombat.io/clicker/sync)

    status_code=$(echo "$response" | jq -r '.statusCode // 200')

    if [ "$status_code" -eq 200 ]; then
        echo -e "${green}($account) Successfully logged in.${reset}"
    else
        error_message=$(echo "$response" | jq -r '.message // "Unknown error"')
        echo -e "${red}($account) Login failed. Status code: $status_code. Error: $error_message${reset}"
    fi
}

# Function for login loop
login_loop() {
    local auth="$1"
    local account="$2"
    while true; do
        single_login "$auth" "$account"
        
        current_hour=$(date +%H)
        if [ $current_hour -ge 2 ] && [ $current_hour -lt 7 ]; then
            sleep_time=$(( ( RANDOM % 3600 ) + 18000 ))
            echo -e "${yellow}($account) Night time detected. Set longer interval.${reset}"
        else
            sleep_time=$(( ( RANDOM % 3600 ) + 7200 ))
            echo -e "${yellow}($account) Day time detected. Set normal interval.${reset}"
        fi
        
        echo -e "${cyan}($account) Waiting ${sleep_time} seconds before next login...${reset}"
        
        # Countdown on a single line
        for (( i=$sleep_time; i>0; i-- )); do
            printf "\r${cyan}($account) Time remaining: %02d:%02d:%02d${reset}" $((i/3600)) $(((i%3600)/60)) $((i%60))
            sleep 1
        done
        echo -e "\n${green}($account) Countdown finished. Starting next login...${reset}" # New line after countdown finishes
    done
}

# Function for auto card buy
auto_card_buy() {
    local auth="$1"
    local balance_threshold="$2"
    local account="AutoCardBuy"
    local running=true
    local last_best_id=""

    echo -e "${cyan}($account) Starting auto card buy...${reset}"

    while $running; do
        start_time=$(date +%s)

        echo -e "${cyan}($account) Fetching available upgrades...${reset}"
        upgrades_response=$(curl -s -X POST \
            -H "User-Agent: Mozilla/5.0 (Android 12; Mobile; rv:102.0) Gecko/102.0 Firefox/102.0" \
            -H "Accept: */*" \
            -H "Accept-Language: en-US,en;q=0.5" \
            -H "Referer: https://hamsterkombatgame.io/" \
            -H "Authorization: $auth" \
            -H "Origin: https://hamsterkombatgame.io" \
            -H "Connection: keep-alive" \
            -H "Sec-Fetch-Dest: empty" \
            -H "Sec-Fetch-Mode: cors" \
            -H "Sec-Fetch-Site: same-site" \
            -H "Priority: u=4" \
            https://api.hamsterkombat.io/clicker/upgrades-for-buy)

        if [ $(echo "$upgrades_response" | jq -r '.statusCode // 200') -eq 200 ]; then
            available_upgrades=$(echo "$upgrades_response" | jq -c '[.upgradesForBuy[] | select(.isExpired == false and .isAvailable == true and .profitPerHourDelta != 0 and .price != 0)] | sort_by(-.profitPerHourDelta / .price)')

            if [ -z "$available_upgrades" ] || [ "$available_upgrades" == "[]" ]; then
                echo -e "${yellow}($account) No valid item found to buy. Waiting before next check...${reset}"
                sleep $(( ( RANDOM % 5 ) + 8 ))
                continue
            fi

            echo -e "${cyan}($account) Fetching current balance...${reset}"
            balance_response=$(curl -s -X POST \
                -H "Authorization: $auth" \
                -H "Origin: https://hamsterkombatgame.io" \
                -H "Referer: https://hamsterkombatgame.io/" \
                https://api.hamsterkombat.io/clicker/sync)

            if [ $(echo "$balance_response" | jq -r '.statusCode // 200') -eq 200 ]; then
                current_balance=$(echo "$balance_response" | jq -r '.clickerUser.balanceCoins')

                if (( $(echo "$current_balance <= $balance_threshold" | bc -l) )); then
                    echo -e "${yellow}($account) Balance threshold reached. Stopping auto card buy.${reset}"
                    running=false
                    break
                fi

                upgrade_found=false

                echo "$available_upgrades" | jq -c '.[]' | while read -r upgrade && [ "$upgrade_found" = false ]; do
                    upgrade_id=$(echo "$upgrade" | jq -r '.id')
                    upgrade_price=$(echo "$upgrade" | jq -r '.price')
                    upgrade_profit=$(echo "$upgrade" | jq -r '.profitPerHourDelta')
                    cooldown_seconds=$(echo "$upgrade" | jq -r '.cooldownSeconds // 0')
                    efficiency=$(echo "scale=6; $upgrade_profit / $upgrade_price" | bc)

                    echo -e "${cyan}($account) Checking upgrade: $upgrade_id${reset}"
                    echo -e "${cyan}($account) Price: $upgrade_price, Profit/Hour: $upgrade_profit, Efficiency: $efficiency${reset}"

                    if (( $(echo "$current_balance - $upgrade_price > $balance_threshold" | bc -l) )); then
                        if [ "$cooldown_seconds" -eq 0 ]; then
                            purchase_upgrade "$upgrade" "$account" "$auth"
                            upgrade_found=true
                            last_best_id="$upgrade_id"
                            break
                        else
                            echo -e "${yellow}($account) Upgrade '$upgrade_id' is on cooldown for $cooldown_seconds seconds. Checking next best upgrade...${reset}"
                        fi
                    else
                        echo -e "${yellow}($account) Insufficient balance for upgrade '$upgrade_id'. Checking next best upgrade...${reset}"
                    fi
                done

                if [ "$upgrade_found" = false ]; then
                    echo -e "${yellow}($account) No suitable upgrade found within the balance threshold. Waiting before next check...${reset}"
                fi
            else
                echo -e "${red}($account) Failed to fetch balance. Status code: $(echo "$balance_response" | jq -r '.statusCode // "Unknown"')${reset}"
            fi
        else
            echo -e "${red}($account) Failed to fetch upgrades. Status code: $(echo "$upgrades_response" | jq -r '.statusCode // "Unknown"')${reset}"
        fi

        end_time=$(date +%s)
        elapsed=$((end_time - start_time))
        if [ $elapsed -lt 8 ]; then
            sleep_time=$((8 - elapsed))
            echo -e "${cyan}($account) Waiting ${sleep_time} seconds to meet minimum execution time...${reset}"
            sleep $sleep_time
        elif [ $elapsed -gt 12 ]; then
            echo -e "${yellow}($account) Execution time exceeded 12 seconds.${reset}"
        fi
    done
}

purchase_upgrade() {
    local upgrade="$1"
    local account="$2"
    local auth="$3"

    local best_item_id=$(echo "$upgrade" | jq -r '.id')
    local section=$(echo "$upgrade" | jq -r '.section')
    local price=$(echo "$upgrade" | jq -r '.price')
    local profit=$(echo "$upgrade" | jq -r '.profitPerHourDelta')

    echo -e "${cyan}($account) Best item to buy: $best_item_id in section: $section${reset}"
    echo -e "${cyan}($account) Price: $price${reset}"
    echo -e "${cyan}($account) Profit per Hour Delta: $profit${reset}"
    echo -e "${cyan}($account) Attempting to purchase upgrade '$best_item_id'...${reset}"

    purchase_response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: $auth" \
        -H "Origin: https://hamsterkombatgame.io" \
        -H "Referer: https://hamsterkombatgame.io/" \
        -d "{\"upgradeId\": \"$best_item_id\", \"timestamp\": $(date +%s%3N)}" \
        https://api.hamsterkombat.io/clicker/buy-upgrade)

    if [ $(echo "$purchase_response" | jq -r '.statusCode // 200') -eq 200 ]; then
        echo -e "${green}($account) Upgrade '$best_item_id' purchased successfully.${reset}"
        sleep_time=$(( ( RANDOM % 5 ) + 8 ))
        echo -e "${cyan}($account) Waiting ${sleep_time} seconds before next purchase...${reset}"
        sleep $sleep_time
    else
        echo -e "${red}($account) Failed to purchase upgrade '$best_item_id'. Status code: $(echo "$purchase_response" | jq -r '.statusCode // "Unknown"')${reset}"
        sleep 5
    fi
}

# Main menu function
show_menu() {
    echo -e "${green}=== Hamster Kombat Auto Tool ===${reset}"
    echo -e "${cyan}1. Auto Login${reset}"
    echo -e "${cyan}2. Auto Card Buy${reset}"
    echo -e "${cyan}3. Exit${reset}"
    echo -e "${yellow}Enter your choice (1-3): ${reset}"
}

# Auto login function
auto_login() {
    echo -e "${cyan}Starting Auto Login...${reset}"
    login_loop "$Authorization" "AutoLogin"
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
                auto_card_buy "$Authorization" "$min_balance_threshold"
                ;;
            3)
                echo -e "${green}Exiting. Goodbye!${reset}"
                exit 0
                ;;
            *)
                echo -e "${red}Invalid choice. Please try again.${reset}"
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
