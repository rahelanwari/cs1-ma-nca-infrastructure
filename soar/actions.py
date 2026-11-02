"""Response actions of the SOAR.

A1 log_incident: store the incident as a JSON file in an S3 bucket.
A2 notify:       send an e-mail via an SNS topic.
A3 block_ip:     ban the source IP of the attack on ALL workstations for 5 minutes.
                 The SOAR asks mgmt01 over SSH (through the VPN); its key
                 may only run the ban script there. The script bans the IP
                 on every workstation in the Ansible inventory.
A4 record_ban:   write the result of block_ip to the ban history in MariaDB
                 (tables bans and ban_targets), so IT staff can see from mgmt01
                 who was banned, when, and on which workstations.

In DRY_RUN mode (local testing) the actions only write a log line.
"""

import base64
import io
import ipaddress
import json
import logging
import re
from datetime import UTC, datetime, timedelta

log = logging.getLogger("soar")

# block_ip never bans these addresses: the management segment (mgmt01, Ansible),
# loopback and the reserved LAN range .0-.31 (fw01 and all workstations).
# The ban script on mgmt01 checks the same list again.
PROTECTED = [
    ipaddress.ip_network("192.168.20.0/24"),
    ipaddress.ip_network("192.168.10.0/27"),
    ipaddress.ip_network("127.0.0.0/8"),
]

# A ban lasts 5 minutes: the same as bantime in the fail2ban jail (monitoring.yml)
BAN_MINUTES = 5

# Answers of the ban script on mgmt01
BANNED = re.compile(r"^BANNED: (?P<ip>\S+) on (?P<ok>\S+) for \d+ minutes$")
PARTIAL = re.compile(r"^PARTIAL: (?P<ip>\S+) banned on (?P<ok>\S+); failed on (?P<bad>\S+)$")


class SshBlocker:
    """Asks mgmt01 to ban an IP. The SOAR key may only run the ban script there."""

    def __init__(self, host, user, private_key, host_key, timeout=15):
        self.host = host
        self.user = user
        self.private_key = private_key
        self.host_key = host_key  # public ed25519 host key of mgmt01 (base64 part)
        self.timeout = timeout

    def ban(self, ip):
        import paramiko  # only needed when the SOAR really blocks

        key = paramiko.Ed25519Key.from_private_key(io.StringIO(self.private_key))
        client = paramiko.SSHClient()
        # Only trust the real mgmt01: a different host key stops the connection
        client.get_host_keys().add(
            self.host, "ssh-ed25519", paramiko.Ed25519Key(data=base64.b64decode(self.host_key))
        )
        client.set_missing_host_key_policy(paramiko.RejectPolicy())
        client.connect(self.host, username=self.user, pkey=key, timeout=self.timeout,
                       allow_agent=False, look_for_keys=False)
        try:
            # The forced command on mgmt01 receives this text as $SSH_ORIGINAL_COMMAND
            _, stdout, stderr = client.exec_command(ip, timeout=self.timeout)
            output = stdout.read().decode().strip()
            exit_code = stdout.channel.recv_exit_status()
            error = stderr.read().decode().strip()
        finally:
            client.close()

        if exit_code != 0:
            raise RuntimeError(output or error or f"ban script failed with exit code {exit_code}")
        return output


class BanRecorder:
    """Writes one ban to the ban history in MariaDB (tables bans and ban_targets)."""

    def __init__(self, host, user, password, database="soar", port=3306, timeout=5):
        self.host = host
        self.user = user
        self.password = password
        self.database = database
        self.port = port
        self.timeout = timeout

    def save(self, ban):
        import pymysql  # only needed when the SOAR really writes to the database

        connection = pymysql.connect(host=self.host, port=self.port, user=self.user,
                                     password=self.password, database=self.database,
                                     connect_timeout=self.timeout, read_timeout=self.timeout,
                                     write_timeout=self.timeout, autocommit=False)
        try:
            with connection.cursor() as cursor:
                # Parameters (%s) instead of text in the SQL: no SQL injection possible
                cursor.execute(
                    "INSERT INTO bans (banned_at, expires_at, src_ip, status, alert_type,"
                    " alert_host, event_id, detail) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)",
                    (ban["banned_at"], ban["expires_at"], ban["src_ip"], ban["status"],
                     ban["alert_type"], ban["alert_host"], ban["event_id"], ban["detail"]),
                )
                ban_id = cursor.lastrowid
                if ban["targets"]:
                    cursor.executemany(
                        "INSERT INTO ban_targets (ban_id, workstation, result) VALUES (%s, %s, %s)",
                        [(ban_id, workstation, result) for workstation, result in ban["targets"]],
                    )
            # One transaction: the ban and its workstations are stored together, or not at all
            connection.commit()
        finally:
            connection.close()
        return ban_id


def ban_from_result(event, block_result, now=None):
    """Turn the result of block_ip into one row for the ban history.

    status BANNED:  banned on all workstations
    status PARTIAL: banned on some workstations, failed on others
    status FAILED:  nothing was banned (whitelist, invalid IP, mgmt01 not reachable, ...)
    """
    now = (now or datetime.now(UTC)).replace(microsecond=0, tzinfo=None)  # UTC in the database
    detail = str(block_result.get("detail", ""))
    status, targets = "FAILED", []

    if block_result.get("result") == "success":
        match = BANNED.match(detail)
        if match:
            status = "BANNED"
            targets = [(host, "banned") for host in match["ok"].split(",")]
    else:
        match = PARTIAL.match(detail)
        if match:
            status = "PARTIAL"
            targets = ([(host, "banned") for host in match["ok"].split(",")]
                       + [(host, "failed") for host in match["bad"].split(",")])

    return {
        "banned_at": now,
        "expires_at": now + timedelta(minutes=BAN_MINUTES) if status != "FAILED" else None,
        "src_ip": str(event["src_ip"])[:45],
        "status": status,
        "alert_type": event["type"][:64],
        "alert_host": event["host"][:64],
        "event_id": event["id"],
        "detail": detail[:255],
        "targets": targets,
    }


class Actions:
    def __init__(self, s3=None, sns=None, bucket="", topic_arn="", blocker=None, recorder=None,
                 dry_run=False):
        self.s3 = s3
        self.sns = sns
        self.bucket = bucket
        self.topic_arn = topic_arn
        self.blocker = blocker
        self.recorder = recorder
        self.dry_run = dry_run

    def log_incident(self, event, results):
        """A1 - write the incident (event, original alert and action results) to S3."""
        day = event["received_at"][:10].replace("-", "/")          # 2026/10/17
        key = f"incidents/{day}/{event['received_at']}-{event['type']}-{event['id'][:8]}.json"
        record = {k: v for k, v in event.items() if k != "alert"}
        record["actions"] = results
        record["alert"] = event["alert"]
        body = json.dumps(record, indent=2)

        if self.dry_run:
            log.info("DRY_RUN log_incident s3://%s/%s", self.bucket or "<bucket>", key)
            return key
        self.s3.put_object(Bucket=self.bucket, Key=key, Body=body.encode("utf-8"),
                           ContentType="application/json")
        return key

    def notify(self, event):
        """A2 - send an e-mail to the IT staff. The tier is in the subject."""
        subject = f"[{event['tier']}] {event['type']} on {event['host']}"
        if event["src_ip"]:
            subject += f" from {event['src_ip']}"
        subject = subject[:100]  # SNS limit for e-mail subjects

        message = "\n".join([
            "Innovatech SOAR - security event",
            "",
            f"Tier:     {event['tier']}",
            f"Type:     {event['type']}",
            f"Severity: {event['severity']}",
            f"Source:   {event['source']}",
            f"Host:     {event['host']}",
            f"Src IP:   {event['src_ip'] or '-'}",
            f"Alert:    {event['alertname']}",
            f"Summary:  {event['summary']}",
            f"Started:  {event['starts_at']}",
            f"Event id: {event['id']}",
        ])

        if self.dry_run:
            log.info("DRY_RUN notify subject=%r", subject)
            return subject
        self.sns.publish(TopicArn=self.topic_arn, Subject=subject, Message=message)
        return subject

    def block_ip(self, event):
        """A3 - ban the source IP of the attack on all workstations for 5 minutes (via mgmt01)."""
        ip = event["src_ip"]
        if not ip:
            raise ValueError("the alert has no src_ip, nothing to block")
        address = ipaddress.IPv4Address(ip)  # ValueError for anything that is not one IPv4 address
        if any(address in network for network in PROTECTED):
            raise ValueError(f"{ip} is on the whitelist, not blocked")

        if self.dry_run:
            log.info("DRY_RUN block_ip %s (attack on %s)", ip, event["host"])
            return f"DRY_RUN: would ban {ip} on all workstations"
        if self.blocker is None:
            raise RuntimeError("block_ip is not configured (BLOCK_HOST is not set)")
        result = self.blocker.ban(str(address))
        log.info("block_ip %s: %s", ip, result)
        return result

    def record_ban(self, event, results):
        """A4 - write the result of block_ip (also a failed one) to the ban history in MariaDB."""
        block_result = next((r for r in results if r["action"] == "block_ip"), None)
        if block_result is None:
            raise ValueError("record_ban needs the result of block_ip")

        if self.dry_run:
            log.info("DRY_RUN record_ban %s", event["src_ip"])
            return f"DRY_RUN: would record the result of block_ip for {event['src_ip']}"
        if self.recorder is None:
            raise RuntimeError("record_ban is not configured (BAN_DB_HOST is not set)")
        ban = ban_from_result(event, block_result)
        ban_id = self.recorder.save(ban)
        log.info("record_ban %s %s: ban id %s", ban["status"], ban["src_ip"], ban_id)
        return f"ban {ban_id} recorded: {ban['status']} {ban['src_ip']}"