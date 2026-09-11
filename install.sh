#!/bin/bash

set -e

REPO_URL="https://github.com/admin6501/backhaul.git"
TEMP_DIR="/tmp/backhaul-install"
ROOT_DIR="/root"

GREEN='\033[1;32m'
RED='\033[1;31m'
CYAN='\033[1;36m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
RESET='\033[0m'

clear

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════╗"
echo "║                                              ║"
echo "║          BACKHAUL TUNNEL INSTALLER           ║"
echo "║                                              ║"
echo "║              GitHub Repository               ║"
echo "║                                              ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${RESET}"

echo
echo -e "${WHITE}Repository:${RESET} ${BLUE}${REPO_URL}${RESET}"
echo -e "${WHITE}Install Path:${RESET} ${BLUE}${ROOT_DIR}${RESET}"
echo

echo -e "${YELLOW}Do you want to install the Backhaul tunnel?${RESET}"
echo -e "${WHITE}[${GREEN}Y${WHITE}] Yes    [${RED}N${WHITE}] No${RESET}"
echo

read -r -p "$(echo -e "${CYAN}➜ ${WHITE}Your choice: ${RESET}")" CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo
    echo -e "${RED}✖ Installation cancelled.${RESET}"
    echo
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    echo
    echo -e "${RED}✖ Error: Please run this installer as root.${RESET}"
    echo
    exit 1
fi

echo
echo -e "${CYAN}┌──────────────────────────────────────────────┐${RESET}"
echo -e "${CYAN}│${RESET} ${WHITE}Starting Backhaul installation...${RESET}       ${CYAN}│${RESET}"
echo -e "${CYAN}└──────────────────────────────────────────────┘${RESET}"
echo

echo -e "${BLUE}[1/5]${RESET} ${WHITE}Preparing temporary directory...${RESET}"
rm -rf "$TEMP_DIR"
echo -e "      ${GREEN}✔ Done${RESET}"

echo
echo -e "${BLUE}[2/5]${RESET} ${WHITE}Cloning Backhaul repository...${RESET}"
git clone "$REPO_URL" "$TEMP_DIR" >/dev/null 2>&1
echo -e "      ${GREEN}✔ Repository cloned successfully${RESET}"

echo
echo -e "${BLUE}[3/5]${RESET} ${WHITE}Installing files to /root...${RESET}"
cp -a "$TEMP_DIR"/. "$ROOT_DIR"/
echo -e "      ${GREEN}✔ Files installed successfully${RESET}"

echo
echo -e "${BLUE}[4/5]${RESET} ${WHITE}Configuring permissions...${RESET}"
chmod 755 "$ROOT_DIR/backhaul.sh"
chmod 755 "$ROOT_DIR/backhaul-core"
chmod 755 "$ROOT_DIR/backhaul-core/backhaul_premium"
echo -e "      ${GREEN}✔ Permissions configured${RESET}"

echo
echo -e "${BLUE}[5/5]${RESET} ${WHITE}Cleaning temporary files...${RESET}"
rm -rf "$TEMP_DIR"
rm -f "$ROOT_DIR/LICENSE"
echo -e "      ${GREEN}✔ Cleanup completed${RESET}"

echo
echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════╗"
echo "║                                              ║"
echo "║       ✔ INSTALLATION COMPLETED SUCCESSFULLY  ║"
echo "║                                              ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${RESET}"

echo
echo -e "${WHITE}Backhaul has been installed in:${RESET} ${CYAN}/root${RESET}"
echo
echo -e "${YELLOW}You can now run the Backhaul tunnel using the command:${RESET}"
echo
echo -e "${GREEN}bash backhaul.sh${RESET}"
echo
