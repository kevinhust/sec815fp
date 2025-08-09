#!/bin/bash
set -e

# Variables
CLUSTER_NAME="${cluster_name}"
CLIENT_NAME="${client_name}"

# Update system and install packages
yum update -y
yum install -y wget curl rsyslog chrony awscli firewalld fail2ban

# Install client-specific packages
if [[ "$CLIENT_NAME" == *"client-1"* ]]; then
    yum install -y nginx
elif [[ "$CLIENT_NAME" == *"client-2"* ]]; then
    yum install -y mysql-server
fi

# Configure hostname and timezone
hostnamectl set-hostname "$CLUSTER_NAME-$CLIENT_NAME"
timedatectl set-timezone UTC
systemctl start chronyd && systemctl enable chronyd

# Configure rsyslog to forward logs to SIEM server
SIEM_SERVER_IP=$(aws ec2 describe-instances --region us-east-1 --filters "Name=tag:Role,Values=SIEM-Server" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text 2>/dev/null || echo "10.0.1.100")

cat >> /etc/rsyslog.conf << EOF
# Forward logs to SIEM server
*.* @@$SIEM_SERVER_IP:514
EOF

systemctl restart rsyslog && systemctl enable rsyslog

# Configure services based on client type
if [[ "$CLIENT_NAME" == *"client-1"* ]]; then
    # Configure Nginx
    systemctl start nginx && systemctl enable nginx
    
    cat > /usr/share/nginx/html/index.html << 'EOF'
<!DOCTYPE html>
<html><head><title>SIEM Test Web Server</title></head>
<body><h1>🌐 SIEM Test Web Server</h1><p>This server generates logs for SIEM monitoring.</p></body></html>
EOF

    cat > /etc/nginx/conf.d/logging.conf << 'EOF'
log_format detailed '$remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent';
access_log /var/log/nginx/access.log detailed;
error_log /var/log/nginx/error.log warn;
EOF

    systemctl reload nginx

elif [[ "$CLIENT_NAME" == *"client-2"* ]]; then
    # Configure MySQL
    systemctl start mysqld && systemctl enable mysqld
    
    cat >> /etc/my.cnf << 'EOF'
[mysqld]
general_log = 1
general_log_file = /var/log/mysqld-general.log
log_error = /var/log/mysqld-error.log
EOF

    systemctl restart mysqld
fi

# Install CloudWatch agent
wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U ./amazon-cloudwatch-agent.rpm

# Configure CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
    "agent": {"metrics_collection_interval": 60, "run_as_user": "cwagent"},
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {"file_path": "/var/log/messages", "log_group_name": "$CLUSTER_NAME-$CLIENT_NAME-messages", "log_stream_name": "{instance_id}", "retention_in_days": 7},
                    {"file_path": "/var/log/secure", "log_group_name": "$CLUSTER_NAME-$CLIENT_NAME-secure", "log_stream_name": "{instance_id}", "retention_in_days": 30}
                ]
            }
        }
    },
    "metrics": {
        "namespace": "SIEM/Client",
        "metrics_collected": {
            "cpu": {"measurement": ["cpu_usage_idle", "cpu_usage_user"], "metrics_collection_interval": 60},
            "mem": {"measurement": ["mem_used_percent"], "metrics_collection_interval": 60}
        }
    }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# Configure fail2ban
systemctl start fail2ban && systemctl enable fail2ban
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
[sshd]
enabled = true
port = ssh
logpath = /var/log/secure
EOF
systemctl restart fail2ban

# Configure firewall
systemctl start firewalld && systemctl enable firewalld
if [[ "$CLIENT_NAME" == *"client-1"* ]]; then
    firewall-cmd --permanent --add-port=80/tcp --add-port=443/tcp
elif [[ "$CLIENT_NAME" == *"client-2"* ]]; then
    firewall-cmd --permanent --add-port=3306/tcp
fi
firewall-cmd --permanent --add-port=22/tcp
firewall-cmd --reload

# Create test users and scripts
useradd -m testuser1 && echo "testuser1:TestUser123!" | chpasswd
useradd -m testuser2 && echo "testuser2:TestUser123!" | chpasswd
mkdir -p /opt/siem/generators

# Create log generation scripts
cat > /opt/siem/generators/auth-test.sh << 'EOF'
#!/bin/bash
for i in {1..3}; do
    echo "$(date): Simulated login for testuser1" >> /var/log/auth-simulation.log
    sleep 1
done
logger "SIEM Test: Authentication simulation completed"
EOF

cat > /opt/siem/generators/system-events.sh << 'EOF'
#!/bin/bash
logger "SIEM Test: CPU $(top -bn1 | grep Cpu | awk '{print $2}'), Memory $(free | awk 'NR==2{printf "%.1f%%", $3*100/$2}')"
logger "SIEM Test: Network connections: $(netstat -tn | grep ESTABLISHED | wc -l) active"
EOF

chmod +x /opt/siem/generators/*.sh

# Client-specific scripts
if [[ "$CLIENT_NAME" == *"client-1"* ]]; then
    cat > /opt/siem/generators/web-activity.sh << 'EOF'
#!/bin/bash
curl -s "http://localhost/" > /dev/null
curl -s "http://localhost/admin" > /dev/null
logger "SIEM Test: Web activity simulation completed"
EOF
    chmod +x /opt/siem/generators/web-activity.sh
    echo "*/15 * * * * root /opt/siem/generators/web-activity.sh" >> /etc/cron.d/siem-log-generation
elif [[ "$CLIENT_NAME" == *"client-2"* ]]; then
    cat > /opt/siem/generators/db-activity.sh << 'EOF'
#!/bin/bash
mysql -e "SHOW DATABASES;" 2>/dev/null || true
logger "SIEM Test: Database activity simulation completed"
EOF
    chmod +x /opt/siem/generators/db-activity.sh
    echo "*/20 * * * * root /opt/siem/generators/db-activity.sh" >> /etc/cron.d/siem-log-generation
fi

# Set up cron jobs
cat > /etc/cron.d/siem-log-generation << 'EOF'
*/10 * * * * root /opt/siem/generators/auth-test.sh
*/5 * * * * root /opt/siem/generators/system-events.sh
EOF

# Create status script
cat > /opt/siem/status.sh << 'EOF'
#!/bin/bash
echo "🖥️  SIEM Client Status - $(hostname)"
echo "Uptime: $(uptime -p)"
echo "Memory: $(free -h | awk 'NR==2{printf "%.1f%%", $3*100/$2}')"
echo "Services: rsyslog=$(systemctl is-active rsyslog) fail2ban=$(systemctl is-active fail2ban)"
EOF

chmod +x /opt/siem/status.sh

# Create welcome message
cat > /etc/motd << EOF
🖥️  SIEM Client - $CLIENT_NAME ($CLUSTER_NAME)
Commands: /opt/siem/status.sh
⚠️  Generates test logs for SIEM analysis.
EOF

# Final configuration
echo 'PATH=$PATH:/opt/siem' >> /etc/profile
yum install -y yum-cron
systemctl enable yum-cron && systemctl start yum-cron

# Signal completion
touch /tmp/siem-client-ready
echo "SIEM Client ($CLIENT_NAME) initialization completed: $(date)"
