#!/bin/bash

# GUI dependencies
if ! command -v zenity &> /dev/null; then
    echo "Zenity is not installed. Please install it to use the GUI."
    exit 1
fi

# Colors
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
purple='\033[0;35m'
cyan='\033[0;36m'
blue='\033[0;34m'
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
        if [ -n "$(command -v pkg)" ]; then
            pkg install "${missing_packages[@]}" -y
        elif [ -n "$(command -v apt)" ]; then
            sudo apt update -y
            sudo apt install "${missing_packages[@]}" -y
        elif [ -n "$(command -v yum)" ]; then
            sudo yum update -y
            sudo yum install "${missing_packages[@]}" -y
        elif [ -n "$(command -v dnf)" ]; then
            sudo dnf update -y
            sudo dnf install "${missing_packages[@]}" -y
        else
            echo -e "${yellow}Unsupported package manager. Please install required packages manually.${rest}"
        fi
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
    (
        echo "# Upgrade is on cooldown. Waiting for cooldown period of $cooldown_seconds seconds..."
        for ((i=cooldown_seconds; i>0; i--)); do
            echo "$i"
            echo "# $i seconds remaining"
            sleep 1
        done
    ) | zenity --progress --title="Cooldown" --text="Waiting for cooldown..." --percentage=0 --auto-close --auto-kill
}

# Main script logic
main() {
    while true; do
        best_item=$(get_best_item)
        best_item_id=$(echo "$best_item" | jq -r '.id')
        section=$(echo "$best_item" | jq -r '.section')
        price=$(echo "$best_item" | jq -r '.price')
        profit=$(echo "$best_item" | jq -r '.profitPerHourDelta')
        cooldown=$(echo "$best_item" | jq -r '.cooldownSeconds')

        zenity --info --title="Best Item" --text="Best item to buy: $best_item_id in section: $section\nPrice: $price\nProfit per Hour: $profit"

        current_balance=$(curl -s -X POST \
            -H "Authorization: $Authorization" \
            -H "Origin: https://hamsterkombat.io" \
            -H "Referer: https://hamsterkombat.io/" \
            https://api.hamsterkombat.io/clicker/sync | jq -r '.clickerUser.balanceCoins')

        if (( $(echo "$current_balance - $price > $min_balance_threshold" | bc -l) )); then
            if [ -n "$best_item_id" ]; then
                zenity --question --title="Purchase Confirmation" --text="Attempt to purchase upgrade '$best_item_id'?" --ok-label="Yes" --cancel-label="No"
                if [ $? -eq 0 ]; then
                    purchase_status=$(purchase_upgrade "$best_item_id")

                    if echo "$purchase_status" | grep -q "error_code"; then
                        wait_for_cooldown "$cooldown"
                    else
                        purchase_time=$(date +"%Y-%m-%d %H:%M:%S")
                        total_spent=$(echo "$total_spent + $price" | bc)
                        total_profit=$(echo "$total_profit + $profit" | bc)
                        current_balance=$(echo "$current_balance - $price" | bc)

                        zenity --info --title="Purchase Successful" --text="Upgrade '$best_item_id' purchased successfully at $purchase_time.\nTotal spent so far: $total_spent coins.\nTotal profit added: $total_profit coins per hour.\nCurrent balance: $current_balance coins."
                        
                        sleep_duration=$((RANDOM % 8 + 5))
                        (
                            echo "# Waiting for $sleep_duration seconds before next purchase..."
                            for ((i=sleep_duration; i>0; i--)); do
                                echo "$i"
                                echo "# $i seconds remaining"
                                sleep 1
                            done
                        ) | zenity --progress --title="Waiting" --text="Waiting before next purchase..." --percentage=0 --auto-close --auto-kill
                    fi
                else
                    break
                fi
            else
                zenity --error --title="Error" --text="No valid item found to buy."
                break
            fi
        else
            zenity --error --title="Error" --text="Current balance ($current_balance) minus price of item ($price) is below the threshold ($min_balance_threshold). Stopping purchases."
            break
        fi
    done
}

# GUI for input
Authorization=$(zenity --entry --title="Authorization" --text="Enter Authorization [Example: Bearer 171852....]:")
min_balance_threshold=$(zenity --entry --title="Minimum Balance Threshold" --text="Enter minimum balance threshold:")

# Execute the main function
main