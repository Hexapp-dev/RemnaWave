#!/usr/bin/env bash

set -euo pipefail

# HEX Proxy Setup Script
# Establishes SSH tunnel with SOCKS proxy

clear_screen() {
  if command -v tput >/dev/null 2>&1; then
    tput reset || printf '\033c'
  elif command -v clear >/dev/null 2>&1; then
    clear
  else
    printf '\033[2J\033[H'
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || return 1
}

print_header() {
  echo ""
  echo "============================================================"
  echo "$1"
  echo "============================================================"
}

abort() {
  echo "Error: $1" >&2
  exit 1
}

print_banner() {
  local MAGENTA CYAN GRAY SEP BOLD RESET
  if [ -t 1 ]; then
    MAGENTA='\033[38;5;141m'  # muted orchid
    CYAN='\033[38;5;81m'     # soft teal
    GRAY='\033[38;5;245m'    # neutral gray text
    SEP='\033[38;5;244m'     # subtle separator
    BOLD='\033[1m'
    RESET='\033[0m'
  else
    MAGENTA=''; CYAN=''; GRAY=''; SEP=''; BOLD=''; RESET=''
  fi

  clear_screen 
  echo ""
  echo -e "${SEP}╔════════════════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${SEP}║                                                                        ║${RESET}"
  echo -e "${SEP}║   ${MAGENTA}${BOLD}██╗  ██╗███████╗██╗  ██╗  ${CYAN} ██████╗ ██████╗  ██████╗ ██╗  ██╗██╗   ██╗${SEP}║${RESET}"
  echo -e "${SEP}║   ${MAGENTA}${BOLD}██║  ██║██╔════╝╚██╗██╔╝  ${CYAN} ██╔══██╗██╔══██╗██╔═══██╗╚██╗██╔╝╚██╗ ██╔╝${SEP}║${RESET}"
  echo -e "${SEP}║   ${MAGENTA}${BOLD}███████║█████╗   ╚███╔╝   ${CYAN} ██████╔╝██████╔╝██║   ██║ ╚███╔╝  ╚████╔╝ ${SEP}║${RESET}"
  echo -e "${SEP}║   ${MAGENTA}${BOLD}██╔══██║██╔══╝   ██╔██╗   ${CYAN} ██╔═══╝ ██╔══██╗██║   ██║ ██╔██╗   ╚██╔╝  ${SEP}║${RESET}"
  echo -e "${SEP}║   ${MAGENTA}${BOLD}██║  ██║███████╗██╔╝ ██╗  ${CYAN} ██║     ██║  ██║╚██████╔╝██╔╝ ██╗   ██║   ${SEP}║${RESET}"
  echo -e "${SEP}║   ${MAGENTA}${BOLD}╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝  ${CYAN} ╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ${SEP}║${RESET}"
  echo -e "${SEP}║                                                                        ║${RESET}"
  echo -e "${SEP}╚════════════════════════════════════════════════════════════════════════╝${RESET}"
  echo -e "${GRAY} Website: https://hexapp.dev${RESET}"
  echo -e "${GRAY} telegram Channel: https://t.me/HEXApp_dev${RESET}"
  echo -e "${GRAY} SSH SOCKS Proxy Setup${RESET}\n"
}

print_banner
print_header "HEX Proxy Setup"

# Get user input for server details
read -rp "Enter server IP address: " SERVER_IP
read -rp "Enter username (default: root): " USERNAME
USERNAME=${USERNAME:-root}
read -rsp "Enter password: " PASSWORD
echo

[[ -z "$SERVER_IP" ]] && abort "Server IP cannot be empty."
[[ -z "$USERNAME" ]] && abort "Username cannot be empty."
[[ -z "$PASSWORD" ]] && abort "Password cannot be empty."

# Function to check if port 1080 is already in use
check_port() {
  if lsof -Pi :1080 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "Port 1080 is already in use. Killing existing process..."
    kill $(lsof -Pi :1080 -sTCP:LISTEN -t) 2>/dev/null
    sleep 2
  fi
}

# Function to establish SSH tunnel
establish_tunnel() {
  echo "Establishing SSH tunnel to $USERNAME@$SERVER_IP..."
  
  # Use sshpass to handle password authentication and auto-accept host key
  sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -D 1080 -q -C -N "$USERNAME@$SERVER_IP" &
  
  # Store the PID of the SSH process
  SSH_PID=$!
  
  # Wait a moment for connection to establish
  sleep 3
  
  # Check if the process is still running
  if kill -0 $SSH_PID 2>/dev/null; then
    echo "✓ SSH tunnel established successfully (PID: $SSH_PID)"
    echo "✓ Tunnel is running in background on port 1080"
    return 0
  else
    echo "✗ Failed to establish SSH tunnel"
    return 1
  fi
}

# Function to set proxy environment variables
set_proxy() {
  echo "Setting proxy environment variables..."
  export http_proxy="socks5h://127.0.0.1:1080"
  export https_proxy="socks5h://127.0.0.1:1080"
  
  echo "✓ Proxy settings applied:"
  echo "  HTTP_PROXY: $http_proxy"
  echo "  HTTPS_PROXY: $https_proxy"
  echo
  echo "To make these settings permanent, add the following to your ~/.bashrc or ~/.profile:"
  echo "export http_proxy=\"socks5h://127.0.0.1:1080\""
  echo "export https_proxy=\"socks5h://127.0.0.1:1080\""
}

# Function to cleanup on exit
cleanup() {
  echo
  echo "Cleaning up..."
  if [ ! -z "$SSH_PID" ]; then
    kill $SSH_PID 2>/dev/null
    echo "✓ SSH tunnel terminated"
  fi
  exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

print_header "Checking prerequisites"
# Check if sshpass is installed
if ! require_cmd sshpass; then
  abort "sshpass is not installed. Please install it using:
  Ubuntu/Debian: sudo apt-get install sshpass
  CentOS/RHEL: sudo yum install sshpass
  macOS: brew install sshpass"
fi

print_header "Preparing SSH tunnel"
# Check if port is available
check_port

# Establish SSH tunnel
if establish_tunnel; then
  # Set proxy environment variables
  set_proxy
  
  echo ""
  echo "============================================================"
  echo "Setup Complete"
  echo "============================================================"
  echo "✓ SSH tunnel is running in background"
  echo "✓ Proxy is configured and ready to use"
  echo ""
  echo "To stop the tunnel, press Ctrl+C or run: kill $SSH_PID"
  echo "To test the proxy, try: curl --proxy socks5h://127.0.0.1:1080 http://httpbin.org/ip"
  echo ""
  
  # Keep script running to maintain the tunnel
  echo "Press Ctrl+C to stop the tunnel and exit..."
  while true; do
    sleep 1
    # Check if SSH process is still running
    if ! kill -0 $SSH_PID 2>/dev/null; then
      echo "SSH tunnel connection lost. Exiting..."
      break
    fi
  done
else
  abort "Failed to establish SSH tunnel. Please check your credentials and network connection."
fi

cleanup
