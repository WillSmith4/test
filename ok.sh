#!/bin/bash

# Colors
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
purple='\033[0;35m'
cyan='\033[0;36m'
blue='\033[0;34m'
rest='\033[0m'

# Global variables
Authorization=""
min_balance_threshold=0
last_upgraded_id=""
running=false
tokens=()
log_buffer=""

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

# Function to update log
update_log() {
    log_buffer+="$(date '+%Y-%m-%d %H:%M:%S') - $1\n"
}

# Function to show logs
show_logs() {
    dialog --title "Log" --no-cancel --ok-label "Back" --msgbox "$log_buffer" 20 70
}

# Function to show the main menu
show_main_menu() {
    while true; do
        choice=$(dialog --clear --title "Hamster Kombat Auto Tools" \
            --menu "Choose an option:" 15 50 3 \
            1 "Auto Card Buy" \
            2 "Auto Login" \
            3 "Exit" \
            2>&1 >/dev/tty)

        case $choice in
            1) auto_card_buy_menu ;;
            2) auto_login_menu ;;
            3) exit 0 ;;
        esac
    done
}

# Function to show Auto Card Buy menu
auto_card_buy_menu() {
    while true; do
        choice=$(dialog --clear --title "Auto Card Buy" \
            --menu "Choose an option:" 15 50 5 \
            1 "Start Auto Buy" \
            2 "Stop Auto Buy" \
            3 "Show Best Upgrades" \
            4 "Show Logs" \
            5 "Back to Main Menu" \
            2>&1 >/dev/tty)

        case $choice in
            1) start_auto_buy ;;
            2) stop_auto_buy ;;
            3) show_best_upgrades ;;
            4) show_logs ;;
            5) return ;;
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
    update_log "Auto Buy started."

    # Start the auto-buy process in the background
    (
        while $running; do
            update_log "Fetching available upgrades..."
            available_upgrades=$(get_best_items)
            
            if [ -z "$available_upgrades" ]; then
                update_log "No valid items found to buy."
                break
            fi
            
            update_log "Fetching current balance..."
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
                        update_log "Attempting to purchase upgrade '$id'..."
                        purchase_status=$(purchase_upgrade "$id")
                        if echo "$purchase_status" | grep -q "error_code"; then
                            update_log "Failed to purchase upgrade. Error: $purchase_status"
                        else
                            update_log "Upgrade '$id' purchased successfully."
                            last_upgraded_id="$id"
                            upgrade_found=true
                            sleep_time=$(( ( RANDOM % 4 ) + 8 ))
                            update_log "Waiting $sleep_time seconds before next purchase..."
                            sleep "$sleep_time"
                            break
                        fi
                    else
                        update_log "Upgrade is on cooldown for $cooldown seconds. Checking next best upgrade..."
                    fi
                else
                    update_log "Insufficient balance for upgrade '$id'. Checking next best upgrade..."
                fi
            done
            
            if [ "$upgrade_found" = false ]; then
                update_log "No suitable upgrade found within the balance threshold. Waiting before next check..."
                sleep 60
            fi

            # Update logs in GUI
            dialog --clear --title "Auto Buy Log" --no-cancel --ok-label "Stop" --msgbox "$log_buffer" 20 70
            if [ $? -eq 0 ]; then
                running=false
                break
            fi
        done
    ) &

    # Wait for the background process to finish
    wait
    update_log "Auto Buy stopped."
}

# Function to stop auto buy
stop_auto_buy() {
    running=false
    update_log "Auto Buy stopped."
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

# Function to show Auto Login menu
auto_login_menu() {
    while true; do
        choice=$(dialog --clear --title "Auto Login" \
            --menu "Choose an option:" 15 50 6 \
            1 "Add Token" \
            2 "Remove Token" \
            3 "Start Auto Login" \
            4 "Stop Auto Login" \
            5 "Show Logs" \
            6 "Back to Main Menu" \
            2>&1 >/dev/tty)

        case $choice in
            1) add_token ;;
            2) remove_token ;;
            3) start_auto_login ;;
            4) stop_auto_login ;;
            5) show_logs ;;
            6) return ;;
        esac
    done
}

# Function to add token
add_token() {
    account=$(dialog --clear --title "Add Token" \
        --inputbox "Enter account name:" 8 60 \
        2>&1 >/dev/tty)
    
    token=$(dialog --clear --title "Add Token" \
        --inputbox "Enter token:" 8 60 \
        2>&1 >/dev/tty)

    if [ -n "$account" ] && [ -n "$token" ]; then
        tokens+=("$account:$token")
        update_log "Token added for account: $account"
    else
        update_log "Invalid input. Token not added."
    fi
}

# Function to remove token
remove_token() {
    if [ ${#tokens[@]} -eq 0 ]; then
        update_log "No tokens to remove."
        return
    fi

    options=()
    for i in "${!tokens[@]}"; do
        account=$(echo "${tokens[$i]}" | cut -d':' -f1)
        options+=("$i" "$account")
    done

    choice=$(dialog --clear --title "Remove Token" \
        --menu "Choose a token to remove:" 15 50 5 \
        "${options[@]}" \
        2>&1 >/dev/tty)

    if [ -n "$choice" ]; then
        account=$(echo "${tokens[$choice]}" | cut -d':' -f1)
        unset 'tokens[$choice]'
        tokens=("${tokens[@]}")
        update_log "Token removed for account: $account"
    fi
}

# Function to start auto login
start_auto_login() {
    if [ ${#tokens[@]} -eq 0 ]; then
        update_log "Please add at least one authorization token."
        return
    fi

    running=true
    update_log "Auto Login started."

    # Start the auto-login process in the background
    (
        while $running; do
            for token_entry in "${tokens[@]}"; do
                account=$(echo "$token_entry" | cut -d':' -f1)
                token=$(echo "$token_entry" | cut -d':' -f2)
                
                update_log "Performing auto login for account: $account"
                login_response=$(curl -s -X POST \
                    -H "Authorization: Bearer $token" \
                    -H "Origin: https://hamsterkombat.io" \
                    -H "Referer: https://hamsterkombat.io/" \
                    https://api.hamsterkombat.io/clicker/sync)
                
                if echo "$login_response" | grep -q "error"; then
                    update_log "Auto login failed for account: $account. Error: $login_response"
                else
                    update_log "Auto login successful for account: $account"
                fi

                current_hour=$(date +%H)
                current_minute=$(date +%M)

                # Convert time to minutes from midnight
                current_time_minutes=$((current_hour * 60 + current_minute))
                night_start_minutes=$((2 * 60))  # 2:00 AM
                night_end_minutes=$((7 * 60))  # 7:00 AM

                if [ $current_time_minutes -ge $night_start_minutes ] && [ $current_time_minutes -lt $night_end_minutes ]; then
                    # Night (2:00 AM to 6:59 AM)
                    sleep_seconds=$(awk -v min=18000 -v max=21600 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')
                    update_log "($account) Night time detected. Longer interval set: $sleep_seconds seconds"
                else
                    # Day (other hours)
                    sleep_seconds=$(awk -v min=7200 -v max=10800 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')
                    update_log "($account) Day time detected. Normal interval set: $sleep_seconds seconds"
                fi

                update_log "Waiting $sleep_seconds seconds before next login for account: $account"
                
                # Update logs in GUI
                dialog --clear --title "Auto Login Log" --no-cancel --ok-label "Stop" --msgbox "$log_buffer" 20 70
                if [ $? -eq 0 ]; then
                    running=false
                    break 2
                fi

                sleep "$sleep_seconds"
            done
        done
    ) &

    # Wait for the background process to finish
    wait
    update_log "Auto Login stopped."
}

# Function to stop auto login
stop_auto_login() {
    running=false
    update_log "Auto Login stopped."
}

# Start the main menu
show_main_menu
