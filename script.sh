#!/data/data/com.termux/files/usr/bin/bash

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
    local packages=(curl jq bc dialog)
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

        dialog --title "Best Item" --msgbox "Best item to buy: $best_item_id in section: $section\nPrice: $price\nProfit per Hour: $profit" 10 60

        current_balance=$(curl -s -X POST \
            -H "Authorization: $Authorization" \
            -H "Origin: https://hamsterkombat.io" \
            -H "Referer: https://hamsterkombat.io/" \
            https://api.hamsterkombat.io/clicker/sync | jq -r '.clickerUser.balanceCoins')

        if (( $(echo "$current_balance - $price > $min_balance_threshold" | bc -l) )); then
            if [ -n "$best_item_id" ]; then
                dialog --title "Purchase Confirmation" --yesno "Attempt to purchase upgrade '$best_item_id'?" 7 60
                response=$?
                case $response in
                    0) 
                        purchase_status=$(purchase_upgrade "$best_item_id")

                        if echo "$purchase_status" | grep -q "error_code"; then
                            wait_for_cooldown "$cooldown"
                        else
                            purchase_time=$(date +"%Y-%m-%d %H:%M:%S")
                            total_spent=$(echo "$total_spent + $price" | bc)
                            total_profit=$(echo "$total_profit + $profit" | bc)
                            current_balance=$(echo "$current_balance - $price" | bc)

                            dialog --title "Purchase Successful" --msgbox "Upgrade '$best_item_id' purchased successfully at $purchase_time.\nTotal spent so far: $total_spent coins.\nTotal profit added: $total_profit coins per hour.\nCurrent balance: $current_balance coins." 10 60
                            
                            sleep_duration=$((RANDOM % 8 + 5))
                            echo -e "${green}Waiting for ${yellow}$sleep_duration${green} seconds before next purchase...${rest}"
                            sleep $sleep_duration
                        fi
                        ;;
                    1) 
                        break
                        ;;
                    255) 
                        echo "ESC pressed."
                        break
                        ;;
                esac
            else
                dialog --title "Error" --msgbox "No valid item found to buy." 7 40
                break
            fi
        else
            dialog --title "Error" --msgbox "Current balance ($current_balance) minus price of item ($price) is below the threshold ($min_balance_threshold). Stopping purchases." 8 60
            break
        fi
    done
}

# Text-based UI for input
Authorization=$(dialog --title "Authorization" --inputbox "Enter Authorization [Example: Bearer 171852....]:" 8 60 3>&1 1>&2 2>&3 3>&-)
min_balance_threshold=$(dialog --title "Minimum Balance Threshold" --inputbox "Enter minimum balance threshold:" 8 60 3>&1 1>&2 2>&3 3>&-)

# Clear screen after input
clear

# Execute the main function
main
