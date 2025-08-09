#!/bin/bash
set -e

# Variables
CLUSTER_NAME="${cluster_name}"

# Update system and install packages
yum update -y
yum install -y wget curl rsyslog chrony awscli firewalld

# Configure hostname and timezone
hostnamectl set-hostname "$CLUSTER_NAME-siem-server"
timedatectl set-timezone UTC
systemctl start chronyd && systemctl enable chronyd

# Configure rsyslog for centralized logging
cat >> /etc/rsyslog.conf << 'EOF'
# SIEM Server Configuration
$ModLoad imudp
$UDPServerRun 514
$ModLoad imtcp
$InputTCPServerRun 514
$template RemoteLogs,"/var/log/remote/%HOSTNAME%/%PROGRAMNAME%.log"
*.* ?RemoteLogs
& stop
EOF

mkdir -p /var/log/remote
systemctl restart rsyslog && systemctl enable rsyslog

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
                    {"file_path": "/var/log/messages", "log_group_name": "$CLUSTER_NAME-siem-server-messages", "log_stream_name": "{instance_id}", "retention_in_days": 7},
                    {"file_path": "/var/log/secure", "log_group_name": "$CLUSTER_NAME-siem-server-secure", "log_stream_name": "{instance_id}", "retention_in_days": 30}
                ]
            }
        }
    },
    "metrics": {
        "namespace": "SIEM/Server",
        "metrics_collected": {
            "cpu": {"measurement": ["cpu_usage_idle", "cpu_usage_user"], "metrics_collection_interval": 60},
            "mem": {"measurement": ["mem_used_percent"], "metrics_collection_interval": 60}
        }
    }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# Configure firewall
systemctl start firewalld && systemctl enable firewalld
firewall-cmd --permanent --add-port=514/udp --add-port=514/tcp --add-port=22/tcp
firewall-cmd --reload

# Create SIEM user and scripts
useradd -m -s /bin/bash siemuser
echo "siemuser:SiemUser123!" | chpasswd
mkdir -p /opt/siem/scripts

# Create status script
cat > /opt/siem/scripts/status.sh << 'EOF'
#!/bin/bash
echo "🛡️  SIEM Server Status - $(hostname)"
echo "Uptime: $(uptime -p)"
echo "Memory: $(free -h | awk 'NR==2{printf "%.1f%%", $3*100/$2}')"
echo "Disk: $(df -h / | awk 'NR==2{print $5}')"
echo "Services: rsyslog=$(systemctl is-active rsyslog) firewalld=$(systemctl is-active firewalld)"
echo "Network: $(netstat -tlun | grep :514 | wc -l) syslog listeners active"
EOF

chmod +x /opt/siem/scripts/status.sh

# Create security monitoring script
cat > /opt/siem/scripts/security-monitor.sh << 'EOF'
#!/bin/bash
failed_ssh=$(grep "Failed password" /var/log/secure | grep "$(date '+%b %d')" | wc -l 2>/dev/null || echo 0)
if [ $failed_ssh -gt 10 ]; then
    logger "SIEM ALERT: High SSH failures: $failed_ssh"
fi
disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ $disk_usage -gt 80 ]; then
    logger "SIEM ALERT: High disk usage: $disk_usage%"
fi
EOF

chmod +x /opt/siem/scripts/security-monitor.sh

# Create cron job for monitoring
echo "*/5 * * * * root /opt/siem/scripts/security-monitor.sh" > /etc/cron.d/siem-monitor

# Create welcome message
cat > /etc/motd << EOF
🛡️  SIEM Server - $CLUSTER_NAME
================================
Commands: /opt/siem/scripts/status.sh
Services: rsyslog (port 514), CloudWatch Agent
⚠️  This system is monitored.
EOF

# Final configuration
echo 'PATH=$PATH:/opt/siem/scripts' >> /etc/profile
yum install -y yum-cron
systemctl enable yum-cron && systemctl start yum-cron

# Signal completion
touch /tmp/siem-server-ready
echo "SIEM Server initialization completed: $(date)"
