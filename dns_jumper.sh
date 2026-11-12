#!/bin/bash
# ==============================================================================
# Script: DNS Jumper para Linux
# Descripción: Mide latencia de servidores DNS, aplica el más rápido y limpia caché.
# Autor: Luis David Urbaneja
# ==============================================================================


GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'


declare -A DNS_SERVERS=(
    ["Cloudflare Primary"]="1.1.1.1"
    ["Cloudflare Secondary"]="1.0.0.1"
    ["Google Primary"]="8.8.8.8"
    ["Google Secondary"]="8.8.4.4"
    ["OpenDNS Primary"]="208.67.222.222"
    ["OpenDNS Secondary"]="208.67.220.220"
    ["Quad9 Primary"]="9.9.9.9"
    ["AdGuard Primary"]="94.140.14.14"
)


flush_dns_cache() {
    echo -e "\n${YELLOW}[i] Limpiando caché DNS del sistema...${RESET}"
    if command -v resolvectl &> /dev/null; then
        sudo resolvectl flush-caches
        echo -e "${GREEN}[✓] Caché limpiado exitosamente con resolvectl.${RESET}"
    elif command -v systemd-resolve &> /dev/null; then
        sudo systemd-resolve --flush-caches
        echo -e "${GREEN}[✓] Caché limpiado exitosamente con systemd-resolve.${RESET}"
    else
        echo -e "${RED}[!] No se encontró resolvectl ni systemd-resolve para vaciar la caché.${RESET}"
    fi
}


echo -e "${CYAN}====================================================${RESET}"
echo -e "${CYAN}             DNS JUMPER FOR LINUX                   ${RESET}"
echo -e "${CYAN}====================================================${RESET}"

echo -e "\n${YELLOW}[*] Probando latencia de servidores DNS (espera unos segundos)...${RESET}\n"


TMP_FILE=$(mktemp)

for name in "${!DNS_SERVERS[@]}"; do
    ip="${DNS_SERVERS[$name]}"
    

    latency=$(ping -c 3 -W 1 "$ip" 2>/dev/null | awk -F'/' 'END { print $5 }')

    if [ -n "$latency" ]; then
  
        echo "$latency $name $ip" >> "$TMP_FILE"
    else
        echo "9999 $name $ip (Sin respuesta)" >> "$TMP_FILE"
    fi
done


echo -e "LATENCIA\tSERVIDOR\t\t\tIP"
echo -e "----------------------------------------------------"

sort -n "$TMP_FILE" | while read -r lat name ip extra; do
    if [ "$lat" == "9999" ]; then
        printf "${RED}%-15s %-30s %s${RESET}\n" "TIMEOUT" "$name" "$ip"
    else
        printf "${GREEN}%-15s${RESET} %-30s %s\n" "${lat} ms" "$name" "$ip"
    fi
done


WINNER=$(sort -n "$TMP_FILE" | grep -v "9999" | head -n 1)
WINNER_NAME=$(echo "$WINNER" | awk '{for (i=2; i<NF; i++) printf $i " "; print ""}' | xargs)
WINNER_IP=$(echo "$WINNER" | awk '{print $NF}')
WINNER_LAT=$(echo "$WINNER" | awk '{print $1}')

rm -f "$TMP_FILE"

echo -e "\n----------------------------------------------------"
if [ -n "$WINNER_IP" ]; then
    echo -e "${GREEN}[★] El DNS más rápido es: ${WINNER_NAME} (${WINNER_IP}) con ${WINNER_LAT} ms${RESET}"
else
    echo -e "${RED}[!] No se pudo determinar un servidor DNS activo.${RESET}"
    exit 1
fi

echo -e "\n${CYAN}Opciones:${RESET}"
echo "1) Aplicar el DNS más rápido al sistema"
echo "2) Limpiar el caché DNS únicamente"
echo "3) Aplicar el DNS ganador Y limpiar caché"
echo "4) Salir"

read -rp "Selecciona una opción [1-4]: " OPTION

case $OPTION in
    1|3)
        echo -e "\n${YELLOW}[*] Aplicando $WINNER_IP en la interfaz principal...${RESET}"

        INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)
        
        if [ -n "$INTERFACE" ]; then
            sudo resolvectl dns "$INTERFACE" "$WINNER_IP"
            echo -e "${GREEN}[✓] Servidor DNS actualizado a $WINNER_IP en la interfaz $INTERFACE.${RESET}"
        else
            echo -e "${RED}[!] No se detectó interfaz de red activa.${RESET}"
        fi
        
        if [ "$OPTION" -eq 3 ]; then
            flush_dns_cache
        fi
        ;;
    2)
        flush_dns_cache
        ;;
    4|*)
        echo -e "\nSaliendo..."
        ;;
esac
