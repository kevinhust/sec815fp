#!/bin/bash

# SIEM Client Initialization Script
# This script sets up a client machine that generates logs for SIEM monitoring

set -e

# Variables
CLUSTER_NAME="${cluster_name}"
CLIENT_NAME="${client_name}"
LOG_FILE="/var/log/client-init.log"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

log "🚀 Starting SIEM Client ($CLIENT_NAME) initialization..."

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
    nginx \
    mysql \
    rsyslog \
    logrotate \
    chrony \
    awscli \
    fail2ban

# Configure hostname
log "🏷️  Setting hostname..."
hostnamectl set-hostname "$CLUSTER_NAME-$CLIENT_NAME"
echo "127.0.0.1 $CLUSTER_NAME-$CLIENT_NAME" >> /etc/hosts

# Configure timezone
log "🕐 Setting timezone..."
timedatectl set-timezone UTC

# Start and enable chronyd for time synchronization
log "⏰ Configuring time synchronization..."
systemctl start chronyd
systemctl enable chronyd

# Configure rsyslog to forward logs to SIEM server
log "📋 Configuring rsyslog forwarding..."

# Get SIEM server IP (assuming it's the first instance in the same subnet)
SIEM_SERVER_IP=$(aws ec2 describe-instances \
    --region us-east-1 \
    --filters "Name=tag:Role,Values=SIEM-Server" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text 2>/dev/null || echo "10.0.1.100")

cat >> /etc/rsyslog.conf << EOF

# Forward logs to SIEM server
*.* @@$SIEM_SERVER_IP:514
EOF

# Restart rsyslog
systemctl restart rsyslog
systemctl enable rsyslog

# Configure services based on client type
if [[ "$CLIENT_NAME" == *"client-1"* ]]; then
    log "🌐 Configuring as Web Server (client-1)..."
    
    # Configure Nginx
    systemctl start nginx
    systemctl enable nginx
    
    # Create custom web content
    cat > /usr/share/nginx/html/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>SIEM Test Web Server - $CLIENT_NAME</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { background: #007acc; color: white; padding: 20px; }
        .content { padding: 20px; }
        .status { background: #f0f0f0; padding: 10px; margin: 10px 0; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🌐 SIEM Test Web Server</h1>
        <p>Client: $CLIENT_NAME | Cluster: $CLUSTER_NAME</p>
    </div>
    <div class="content">
        <h2>Server Status</h2>
        <div class="status">
            <strong>Server Time:</strong> <span id="time"></span><br>
            <strong>Hostname:</strong> $(hostname)<br>
            <strong>Purpose:</strong> Log generation for SIEM testing
        </div>
        
        <h2>Test Actions</h2>
        <p>This server generates various log events for SIEM monitoring:</p>
        <ul>
            <li>Web access logs</li>
            <li>Authentication attempts</li>
            <li>System events</li>
            <li>Error conditions</li>
        </ul>
    </div>
    
    <script>
        function updateTime() {
            document.getElementById('time').textContent = new Date().toLocaleString();
        }
        updateTime();
        setInterval(updateTime, 1000);
    </script>
</body>
</html>
EOF

    # Configure Nginx logging
    cat > /etc/nginx/conf.d/logging.conf << EOF
log_format detailed '\$remote_addr - \$remote_user [\$time_local] '
                   '"\$request" \$status \$body_bytes_sent '
                   '"\$http_referer" "\$http_user_agent" '
                   'rt=\$request_time ';

access_log /var/log/nginx/access.log detailed;
error_log /var/log/nginx/error.log warn;
EOF

    systemctl reload nginx

elif [[ "$CLIENT_NAME" == *"client-2"* ]]; then
    log "🗄️  Configuring as Database Server (client-2)..."
    
    # Configure MySQL
    systemctl start mysqld
    systemctl enable mysqld
    
    # Get temporary MySQL root password
    MYSQL_TEMP_PASSWORD=$(grep 'temporary password' /var/log/mysqld.log | awk '{print $NF}' | tail -1)
    
    # Set up MySQL (simplified for demo)
    cat > /tmp/mysql_setup.sql << EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY 'SiemTest123!';
CREATE DATABASE siem_test;
CREATE USER 'siem_user'@'localhost' IDENTIFIED BY 'SiemUser123!';
GRANT ALL PRIVILEGES ON siem_test.* TO 'siem_user'@'localhost';
FLUSH PRIVILEGES;
EOF

    # Configure MySQL for enhanced logging
    cat >> /etc/my.cnf << EOF

[mysqld]
# Enhanced logging for SIEM
general_log = 1
general_log_file = /var/log/mysqld-general.log
log_error = /var/log/mysqld-error.log
slow_query_log = 1
slow_query_log_file = /var/log/mysqld-slow.log
long_query_time = 2
log_queries_not_using_indexes = 1
EOF

    systemctl restart mysqld
fi

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
                        "log_group_name": "$CLUSTER_NAME-$CLIENT_NAME-messages",
                        "log_stream_name": "{instance_id}",
                        "retention_in_days": 7
                    },
                    {
                        "file_path": "/var/log/secure",
                        "log_group_name": "$CLUSTER_NAME-$CLIENT_NAME-secure",
                        "log_stream_name": "{instance_id}",
                        "retention_in_days": 30
                    }
                ]
            }
        }
    },
    "metrics": {
        "namespace": "SIEM/Client",
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

# Configure fail2ban for intrusion detection
log "🛡️  Configuring fail2ban..."
systemctl start fail2ban
systemctl enable fail2ban

cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
# Ban hosts for 1 hour
bantime = 3600
# Check for attacks in the last 10 minutes
findtime = 600
# Ban after 3 failures
maxretry = 3

[sshd]
enabled = true
port = ssh
logpath = /var/log/secure
EOF

systemctl restart fail2ban

# Configure firewall
log "🔥 Configuring firewall..."
systemctl start firewalld
systemctl enable firewalld

# Open necessary ports based on client type
if [[ "$CLIENT_NAME" == *"client-1"* ]]; then
    firewall-cmd --permanent --add-port=80/tcp   # HTTP
    firewall-cmd --permanent --add-port=443/tcp  # HTTPS
elif [[ "$CLIENT_NAME" == *"client-2"* ]]; then
    firewall-cmd --permanent --add-port=3306/tcp # MySQL
fi

firewall-cmd --permanent --add-port=22/tcp   # SSH
firewall-cmd --reload

# Create test user accounts
log "👤 Creating test users..."
useradd -m -s /bin/bash testuser1
useradd -m -s /bin/bash testuser2
echo "testuser1:TestUser123!" | chpasswd
echo "testuser2:TestUser123!" | chpasswd

# Create log generation scripts
log "📊 Creating log generation scripts..."
mkdir -p /opt/siem/generators

# Create authentication test script
cat > /opt/siem/generators/auth-test.sh << 'EOF'
#!/bin/bash

# Generate authentication events for SIEM testing

# Simulate successful logins
for i in {1..3}; do
    echo "$(date): Simulated successful login for testuser1" >> /var/log/auth-simulation.log
    sleep 2
done

# Simulate failed login attempts (for testing)
for i in {1..5}; do
    echo "$(date): Failed password for invaliduser from 192.168.1.100 port 22 ssh2" >> /var/log/secure
    sleep 1
done

# Log to syslog
logger -p auth.info "SIEM Test: Authentication simulation completed"
EOF

chmod +x /opt/siem/generators/auth-test.sh

# Create web activity simulator (for client-1)
if [[ "$CLIENT_NAME" == *"client-1"* ]]; then
    cat > /opt/siem/generators/web-activity.sh << 'EOF'
#!/bin/bash

# Generate web activity logs

# Simulate normal web requests
curl -s "http://localhost/" > /dev/null
curl -s "http://localhost/page1" > /dev/null
curl -s "http://localhost/api/status" > /dev/null

# Simulate suspicious requests
curl -s "http://localhost/../../../etc/passwd" > /dev/null
curl -s "http://localhost/admin/login" > /dev/null
curl -s "http://localhost/?id=1' OR '1'='1" > /dev/null

logger -p daemon.info "SIEM Test: Web activity simulation completed"
EOF
    chmod +x /opt/siem/generators/web-activity.sh
fi

# Create database activity simulator (for client-2)
if [[ "$CLIENT_NAME" == *"client-2"* ]]; then
    cat > /opt/siem/generators/db-activity.sh << 'EOF'
#!/bin/bash

# Generate database activity logs
mysql -u root -pSiemTest123! -e "USE siem_test; CREATE TABLE IF NOT EXISTS test_table (id INT, data VARCHAR(100));" 2>/dev/null || true
mysql -u root -pSiemTest123! -e "USE siem_test; INSERT INTO test_table VALUES (1, 'test data');" 2>/dev/null || true
mysql -u root -pSiemTest123! -e "USE siem_test; SELECT * FROM test_table;" 2>/dev/null || true

# Simulate failed login attempt
mysql -u root -pWrongPassword -e "SELECT 1;" 2>/dev/null || true

logger -p daemon.info "SIEM Test: Database activity simulation completed"
EOF
    chmod +x /opt/siem/generators/db-activity.sh
fi

# Create system monitoring script
cat > /opt/siem/generators/system-events.sh << 'EOF'
#!/bin/bash

# Generate system events

# System information
logger -p daemon.info "SIEM Test: System status check - CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)%"
logger -p daemon.info "SIEM Test: System status check - Memory: $(free | awk 'FNR==2{printf "%.1f%%", $3/($3+$4)*100 }')"
logger -p daemon.info "SIEM Test: System status check - Disk: $(df / | awk 'FNR==2{print $5}')"

# Simulate process monitoring
logger -p daemon.notice "SIEM Test: Process monitoring - Total processes: $(ps aux | wc -l)"

# Network monitoring
logger -p daemon.info "SIEM Test: Network connections: $(netstat -tn | grep ESTABLISHED | wc -l) active"
EOF

chmod +x /opt/siem/generators/system-events.sh

# Set up cron jobs for log generation
cat > /etc/cron.d/siem-log-generation << EOF
# Generate authentication logs every 10 minutes
*/10 * * * * root /opt/siem/generators/auth-test.sh

# Generate system events every 5 minutes
*/5 * * * * root /opt/siem/generators/system-events.sh
EOF

# Add client-specific cron jobs
if [[ "$CLIENT_NAME" == *"client-1"* ]]; then
    cat >> /etc/cron.d/siem-log-generation << EOF
# Generate web activity every 15 minutes
*/15 * * * * root /opt/siem/generators/web-activity.sh
EOF
elif [[ "$CLIENT_NAME" == *"client-2"* ]]; then
    cat >> /etc/cron.d/siem-log-generation << EOF
# Generate database activity every 20 minutes
*/20 * * * * root /opt/siem/generators/db-activity.sh
EOF
fi

# Create status script
cat > /opt/siem/status.sh << 'EOF'
#!/bin/bash

echo "🖥️  SIEM Client Status - $CLIENT_NAME"
echo "================================"
echo "Hostname: $(hostname)"
echo "Uptime: $(uptime -p)"
echo "Load: $(uptime | awk -F'load average:' '{print $2}')"
echo "Memory: $(free -h | awk 'NR==2{printf "%.1f/%.1f GB (%.1f%%)", $3/1024/1024, $2/1024/1024, $3*100/$2}')"
echo "Disk: $(df -h / | awk 'NR==2{printf "%s/%s (%s)", $3, $2, $5}')"
echo ""
echo "📋 Services Status:"
echo "- rsyslog: $(systemctl is-active rsyslog)"
echo "- fail2ban: $(systemctl is-active fail2ban)"
echo "- firewalld: $(systemctl is-active firewalld)"
echo "- chronyd: $(systemctl is-active chronyd)"
echo "- cloudwatch-agent: $(systemctl is-active amazon-cloudwatch-agent)"

if [[ "$CLIENT_NAME" == *"client-1"* ]]; then
    echo "- nginx: $(systemctl is-active nginx)"
elif [[ "$CLIENT_NAME" == *"client-2"* ]]; then
    echo "- mysqld: $(systemctl is-active mysqld)"
fi

echo ""
echo "📊 Recent Log Activity:"
echo "- Messages: $(wc -l < /var/log/messages) lines"
echo "- Secure: $(wc -l < /var/log/secure) lines"
echo "- Last rsyslog forward: $(grep rsyslog /var/log/messages | tail -1 | awk '{print $1,$2,$3}' 2>/dev/null || echo 'No recent activity')"
EOF

chmod +x /opt/siem/status.sh

# Create welcome message
cat > /etc/motd << EOF

🖥️  SIEM Client - $CLIENT_NAME ($CLUSTER_NAME)
=====================================

This client is configured to generate logs for SIEM monitoring.

📊 Available Commands:
- /opt/siem/status.sh : Show client status

📁 Log Generation Scripts:
- /opt/siem/generators/auth-test.sh    : Authentication events
- /opt/siem/generators/system-events.sh: System monitoring events
EOF

if [[ "$CLIENT_NAME" == *"client-1"* ]]; then
    cat >> /etc/motd << EOF
- /opt/siem/generators/web-activity.sh : Web server activity

🌐 Web Server: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
EOF
elif [[ "$CLIENT_NAME" == *"client-2"* ]]; then
    cat >> /etc/motd << EOF
- /opt/siem/generators/db-activity.sh  : Database activity

🗄️  Database Server: MySQL running on port 3306
EOF
fi

cat >> /etc/motd << EOF

⚠️  This system generates test logs for SIEM analysis.

EOF

# Final system configuration
log "🔧 Final system configuration..."

# Enable automatic security updates
yum install -y yum-cron
systemctl enable yum-cron
systemctl start yum-cron

log "✅ SIEM Client ($CLIENT_NAME) initialization completed successfully!"
log "🌐 Client IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
log "🔗 SSH Command: ssh -i siem-key.pem ec2-user@$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"

# Signal completion
touch /tmp/siem-client-ready
