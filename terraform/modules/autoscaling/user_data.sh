#!/bin/bash
set -euo pipefail
set -x

# write the templated CloudWatch config (templatefile injects the JSON with PLACEHOLDER_HOSTNAME)
cat > /tmp/cw-config.json <<'CWC'
${cw_config}
CWC

# Replace placeholder token with actual short hostname
hostval="$(hostname -s)"
sed -i "s/PLACEHOLDER_HOSTNAME/${hostval}/g" /tmp/cw-config.json || true

# Update and install packages (works for yum/dnf)
if command -v yum >/dev/null 2>&1; then
  yum update -y || true
  yum install -y nginx amazon-cloudwatch-agent || true
elif command -v dnf >/dev/null 2>&1; then
  dnf upgrade -y || true
  dnf install -y nginx amazon-cloudwatch-agent || true
fi

# Ensure SSM agent and nginx are enabled
if command -v systemctl >/dev/null 2>&1; then
  systemctl enable --now amazon-ssm-agent || true
  systemctl enable --now nginx || true
fi

# awslogs fallback config (only useful if awslogs is installed)
mkdir -p /etc/awslogs/config || true
cat > /etc/awslogs/config/var-log-messages.conf <<'AWSLOG'
[/var/log/messages]
file = /var/log/messages
log_group_name = /ec2/${HOSTNAME}/messages
log_stream_name = {instance_id}
datetime_format = %b %d %H:%M:%S
AWSLOG

# Restart awslogs if the service exists
if systemctl list-units --type=service --all | grep -q awslogs; then
  systemctl restart awslogsd || systemctl restart awslogs || true
fi

# Start cloudwatch agent using supplied config if the ctl binary exists
if [ -x /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl ]; then
  /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/tmp/cw-config.json -s || true
fi

# Ensure nginx listens on 0.0.0.0:80 by placing a minimal server block in conf.d
cat > /etc/nginx/conf.d/00-http.conf <<'NGINX'
server {
    listen 80 default_server;
    server_name _;
    location / { return 200 'ok'; }
}
NGINX

# Restart nginx to apply configuration
systemctl restart nginx || true