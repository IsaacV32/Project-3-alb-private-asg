#!/bin/bash
set -euxo pipefail

dnf update -y
dnf install -y nginx

INSTANCE_ID="$(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
AZ="$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)"
HOSTNAME="$(hostname)"

cat > /usr/share/nginx/html/index.html <<EOF
<html>
  <body style="font-family: Arial;">
    <h1>Project 3 — Private ALB + ASG (SSM-only)</h1>
    <p><b>Hostname:</b> ${HOSTNAME}</p>
    <p><b>Instance ID:</b> ${INSTANCE_ID}</p>
    <p><b>Availability Zone:</b> ${AZ}</p>
    <p><b>Time:</b> $(date)</p>
  </body>
</html>
EOF

cat > /usr/share/nginx/html/health <<EOF
ok
EOF

systemctl enable nginx
systemctl start nginx
