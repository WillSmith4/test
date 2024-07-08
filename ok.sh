#!/bin/bash

# Globalne zmienne
declare -A tokens=()
running=false
declare -A next_click_times=()
card_buy_running=false
auth=""
balance_threshold=0
upgrade_priority=()
selected_upgrades=()
upgrade_data=()
last_checked_upgrade=""
declare -A proxy_settings=()

# Funkcje pomocnicze
clear_screen() {
  clear
}

press_any_key() {
  read -n 1 -s -r -p "Naciśnij dowolny klawisz, aby kontynuować..."
}

# Główne menu
show_main_menu() {
  while true; do
    clear_screen
    echo "======= Główne Menu ======="
    echo "1. Auto-login"
    echo "2. Auto Card Buy"
    echo "3. Wyjście"
    echo "==========================="
    read -p "Wybierz opcję: " choice

    case $choice in
    1)
      auto_login_menu
      ;;
    2)
      auto_card_buy_menu
      ;;
    3)
      exit 0
      ;;
    *)
      echo "Nieprawidłowy wybór. Spróbuj ponownie."
      ;;
    esac
    press_any_key
  done
}

# Menu Auto-login
auto_login_menu() {
  while true; do
    clear_screen
    echo "======= Auto-login Menu ======="
    echo "1. Zarządzaj tokenami"
    echo "2. Start"
    echo "3. Stop"
    echo "4. Status"
    echo "5. Powrót do głównego menu"
    echo "==============================="
    read -p "Wybierz opcję: " choice

    case $choice in
    1)
      manage_tokens
      ;;
    2)
      start_clicking
      ;;
    3)
      stop_clicking
      ;;
    4)
      show_status
      ;;
    5)
      return
      ;;
    *)
      echo "Nieprawidłowy wybór. Spróbuj ponownie."
      ;;
    esac
    press_any_key
  done
}

# Menu Auto Card Buy
auto_card_buy_menu() {
  while true; do
    clear_screen
    echo "======= Auto Card Buy Menu ======="
    echo "1. Ustaw autoryzację"
    echo "2. Ustaw proxy"
    echo "3. Ustaw minimalny próg balansu"
    echo "4. Zarządzaj priorytetami ulepszeń"
    echo "5. Start"
    echo "6. Stop"
    echo "7. Lista ulepszeń"
    echo "8. Powrót do głównego menu"
    echo "=================================="
    read -p "Wybierz opcję: " choice

    case $choice in
    1)
      set_auth
      ;;
    2)
      set_proxy
      ;;
    3)
      set_balance_threshold
      ;;
    4)
      manage_upgrade_priority
      ;;
    5)
      start_card_buy
      ;;
    6)
      stop_card_buy
      ;;
    7)
      list_upgrades
      ;;
    8)
      return
      ;;
    *)
      echo "Nieprawidłowy wybór. Spróbuj ponownie."
      ;;
    esac
    press_any_key
  done
}

# Funkcje Auto-login
manage_tokens() {
  while true; do
    clear_screen
    echo "===== Zarządzanie tokenami ====="
    echo "1. Dodaj token"
    echo "2. Usuń token"
    echo "3. Lista tokenów"
    echo "4. Powrót do menu Auto-login"
    echo "================================"
    read -p "Wybierz opcję: " choice

    case $choice in
    1)
      add_token
      ;;
    2)
      remove_token
      ;;
    3)
      list_tokens
      ;;
    4)
      return
      ;;
    *)
      echo "Nieprawidłowy wybór. Spróbuj ponownie."
      ;;
    esac
    press_any_key
  done
}

add_token() {
  read -p "Podaj nazwę konta: " account
  read -p "Podaj token: " token
  tokens["$account"]=$token
  echo "Token dodany pomyślnie."
}

remove_token() {
  read -p "Podaj nazwę konta do usunięcia: " account
  if [[ -v tokens["$account"] ]]; then
    unset tokens["$account"]
    echo "Token usunięty pomyślnie."
  else
    echo "Nie znaleziono tokenu dla podanego konta."
  fi
}

list_tokens() {
  echo "Lista tokenów:"
  for account in "${!tokens[@]}"; do
    echo "$account: ${tokens[$account]}"
  done
}

start_clicking() {
  if [ ${#tokens[@]} -eq 0 ]; then
    echo "Proszę dodać przynajmniej jeden token autoryzacyjny."
    return
  fi

  running=true
  echo "Rozpoczynanie procesu auto-logowania..."
  for account in "${!tokens[@]}"; do
    (click_loop "$account" "${tokens[$account]}") &
  done
}

stop_clicking() {
  running=false
  echo "Zatrzymywanie procesu auto-logowania..."
  wait
  echo "Proces auto-logowania został zatrzymany."
}

click_loop() {
  local account=$1
  local auth=$2

  while $running; do
    single_click "$account" "$auth"

    current_hour=$(date +%H)
    if [ $current_hour -ge 2 ] && [ $current_hour -lt 7 ]; then
      sleep_time=$((RANDOM % 3600 + 18000)) # 5-6 godzin
      echo "($account) Wykryto porę nocną. Ustawiono dłuższy interwał."
    else
      sleep_time=$((RANDOM % 3600 + 7200)) # 2-3 godziny
      echo "($account) Wykryto porę dzienną. Ustawiono normalny interwał."
    fi

    next_click_times["$account"]=$(($(date +%s) + sleep_time))
    sleep $sleep_time
  done
}

single_click() {
  local account=$1
  local auth=$2

  echo "($account) Wysyłanie żądania..."
  response=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    -H "User-Agent: Mozilla/5.0 (Android 12; Mobile; rv:102.0) Gecko/102.0 Firefox/102.0" \
    -H "Accept: */*" \
    -H "Accept-Language: en-US,en;q=0.5" \
    -H "Referer: https://hamsterkombat.io/" \
    -H "Authorization: Bearer $auth" \
    -H "Origin: https://hamsterkombat.io" \
    -H "Connection: keep-alive" \
    -H "Sec-Fetch-Dest: empty" \
    -H "Sec-Fetch-Mode: cors" \
    -H "Sec-Fetch-Site: same-site" \
    -H "Content-Type: application/json" \
    -d "{\"lastSyncUpdate\":$(date +%s)}" \
    "https://api.hamsterkombat.io/clicker/sync")

  if [ "$response" -eq 200 ]; then
    echo "($account) Zalogowano pomyślnie."
  else
    echo "($account) Logowanie nie powiodło się. Kod statusu: $response"
  fi
}

show_status() {
  clear_screen
  echo "===== Status kliknięć ====="
  current_time=$(date +%s)

  for account in "${!next_click_times[@]}"; do
    next_time=${next_click_times[$account]}
    remaining_time=$((next_time - current_time))
    minutes=$((remaining_time / 60))
    seconds=$((remaining_time % 60))
    printf "%s: %02d:%02d\n" "$account" $minutes $seconds
  done

  echo "==========================="
}

# Funkcje Auto Card Buy
set_auth() {
  read -p "Podaj token autoryzacyjny: " auth
  echo "Token autoryzacyjny ustawiony."
}

set_proxy() {
  while true; do
    clear_screen
    echo "===== Ustawienia Proxy ====="
    echo "1. Adres"
    echo "2. Port"
    echo "3. Nazwa użytkownika"
    echo "4. Hasło"
    echo "5. Protokół (HTTP/HTTPS/SOCKS4/SOCKS5)"
    echo "6. Powrót do menu Auto Card Buy"
    echo "=============================="
    read -p "Wybierz opcję: " choice

    case $choice in
    1)
      read -p "Podaj adres proxy: " proxy_settings[address]
      echo "Adres proxy ustawiony na: ${proxy_settings[address]}"
      ;;
    2)
      read -p "Podaj port proxy: " proxy_settings[port]
      echo "Port proxy ustawiony na: ${proxy_settings[port]}"
      ;;
    3)
      read -p "Podaj nazwę użytkownika proxy: " proxy_settings[username]
      echo "Nazwa użytkownika proxy ustawiona na: ${proxy_settings[username]}"
      ;;
    4)
      read -p "Podaj hasło proxy: " proxy_settings[password]
      echo "Hasło proxy ustawione."
      ;;
    5)
      read -p "Podaj protokół proxy (HTTP/HTTPS/SOCKS4/SOCKS5): " proxy_settings[protocol]
      echo "Protokół proxy ustawiony na: ${proxy_settings[protocol]}"
      ;;
    6)
      return
      ;;
    *)
      echo "Nieprawidłowy wybór. Spróbuj ponownie."
      ;;
    esac
    press_any_key
  done
}

set_balance_threshold() {
  read -p "Podaj minimalny próg balansu: " balance_threshold
  echo "Minimalny próg balansu ustawiony na: $balance_threshold"
}

manage_upgrade_priority() {
  while true; do
    clear_screen
    echo "===== Zarządzaj priorytetami ulepszeń ====="
    echo "1. Dodaj ulepszenie"
    echo "2. Usuń ulepszenie"
    echo "3. Wyświetl priorytety"
    echo "4. Powrót do menu Auto Card Buy"
    echo "=========================================="
    read -p "Wybierz opcję: " choice

    case $choice in
    1)
      add_upgrade
      ;;
    2)
      remove_upgrade
      ;;
    3)
      show_upgrade_priority
      ;;
    4)
      return
      ;;
    *)
      echo "Nieprawidłowy wybór. Spróbuj ponownie."
      ;;
    esac
    press_any_key
  done
}

add_upgrade() {
  list_upgrades
  read -p "Podaj ID ulepszenia do dodania: " upgrade_id
  upgrade_priority+=("$upgrade_id")
  echo "Ulepszenie $upgrade_id dodane do priorytetów."
}

remove_upgrade() {
  show_upgrade_priority
  read -p "Podaj numer ulepszenia do usunięcia: " upgrade_index
  if ((upgrade_index > 0 && upgrade_index <= ${#upgrade_priority[@]})); then
    unset "upgrade_priority[$(($upgrade_index - 1))]"
    upgrade_priority=("${upgrade_priority[@]}") # Reindex array
    echo "Ulepszenie usunięte z priorytetów."
  else
    echo "Nieprawidłowy numer ulepszenia."
  fi
}

show_upgrade_priority() {
  echo "Lista priorytetów ulepszeń:"
  if [ ${#upgrade_priority[@]} -eq 0 ]; then
    echo "Brak priorytetów ulepszeń."
  else
    for i in "${!upgrade_priority[@]}"; do
      echo "$((i + 1)). ${upgrade_priority[$i]}"
    done
  fi
}

start_card_buy() {
  if [ -z "$auth" ] || [ $balance_threshold -eq 0 ]; then
    echo "Proszę ustawić token autoryzacyjny i minimalny próg balansu."
    return
  fi
  card_buy_running=true
  echo "Rozpoczynanie procesu Auto Card Buy..."
  (card_buy_loop) &
}

stop_card_buy() {
  card_buy_running=false
  echo "Zatrzymywanie procesu Auto Card Buy..."
  wait
  echo "Proces Auto Card Buy został zatrzymany."
}

card_buy_loop() {
  while $card_buy_running; do
    fetch_upgrades
    fetch_balance
    check_and_buy_upgrades
    sleep 60
  done
}

fetch_upgrades() {
  echo "Pobieranie dostępnych ulepszeń..."
  upgrade_data=$(curl -s -X POST \
    -H "User-Agent: Mozilla/5.0 (Android 12; Mobile; rv:102.0) Gecko/102.0 Firefox/102.0" \
    -H "Accept: */*" \
    -H "Accept-Language: en-US,en;q=0.5" \
    -H "Referer: https://hamsterkombat.io/" \
    -H "Authorization: $auth" \
    -H "Origin: https://hamsterkombat.io" \
    -H "Connection: keep-alive" \
    -H "Sec-Fetch-Dest: empty" \
    -H "Sec-Fetch-Mode: cors" \
    -H "Sec-Fetch-Site: same-site" \
    -H "Content-Type: application/json" \
    "https://api.hamsterkombat.io/clicker/upgrades-for-buy")

  # Parse the upgrade data and store relevant information
  selected_upgrades=()
  while IFS= read -r line; do
    upgrade_id=$(echo "$line" | jq -r '.id')
    upgrade_price=$(echo "$line" | jq -r '.price')
    upgrade_profit=$(echo "$line" | jq -r '.profitPerHourDelta')
    upgrade_cooldown=$(echo "$line" | jq -r '.cooldownSeconds // 0')
    selected_upgrades+=("$upgrade_id $upgrade_price $upgrade_profit $upgrade_cooldown")
  done < <(echo "$upgrade_data" | jq -r '.upgradesForBuy[] | select(.isExpired == false and .isAvailable == true and .profitPerHourDelta != 0 and .price != 0)')
}

fetch_balance() {
  echo "Pobieranie aktualnego balansu..."
  balance_response=$(curl -s -X POST \
    -H "Authorization: $auth" \
    -H "Origin: https://hamsterkombat.io" \
    -H "Referer: https://hamsterkombat.io/" \
    "https://api.hamsterkombat.io/clicker/sync")
  current_balance=$(echo "$balance_response" | jq -r '.clickerUser.balanceCoins')
}

check_and_buy_upgrades() {
  local best_upgrade_id=""
  local best_upgrade_price=0
  local best_upgrade_profit=0

  # Iterate through priority upgrades
  for priority_upgrade_id in "${upgrade_priority[@]}"; do
    # Find the upgrade in the selected_upgrades array
    for upgrade in "${selected_upgrades[@]}"; do
      upgrade_id=$(echo "$upgrade" | awk '{print $1}')
      if [ "$upgrade_id" == "$priority_upgrade_id" ]; then
        upgrade_price=$(echo "$upgrade" | awk '{print $2}')
        upgrade_profit=$(echo "$upgrade" | awk '{print $3}')
        upgrade_cooldown=$(echo "$upgrade" | awk '{print $4}')

        # Check if the upgrade is affordable and not on cooldown
        if ((current_balance - upgrade_price > balance_threshold)) && [ "$upgrade_cooldown" -eq 0 ]; then
          # Check if this upgrade is more profitable than the current best
          if ((upgrade_profit > best_upgrade_profit)); then
            best_upgrade_id=$upgrade_id
            best_upgrade_price=$upgrade_price
            best_upgrade_profit=$upgrade_profit
          fi
        fi
        break
      fi
    done
  done

  # If a suitable upgrade was found, attempt to purchase it
  if [ -n "$best_upgrade_id" ]; then
    echo "Próba zakupu ulepszenia $best_upgrade_id..."
    purchase_response=$(curl -s -X POST \
      -H "Content-Type: application/json" \
      -H "Authorization: $auth" \
      -H "Origin: https://hamsterkombat.io" \
      -H "Referer: https://hamsterkombat.io/" \
      -d "{\"upgradeId\":\"$best_upgrade_id\",\"timestamp\":$(date +%s000)}" \
      "https://api.hamsterkombat.io/clicker/buy-upgrade")

    if [ "$(echo "$purchase_response" | jq -r '.success')" == "true" ]; then
      echo "Ulepszenie $best_upgrade_id zakupione pomyślnie."
      last_checked_upgrade=$best_upgrade_id
      sleep $((RANDOM % 4 + 8))
    else
      echo "Nie udało się zakupić ulepszenia $best_upgrade_id."
      sleep 60
    fi
  else
    echo "Brak odpowiedniego ulepszenia do zakupu w tym momencie."
    sleep 60
  fi
}

list_upgrades() {
  echo "Pobieranie listy ulepszeń..."
  upgrades=$(curl -s -X POST \
    -H "User-Agent: Mozilla/5.0 (Android 12; Mobile; rv:102.0) Gecko/102.0 Firefox/102.0" \
    -H "Accept: */*" \
    -H "Accept-Language: en-US,en;q=0.5" \
    -H "Referer: https://hamsterkombat.io/" \
    -H "Authorization: $auth" \
    -H "Origin: https://hamsterkombat.io" \
    -H "Connection: keep-alive" \
    -H "Sec-Fetch-Dest: empty" \
    -H "Sec-Fetch-Mode: cors" \
    -H "Sec-Fetch-Site: same-site" \
    -H "Content-Type: application/json" \
    "https://api.hamsterkombat.io/clicker/upgrades-for-buy")
  echo "Lista ulepszeń:"
  echo "$upgrades" | jq -r '.upgradesForBuy[] | select(.isExpired == false and .isAvailable == true and .profitPerHourDelta != 0 and .price != 0) | . += {"efficiency": (.profitPerHourDelta / .price)} | sort_by(.efficiency) | reverse | .[:10] | .[] | "ID: \(.id), Efektywność: \(.efficiency)"'
}

# Uruchomienie głównego menu
show_main_menu