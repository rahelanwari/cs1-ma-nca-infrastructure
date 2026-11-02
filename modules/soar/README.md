# SOAR module (Case Study 2)

Terraform code for the SOAR platform (filled in Phase 2):
ECS Fargate service (2 tasks), S3 bucket for incidents,
SNS topic for notifications, IAM task role and security group.
Action A3 block_ip: SSH key in Secrets Manager (ban script on mgmt01).
Action A4 record_ban: database settings, the soar_writer password from
Secrets Manager and a database rule for port 3306 from the SOAR.