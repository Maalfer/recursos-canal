#!/usr/bin/env bash
set -euo pipefail

# --- CONFIG ---
API_KEY="TU-API-KEY"
LOG_FILE="/var/log/apache2/dockerlabs_access.log"
MAX_AGE_DAYS=90
SLEEP_SEC=0.7
THRESHOLD=2      # umbral para bloquear
IPSET_NAME="bloqueados"
DEBUG="${DEBUG:-0}"

# --- Requisitos ---
for bin in curl jq awk sort uniq sed grep ipset; do
  command -v "$bin" >/dev/null 2>&1 || { echo "Falta '$bin'"; exit 1; }
done

[[ -r "$LOG_FILE" ]] || { echo "No puedo leer el log: $LOG_FILE"; exit 1; }

# Extraer solo IPv4 válidas de la primera columna del log
mapfile -t IPS < <(awk '{print $1}' "$LOG_FILE" \
  | grep -Eo '(^| )[0-9]{1,3}(\.[0-9]{1,3}){3}($| )' \
  | tr -d ' ' | sort -u)

if [[ ${#IPS[@]} -eq 0 ]]; then
  echo "No se han encontrado IPs IPv4 en $LOG_FILE"
  exit 0
fi

# Comprobar que el set existe
if ! ipset list "$IPSET_NAME" &>/dev/null; then
  echo "El set de ipset '$IPSET_NAME' no existe. Créalo con:"
  echo "sudo ipset create $IPSET_NAME hash:ip"
  exit 1
fi

# Configuración extra para curl
CURL_FLAGS=(-sS --fail --connect-timeout 10 --max-time 20 --retry 2 --retry-connrefused)
[[ "$DEBUG" == "1" ]] && CURL_FLAGS+=(-v)

echo "IP,abuseConfidenceScore"
for ip in "${IPS[@]}"; do
  RESP=$(curl "${CURL_FLAGS[@]}" -G "https://api.abuseipdb.com/api/v2/check" \
    --data-urlencode "ipAddress=${ip}" \
    --data-urlencode "maxAgeInDays=${MAX_AGE_DAYS}" \
    -H "Key: ${API_KEY}" \
    -H "Accept: application/json" \
    || true)

  if [[ -z "${RESP:-}" ]]; then
    echo "${ip},NA"
    sleep "$SLEEP_SEC"
    continue
  fi

  if jq -e 'has("errors")' >/dev/null 2>&1 <<<"$RESP"; then
    err="$(jq -r '.errors[0].detail // "error"' <<<"$RESP")"
    [[ "$DEBUG" == "1" ]] && echo "Error $ip: $err" >&2
    echo "${ip},NA"
    sleep "$SLEEP_SEC"
    continue
  fi

  score="$(jq -r '.data.abuseConfidenceScore // 0' <<<"$RESP" 2>/dev/null || echo 0)"
  echo "${ip},${score}"

  # Si supera el umbral, añadir a ipset
  if (( score > THRESHOLD )); then
    if ! ipset test "$IPSET_NAME" "$ip" &>/dev/null; then
      sudo ipset add "$IPSET_NAME" "$ip"
      echo " → $ip añadido a $IPSET_NAME (score $score)"
    else
      [[ "$DEBUG" == "1" ]] && echo " → $ip ya estaba en $IPSET_NAME"
    fi
  fi

  sleep "$SLEEP_SEC"
done
