#!/bin/bash

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
            exit 1
        fi
    fi
}

# Install necessary packages
install_packages

# Global variables
Authorization=""
min_balance_threshold=0
last_upgraded_id=""
running=false

# Function to get the best upgrade items
get_best_items() {
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
        https://api.hamsterkombat.io/clicker/upgrades-for-buy | jq -r '.upgradesForBuy | map(select(.isExpired == false and .isAvailable)) | map(select(.profitPerHourDelta != 0 and .price != 0)) | sort_by(-(.profitPerHourDelta / .price)) | .[:10] | to_entries | map("\(.key+1). ID: \(.value.id), Efficiency: \(.value.profitPerHourDelta / .value.price)")'
}

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

# Function to show the main menu
show_main_menu() {
    while true; do
        choice=$(dialog --clear --title "Auto Card Buy" \
            --menu "Choose an option:" 15 50 4 \
            1 "Start Auto Buy" \
            2 "Stop Auto Buy" \
            3 "Show Best Upgrades" \
            4 "Exit" \
            2>&1 >/dev/tty)

        case $choice in
            1) start_auto_buy ;;
            2) stop_auto_buy ;;
            3) show_best_upgrades ;;
            4) exit 0 ;;
        esac
    done
}

# Function to start auto buy
start_auto_buy() {
    if [ -z "$Authorization" ]; then
        Authorization=$(dialog --clear --title "Authorization" \
            --inputbox "Enter Authorization:" 8 60 \
            2>&1 >/dev/tty)
    fi

    if [ -z "$min_balance_threshold" ] || [ "$min_balance_threshold" -eq 0 ]; then
        min_balance_threshold=$(dialog --clear --title "Minimum Balance Threshold" \
            --inputbox "Enter minimum balance threshold:" 8 60 \
            2>&1 >/dev/tty)
    fi

    running=true
    dialog --infobox "Auto Buy started. Check terminal for progress." 5 50
    sleep 2
    clear

    # Auto buy logic here (similar to the main() function in the previous script)
    while $running; do
        echo -e "${green}Fetching available upgrades...${rest}"
        available_upgrades=$(get_best_items)
        
        if [ -z "$available_upgrades" ]; then
            echo -e "${red}No valid items found to buy.${rest}"
            break
        fi
        
        echo -e "${green}Fetching current balance...${rest}"
        current_balance=$(curl -s -X POST \
            -H "Authorization: $Authorization" \
            -H "Origin: https://hamsterkombat.io" \
            -H "Referer: https://hamsterkombat.io/" \
            https://api.hamsterkombat.io/clicker/sync | jq -r '.clickerUser.balanceCoins')
        
        upgrade_found=false
        
        echo "$available_upgrades" | while read -r upgrade; do
            id=$(echo "$upgrade" | cut -d',' -f1 | cut -d':' -f2 | xargs)
            efficiency=$(echo "$upgrade" | cut -d',' -f2 | cut -d':' -f2 | xargs)
            
            upgrade_details=$(curl -s -X POST -H "Authorization: $Authorization" -H "Origin: https://hamsterkombat.io" -H "Referer: https://hamsterkombat.io/" https://api.hamsterkombat.io/clicker/upgrades-for-buy | jq -r ".upgradesForBuy[] | select(.id == \"$id\")")
            price=$(echo "$upgrade_details" | jq -r '.price')
            cooldown=$(echo "$upgrade_details" | jq -r '.cooldownSeconds // 0')
            
            if (( $(echo "$current_balance - $price > $min_balance_threshold" | bc -l) )); then
                if [ "$cooldown" -eq 0 ]; then
                    echo -e "${green}Attempting to purchase upgrade '${yellow}$id${green}'...${rest}"
                    purchase_status=$(purchase_upgrade "$id")
                    if echo "$purchase_status" | grep -q "error_code"; then
                        echo -e "${red}Failed to purchase upgrade. Error: $purchase_status${rest}"
                    else
                        echo -e "${green}Upgrade '${yellow}$id${green}' purchased successfully.${rest}"
                        last_upgraded_id="$id"
                        upgrade_found=true
                        sleep_time=$(( ( RANDOM % 4 ) + 8 ))
                        echo -e "${green}Waiting ${yellow}$sleep_time${green} seconds before next purchase...${rest}"
                        sleep "$sleep_time"
                        break
                    fi
                else
                    echo -e "${yellow}Upgrade is on cooldown for ${cyan}$cooldown${yellow} seconds. Checking next best upgrade...${rest}"
                fi
            else
                echo -e "${red}Insufficient balance for upgrade '${yellow}$id${red}'. Checking next best upgrade...${rest}"
            fi
        done
        
        if [ "$upgrade_found" = false ]; then
            echo -e "${yellow}No suitable upgrade found within the balance threshold. Waiting before next check...${rest}"
            sleep 60
        fi
    done
}

# Function to stop auto buy
stop_auto_buy() {
    running=false
    dialog --infobox "Auto Buy stopped." 5 50
    sleep 2
}

# Function to show best upgrades
show_best_upgrades() {
    if [ -z "$Authorization" ]; then
        Authorization=$(dialog --clear --title "Authorization" \
            --inputbox "Enter Authorization:" 8 60 \
            2>&1 >/dev/tty)
    fi

    upgrades=$(get_best_items)
    dialog --title "Best Upgrades" --msgbox "$upgrades" 20 70
}

# Start the main menu
show_main_menu