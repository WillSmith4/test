#!/bin/bash

# Colors
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
purple='\033[0;35m'
cyan='\033[0;36m'
rest='\033[0m'

# Global variables
Authorization=""
min_balance_threshold=0
last_upgraded_id=""
running=false

# Function to display log messages
log_message() {
    echo -e "${cyan}$(date '+%Y-%m-%d %H:%M:%S') - $1${rest}"
}

# Function to get the best upgrade items
get_best_items() {
    local response
    response=$(curl -s -X POST -H "User-Agent: Mozilla/5.0 (Android 12; Mobile; rv:102.0) Gecko/102.0 Firefox/102.0" \
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
        https://api.hamsterkombat.io/clicker/upgrades-for-buy)
    
    if [ $? -ne 0 ]; then
        log_message "${red}Error: Failed to fetch upgrade items${rest}"
        return 1
    fi

    echo "$response" | jq -r '.upgradesForBuy | map(select(.isExpired == false and .isAvailable)) | map(select(.profitPerHourDelta != 0 and .price != 0)) | sort_by(-(.profitPerHourDelta / .price)) | .[:10] | to_entries | map("\(.key+1). ID: \(.value.id), Efficiency: \(.value.profitPerHourDelta / .value.price)")'
}

# Function to purchase upgrade
purchase_upgrade() {
    local upgrade_id="$1"
    local timestamp=$(date +%s%3N)
    local response
    response=$(curl -s -X POST \
      -H "Content-Type: application/json" \
      -H "Authorization: $Authorization" \
      -H "Origin: https://hamsterkombat.io" \
      -H "Referer: https://hamsterkombat.io/" \
      -d "{\"upgradeId\": \"$upgrade_id\", \"timestamp\": $timestamp}" \
      https://api.hamsterkombat.io/clicker/buy-upgrade)
    
    if [ $? -ne 0 ]; then
        log_message "${red}Error: Failed to purchase upgrade${rest}"
        return 1
    fi

    echo "$response"
}

# Function to start auto buy
start_auto_buy() {
    running=true
    log_message "${green}Auto Buy started.${rest}"

    while $running; do
        log_message "Fetching available upgrades..."
        available_upgrades=$(get_best_items)
        
        if [ $? -ne 0 ] || [ -z "$available_upgrades" ]; then
            log_message "${yellow}No valid items found to buy.${rest}"
            sleep 60
            continue
        fi
        
        log_message "Fetching current balance..."
        current_balance=$(curl -s -X POST \
            -H "Authorization: $Authorization" \
            -H "Origin: https://hamsterkombat.io" \
            -H "Referer: https://hamsterkombat.io/" \
            https://api.hamsterkombat.io/clicker/sync | jq -r .clickerUser.balanceCoins)
        
        if [ $? -ne 0 ] || [ -z "$current_balance" ]; then
            log_message "${red}Failed to fetch current balance. Retrying in 60 seconds...${rest}"
            sleep 60
            continue
        fi
        
        upgrade_found=false
        
        echo "$available_upgrades" | while read -r upgrade; do
            id=$(echo "$upgrade" | cut -d, -f1 | cut -d: -f2 | xargs)
            efficiency=$(echo "$upgrade" | cut -d, -f2 | cut -d: -f2 | xargs)
            
            upgrade_details=$(curl -s -X POST -H "Authorization: $Authorization" -H "Origin: https://hamsterkombat.io" -H "Referer: https://hamsterkombat.io/" https://api.hamsterkombat.io/clicker/upgrades-for-buy | jq -r ".upgradesForBuy[] | select(.id == \"$id\")")
            price=$(echo "$upgrade_details" | jq -r .price)
            cooldown=$(echo "$upgrade_details" | jq -r '.cooldownSeconds // 0')
            
            if (( $(echo "$current_balance - $price > $min_balance_threshold" | bc -l) )); then
                if [ "$cooldown" -eq 0 ]; then
                    log_message "${blue}Attempting to purchase upgrade $id...${rest}"
                    purchase_status=$(purchase_upgrade "$id")
                    if echo "$purchase_status" | grep -q "error_code"; then
                        log_message "${red}Failed to purchase upgrade. Error: $purchase_status${rest}"
                    else
                        log_message "${green}Upgrade $id purchased successfully.${rest}"
                        last_upgraded_id="$id"
                        upgrade_found=true
                        sleep_time=$(( ( RANDOM % 4 ) + 8 ))
                        log_message "${yellow}Waiting $sleep_time seconds before next purchase...${rest}"
                        sleep "$sleep_time"
                        break
                    fi
                else
                    log_message "${purple}Upgrade is on cooldown for $cooldown seconds. Checking next best upgrade...${rest}"
                fi
            else
                log_message "${yellow}Insufficient balance for upgrade $id. Checking next best upgrade...${rest}"
            fi
        done
        
        if [ "$upgrade_found" = false ]; then
            log_message "${yellow}No suitable upgrade found within the balance threshold. Waiting before next check...${rest}"
            sleep 60
        fi
    done

    log_message "${green}Auto Buy stopped.${rest}"
}

# Main execution
echo -e "${green}Welcome to Hamster Kombat Auto Buy Script${rest}"
echo -e "${yellow}Please enter your Authorization token:${rest}"
read -r Authorization

echo -e "${yellow}Please enter the minimum balance threshold:${rest}"
read -r min_balance_threshold

start_auto_buy
