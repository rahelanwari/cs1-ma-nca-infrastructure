"""Response actions of the SOAR.

A1 log_incident: store the incident as a JSON file in an S3 bucket.
A2 notify:       send an e-mail via an SNS topic.

In DRY_RUN mode (local testing) the actions only write a log line.
"""

import json
import logging

log = logging.getLogger("soar")


class Actions:
    def __init__(self, s3=None, sns=None, bucket="", topic_arn="", dry_run=False):
        self.s3 = s3
        self.sns = sns
        self.bucket = bucket
        self.topic_arn = topic_arn
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