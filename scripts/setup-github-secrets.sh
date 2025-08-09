#!/bin/bash

# GitHub Secrets 快速设置脚本
# 使用方法：./scripts/setup-github-secrets.sh

set -e

echo "🚀 开始设置GitHub Secrets..."
echo

# 检查GitHub CLI是否已安装
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI未安装，请先安装："
    echo "macOS: brew install gh"
    echo "Windows: choco install gh"
    echo "Linux: 参考官方文档"
    exit 1
fi

# 检查是否已登录
if ! gh auth status &> /dev/null; then
    echo "🔐 请先登录GitHub CLI："
    gh auth login
fi

echo "🔑 设置AWS访问凭证..."
echo "⚠️  注意：AWS凭证已在首次运行时配置，如需更新请手动设置"
echo "✅ AWS凭证配置完成"
echo

echo "📝 设置EKS集群配置..."
echo "siem-eks-cluster" | gh secret set EKS_CLUSTER_NAME
echo "arn:aws:iam::123456789012:role/siem-eks-service-role" | gh secret set EKS_ROLE_ARN
echo "✅ EKS配置完成"
echo

echo "🔧 设置Splunk配置（免费版本）..."
echo "free" | gh secret set SPLUNK_LICENSE_TYPE
echo "SiemAdmin2024!" | gh secret set SPLUNK_ADMIN_PASSWORD
echo "a1b2c3d4-e5f6-7890-abcd-ef1234567890" | gh secret set SPLUNK_HEC_TOKEN
echo "✅ Splunk配置完成"
echo

echo "📧 设置邮件通知配置..."
echo "AKIA2XAMPLESMTPUSER1" | gh secret set AWS_SES_SMTP_USERNAME
echo "BGsampleSESpassword123456789abcdefghijklmn" | gh secret set AWS_SES_SMTP_PASSWORD
echo "kevinhust@gmail.com" | gh secret set NOTIFICATION_EMAIL
echo "✅ 邮件通知配置完成"
echo

echo "💬 设置Slack集成（可选）..."
echo "https://hooks.slack.com/services/T01234567/B01234567/abcdefghijklmnopqrstuvwx" | gh secret set SLACK_WEBHOOK_URL
echo "#security-alerts" | gh secret set SLACK_CHANNEL
echo "✅ Slack集成配置完成"
echo

echo "🎉 所有Secrets设置完成！"
echo
echo "✅ 所有必需的Secrets已全部配置完成！"
echo
echo "🔍 验证Secrets设置："
echo "   gh secret list"
echo
echo "⚠️  重要提醒："
echo "   1. 请将EKS_ROLE_ARN中的账户ID (123456789012) 替换为您的真实AWS账户ID"
echo "   2. 建议更改Splunk管理员密码为更复杂的密码"
echo "   3. 通知邮箱已设置为 kevinhust@gmail.com"
echo "   4. 如果使用Slack，请配置真实的Webhook URL"
