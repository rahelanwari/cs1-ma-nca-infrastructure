#!/bin/bash
# =====================================================================
# SOAR BAN SCRIPT on mgmt01 (SOAR block action)
# The SOAR logs in with its own SSH key. That key can ONLY run this
# script (forced command in authorized_keys). The IP address to ban
# arrives in $SSH_ORIGINAL_COMMAND.
# The script checks the IP and bans it on ALL workstations in the
# Ansible inventory at once, so a new workstation is protected as soon
# as it is in the inventory.
# =====================================================================
set -euo pipefail

IP="${SSH_ORIGINAL_COMMAND:-}"
INVENTORY="/etc/soar/inventory.ini"

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

# 2. Whitelist: never ban the management segment, loopback, or the
#    reserved LAN range .0-.31 (fw01 and the workstations)
case "$IP" in
  192.168.20.*|127.*|192.168.10.[0-9]|192.168.10.[12][0-9]|192.168.10.3[01])
    echo "REJECTED: $IP is on the whitelist"
    logger -t soar-ban "rejected: $IP is on the whitelist"
    exit 1
    ;;
esac

# 3. Ban the IP on all workstations in the inventory, in parallel (Ansible)
#    The fail2ban jail on every workstation bans for 5 minutes.
set +e
OUTPUT=$(ANSIBLE_PYTHON_INTERPRETER=auto_silent ansible -i "$INVENTORY" workstations \
  --become --one-line -T 5 \
  -m ansible.builtin.command -a "fail2ban-client set sshd banip ${IP}" 2>&1)
set -e

OK_HOSTS=$(printf '%s\n' "$OUTPUT" | awk -F' [|] ' '$2 ~ /^(CHANGED|SUCCESS)/ {print $1}' | sort | paste -sd, -)
BAD_HOSTS=$(printf '%s\n' "$OUTPUT" | awk -F' [|] ' '$2 ~ /^(FAILED|UNREACHABLE)/ {print $1}' | sort | paste -sd, -)

if [[ -z "$OK_HOSTS" ]]; then
  echo "FAILED: could not ban $IP on any workstation"
  logger -t soar-ban "failed to ban $IP on any workstation"
  exit 1
fi
if [[ -n "$BAD_HOSTS" ]]; then
  echo "PARTIAL: $IP banned on $OK_HOSTS; failed on $BAD_HOSTS"
  logger -t soar-ban "partial: banned $IP on $OK_HOSTS; failed on $BAD_HOSTS"
  exit 1
fi

echo "BANNED: $IP on $OK_HOSTS for 5 minutes"
logger -t soar-ban "banned $IP on $OK_HOSTS"