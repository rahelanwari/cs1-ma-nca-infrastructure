#!/bin/bash
# =====================================================================
# SOAR BAN SCRIPT on mgmt01 (SOAR block action)
# The SOAR logs in with its own SSH key. That key can ONLY run this
# script (forced command in authorized_keys). The IP address to ban
# arrives in $SSH_ORIGINAL_COMMAND.
# The script checks the IP and asks fail2ban on ws01 to ban it.
# =====================================================================
set -euo pipefail

IP="${SSH_ORIGINAL_COMMAND:-}"
WS01="192.168.10.10"

# 1. Only one plain IPv4 address is accepted, nothing else
if ! [[ "$IP" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
  echo "REJECTED: not an IPv4 address"
  logger -t soar-ban "rejected: not an IPv4 address"
  exit 1
fi
for octet in "${BASH_REMATCH[@]:1}"; do
  if (( 10#$octet > 255 )); then
    echo "REJECTED: not a valid IPv4 address"
    logger -t soar-ban "rejected: not a valid IPv4 address"
    exit 1
  fi
done

# 2. Whitelist: never ban the management segment, the firewall or ws01 itself
case "$IP" in
  192.168.20.*|192.168.10.1|192.168.10.10|127.*)
    echo "REJECTED: $IP is on the whitelist"
    logger -t soar-ban "rejected: $IP is on the whitelist"
    exit 1
    ;;
esac

# 3. Ask fail2ban on ws01 to ban the IP (the jail bans for 5 minutes)
ssh -o BatchMode=yes -o ConnectTimeout=10 "student@${WS01}" \
  "sudo fail2ban-client set sshd banip ${IP}" > /dev/null

echo "BANNED: $IP on ws01 for 5 minutes"
logger -t soar-ban "banned $IP on ws01"