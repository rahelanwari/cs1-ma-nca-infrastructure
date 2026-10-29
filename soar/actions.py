"""Response actions of the SOAR.

A1 log_incident: store the incident as a JSON file in an S3 bucket.
A2 notify:       send an e-mail via an SNS topic.
A3 block_ip:     ban the source IP of the attack on ws01 for 5 minutes.
                 The SOAR asks mgmt01 over SSH (through the VPN); its key
                 may only run the ban script there.

In DRY_RUN mode (local testing) the actions only write a log line.
"""

import base64
import io
import ipaddress
import json
import logging

log = logging.getLogger("soar")

# block_ip never bans these addresses: the management segment (mgmt01, Ansible),
# the firewall, ws01 itself and loopback. The ban script on mgmt01 checks this again.
PROTECTED = [
    ipaddress.ip_network("192.168.20.0/24"),
    ipaddress.ip_network("192.168.10.1/32"),
    ipaddress.ip_network("192.168.10.10/32"),
    ipaddress.ip_network("127.0.0.0/8"),
]

# block_ip can only ban on ws01: that is where fail2ban runs
BLOCK_HOSTS = {"ws01"}


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


class Actions:
    def __init__(self, s3=None, sns=None, bucket="", topic_arn="", blocker=None, dry_run=False):
        self.s3 = s3
        self.sns = sns
        self.bucket = bucket
        self.topic_arn = topic_arn
        self.blocker = blocker
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
        """A3 - ban the source IP of the attack on ws01 for 5 minutes (via mgmt01)."""
        ip = event["src_ip"]
        if not ip:
            raise ValueError("the alert has no src_ip, nothing to block")
        if event["host"] not in BLOCK_HOSTS:
            raise ValueError(f"block_ip only works on {sorted(BLOCK_HOSTS)}, not on {event['host']}")
        address = ipaddress.IPv4Address(ip)  # ValueError for anything that is not one IPv4 address
        if any(address in network for network in PROTECTED):
            raise ValueError(f"{ip} is on the whitelist, not blocked")

        if self.dry_run:
            log.info("DRY_RUN block_ip %s on %s", ip, event["host"])
            return f"DRY_RUN: would ban {ip} on {event['host']}"
        if self.blocker is None:
            raise RuntimeError("block_ip is not configured (BLOCK_HOST is not set)")
        result = self.blocker.ban(str(address))
        log.info("block_ip %s: %s", ip, result)
        return result