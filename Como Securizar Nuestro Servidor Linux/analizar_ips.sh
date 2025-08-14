#!/usr/bin/env bash
set -euo pipefail

# --- CONFIG ---
API_KEY="TU-API-KEY"
LOG_FILE="/var/log/apache2/dockerlabs_access.log"
MAX_AGE_DAYS=90
SLEEP_SEC=0.7   # baja si quieres más velocidad
DEBUG="${DEBUG:-0}"

for bin in curl jq awk sort uniq sed grep; do
  command -v "$bin" >/dev/null 2>&1 || { echo "Falta '$bin'"; exit 1; }
done

[[ -r "$LOG_FILE" ]] || { echo "No puedo leer el log: $LOG_FILE"; exit 1; }

# Solo IPv4 válidas de la primera columna
mapfile -t IPS < <(awk '{print $1}' "$LOG_FILE" \
  | grep -Eo '(^| )[0-9]{1,3}(\.[0-9]{1,3}){3}($| )' \
  | tr -d ' ' | sort -u)

if [[ ${#IPS[@]} -eq 0 ]]; then
  echo "No se han encontrado IPs IPv4 en $LOG_FILE"
  exit 0
fi

# Flag curl (debug opcional)
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

  # Si no hay respuesta (timeout / fallo), marca como NA
  if [[ -z "${RESP:-}" ]]; then
    echo "${ip},NA"
    sleep "$SLEEP_SEC"
    continue
  fi

  # Si la API devolvió error, muestra NA
  if jq -e 'has("errors")' >/dev/null 2>&1 <<<"$RESP"; then
    err="$(jq -r '.errors[0].detail // "error"' <<<"$RESP")"
    [[ "$DEBUG" == "1" ]] && echo "Error $ip: $err" >&2
    echo "${ip},NA"
    sleep "$SLEEP_SEC"
    continue
  fi

  score="$(jq -r '.data.abuseConfidenceScore // 0' <<<"$RESP" 2>/dev/null || echo 0)"
  # imprime justo lo que pediste: IP y score
  echo "${ip},${score}"

  sleep "$SLEEP_SEC"
done
