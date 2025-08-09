#!/bin/bash

# SIEM Server Initialization Script
# This script sets up a SIEM monitoring server for log collection and analysis

set -e

# Variables
CLUSTER_NAME="${cluster_name}"
LOG_FILE="/var/log/siem-server-init.log"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

log "🚀 Starting SIEM Server initialization..."

# Update system
log "📦 Updating system packages..."
yum update -y

# Install required packages
log "📦 Installing required packages..."
yum install -y \
    wget \
    curl \
    unzip \
    git \
    htop \
    tcpdump \
    wireshark-cli \
    rsyslog \
    logrotate \
    chrony \
    awscli

# Configure hostname
log "🏷️  Setting hostname..."
hostnamectl set-hostname "$CLUSTER_NAME-siem-server"
echo "127.0.0.1 $CLUSTER_NAME-siem-server" >> /etc/hosts

# Configure timezone
log "🕐 Setting timezone..."
timedatectl set-timezone UTC

# Start and enable chronyd for time synchronization
log "⏰ Configuring time synchronization..."
systemctl start chronyd
systemctl enable chronyd

# Configure rsyslog for centralized logging
log "📋 Configuring rsyslog..."
cat >> /etc/rsyslog.conf << EOF

# SIEM Server Configuration
# Enable UDP syslog reception
\$ModLoad imudp
\$UDPServerRun 514
\$UDPServerAddress 0.0.0.0

# Enable TCP syslog reception
\$ModLoad imtcp
\$InputTCPServerRun 514

# Template for log file naming
\$template RemoteLogs,"/var/log/remote/%HOSTNAME%/%PROGRAMNAME%.log"
*.* ?RemoteLogs
& stop
EOF

# Create remote logs directory
mkdir -p /var/log/remote

# Configure logrotate for remote logs
cat > /etc/logrotate.d/remote-logs << EOF
/var/log/remote/*/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 root root
    sharedscripts
    postrotate
        /bin/kill -HUP \`cat /var/run/rsyslogd.pid 2> /dev/null\` 2> /dev/null || true
    endscript
}
EOF

# Restart rsyslog
systemctl restart rsyslog
systemctl enable rsyslog

# Install AWS CloudWatch agent
log "☁️  Installing AWS CloudWatch agent..."
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U ./amazon-cloudwatch-agent.rpm

# Configure CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
    "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "cwagent"
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/messages",
                        "log_group_name": "$CLUSTER_NAME-siem-server-messages",
                        "log_stream_name": "{instance_id}",
                        "retention_in_days": 7
                    },
                    {
                        "file_path": "/var/log/secure",
                        "log_group_name": "$CLUSTER_NAME-siem-server-secure",
                        "log_stream_name": "{instance_id}",
                        "retention_in_days": 30
                    },
                    {
                        "file_path": "/var/log/remote/*/*",
                        "log_group_name": "$CLUSTER_NAME-siem-remote-logs",
                        "log_stream_name": "{instance_id}",
                        "retention_in_days": 30
                    }
                ]
            }
        }
    },
    "metrics": {
        "namespace": "SIEM/Server",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_iowait",
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": [
                    "used_percent"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "diskio": {
                "measurement": [
                    "io_time"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 60
            }
        }
    }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -s \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# Configure firewall
log "🔥 Configuring firewall..."
systemctl start firewalld
systemctl enable firewalld

# Open necessary ports
firewall-cmd --permanent --add-port=514/udp  # Syslog UDP
firewall-cmd --permanent --add-port=514/tcp  # Syslog TCP
firewall-cmd --permanent --add-port=22/tcp   # SSH
firewall-cmd --reload

# Create SIEM user
log "👤 Creating SIEM user..."
useradd -m -s /bin/bash siemuser
echo "siemuser:SiemUser123!" | chpasswd
usermod -aG wheel siemuser

# Create monitoring scripts
log "📊 Creating monitoring scripts..."
mkdir -p /opt/siem/scripts

# Security monitoring script
cat > /opt/siem/scripts/security-monitor.sh << 'EOF'
#!/bin/bash

# Security monitoring script
ALERT_EMAIL="kevinhust@gmail.com"
LOG_FILE="/var/log/security-alerts.log"

# Function to send alert
send_alert() {
    local message="$1"
    echo "$(date): SECURITY ALERT - $message" >> $LOG_FILE
    
    # Send to CloudWatch (if available)
    aws logs put-log-events \
        --log-group-name "$CLUSTER_NAME-security-alerts" \
        --log-stream-name "$(hostname)" \
        --log-events timestamp=$(date +%s000),message="$message" 2>/dev/null || true
}

# Check for failed SSH attempts
failed_ssh=$(grep "Failed password" /var/log/secure | grep "$(date '+%b %d')" | wc -l)
if [ $failed_ssh -gt 10 ]; then
    send_alert "High number of failed SSH attempts: $failed_ssh"
fi

# Check for root login attempts
root_attempts=$(grep "root" /var/log/secure | grep "$(date '+%b %d')" | wc -l)
if [ $root_attempts -gt 5 ]; then
    send_alert "Root login attempts detected: $root_attempts"
fi

# Check disk usage
disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ $disk_usage -gt 80 ]; then
    send_alert "High disk usage detected: $disk_usage%"
fi

# Check memory usage
mem_usage=$(free | awk 'FNR==2{printf "%.0f", $3/($3+$4)*100}')
if [ $mem_usage -gt 90 ]; then
    send_alert "High memory usage detected: $mem_usage%"
fi
EOF

chmod +x /opt/siem/scripts/security-monitor.sh

# Create cron job for security monitoring
cat > /etc/cron.d/security-monitor << EOF
# Security monitoring every 5 minutes
*/5 * * * * root /opt/siem/scripts/security-monitor.sh
EOF

# Create status script
cat > /opt/siem/scripts/status.sh << 'EOF'
#!/bin/bash

echo "🖥️  SIEM Server Status"
echo "===================="
echo "Hostname: $(hostname)"
echo "Uptime: $(uptime -p)"
echo "Load: $(uptime | awk -F'load average:' '{print $2}')"
echo "Memory: $(free -h | awk 'NR==2{printf "%.1f/%.1f GB (%.1f%%)", $3/1024/1024, $2/1024/1024, $3*100/$2}')"
echo "Disk: $(df -h / | awk 'NR==2{printf "%s/%s (%s)", $3, $2, $5}')"
echo ""
echo "📋 Services Status:"
echo "- rsyslog: $(systemctl is-active rsyslog)"
echo "- firewalld: $(systemctl is-active firewalld)"
echo "- chronyd: $(systemctl is-active chronyd)"
echo "- cloudwatch-agent: $(systemctl is-active amazon-cloudwatch-agent)"
echo ""
echo "📊 Network Connections:"
netstat -tulpn | grep ":514"
echo ""
echo "📈 Recent Security Events:"
tail -5 /var/log/security-alerts.log 2>/dev/null || echo "No security alerts yet"
EOF

chmod +x /opt/siem/scripts/status.sh

# Create log analysis script
cat > /opt/siem/scripts/analyze-logs.sh << 'EOF'
#!/bin/bash

echo "📊 Log Analysis Summary (Last 24 hours)"
echo "======================================="

# SSH login analysis
echo "🔐 SSH Login Summary:"
echo "- Successful logins: $(grep "Accepted password\|Accepted publickey" /var/log/secure | grep "$(date '+%b %d')" | wc -l)"
echo "- Failed logins: $(grep "Failed password" /var/log/secure | grep "$(date '+%b %d')" | wc -l)"

# Top failed login attempts by IP
echo ""
echo "🚨 Top Failed Login IPs:"
grep "Failed password" /var/log/secure | grep "$(date '+%b %d')" | \
    awk '{print $(NF-3)}' | sort | uniq -c | sort -nr | head -5

# System events
echo ""
echo "🖥️  System Events:"
echo "- System starts: $(grep "systemd\[1\].*Started" /var/log/messages | grep "$(date '+%b %d')" | wc -l)"
echo "- Kernel messages: $(grep "kernel:" /var/log/messages | grep "$(date '+%b %d')" | wc -l)"

# Remote log summary
if [ -d "/var/log/remote" ]; then
    echo ""
    echo "🌐 Remote Logs:"
    find /var/log/remote -name "*.log" -newermt "1 day ago" | wc -l | xargs echo "- Active remote hosts:"
fi
EOF

chmod +x /opt/siem/scripts/analyze-logs.sh

# Add SIEM scripts to PATH
echo 'export PATH=$PATH:/opt/siem/scripts' >> /etc/profile

# Create welcome message
cat > /etc/motd << EOF

🛡️  SIEM Server - $CLUSTER_NAME
================================

This server is configured for Security Information and Event Management (SIEM).

📊 Available Commands:
- status.sh          : Show server status
- analyze-logs.sh    : Analyze security logs
- security-monitor.sh: Run security checks

📁 Important Directories:
- /var/log/remote    : Remote syslog messages
- /var/log/secure    : Authentication logs
- /opt/siem/scripts  : SIEM management scripts

📋 Services:
- rsyslog (port 514) : Central log collection
- CloudWatch Agent   : AWS log forwarding
- Security Monitor   : Automated threat detection

⚠️  This system is monitored. All activities are logged.

EOF

# Final system configuration
log "🔧 Final system configuration..."

# Enable automatic security updates
yum install -y yum-cron
systemctl enable yum-cron
systemctl start yum-cron

# Set up log retention
echo "rotate 30" >> /etc/logrotate.conf
echo "daily" >> /etc/logrotate.conf
echo "compress" >> /etc/logrotate.conf

log "✅ SIEM Server initialization completed successfully!"
log "🌐 Server IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
log "🔗 SSH Command: ssh -i siem-key.pem ec2-user@$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"

# Signal completion
touch /tmp/siem-server-ready
