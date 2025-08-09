#!/bin/bash

# GitHub Secrets 验证脚本
# 使用方法：./scripts/verify-secrets.sh

set -e

echo "🔍 验证GitHub Secrets配置..."
echo

# 检查GitHub CLI是否已安装
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI未安装"
    exit 1
fi

# 检查是否已登录
if ! gh auth status &> /dev/null; then
    echo "❌ 请先登录GitHub CLI"
    exit 1
fi

echo "📋 当前配置的Secrets："
gh secret list

echo
echo "🔍 检查必需的Secrets..."

# 定义必需的Secrets
required_secrets=(
    "AWS_ACCESS_KEY_ID"
    "AWS_SECRET_ACCESS_KEY" 
    "AWS_DEFAULT_REGION"
    "EKS_CLUSTER_NAME"
    "EKS_ROLE_ARN"
    "SPLUNK_LICENSE_TYPE"
    "SPLUNK_ADMIN_PASSWORD"
)

# 定义可选的Secrets
optional_secrets=(
    "SPLUNK_HEC_TOKEN"
    "AWS_SES_SMTP_USERNAME"
    "AWS_SES_SMTP_PASSWORD"
    "NOTIFICATION_EMAIL"
    "SLACK_WEBHOOK_URL"
    "SLACK_CHANNEL"
)

# 检查必需的Secrets
missing_required=()
for secret in "${required_secrets[@]}"; do
    if gh secret list | grep -q "^$secret"; then
        echo "✅ $secret - 已配置"
    else
        echo "❌ $secret - 未配置"
        missing_required+=("$secret")
    fi
done

echo
echo "🔍 检查可选的Secrets..."

# 检查可选的Secrets
missing_optional=()
for secret in "${optional_secrets[@]}"; do
    if gh secret list | grep -q "^$secret"; then
        echo "✅ $secret - 已配置"
    else
        echo "⚠️  $secret - 未配置（可选）"
        missing_optional+=("$secret")
    fi
done

echo
echo "📊 配置总结："

if [ ${#missing_required[@]} -eq 0 ]; then
    echo "✅ 所有必需的Secrets都已配置"
else
    echo "❌ 缺少必需的Secrets:"
    for secret in "${missing_required[@]}"; do
        echo "   - $secret"
    done
fi

if [ ${#missing_optional[@]} -gt 0 ]; then
    echo "⚠️  未配置的可选Secrets:"
    for secret in "${missing_optional[@]}"; do
        echo "   - $secret"
    done
fi

echo
if [ ${#missing_required[@]} -eq 0 ]; then
    echo "🎉 配置验证通过！可以开始部署SIEM项目。"
    echo
    echo "🚀 下一步操作："
    echo "   1. 确认AWS账户ID是否正确（在EKS_ROLE_ARN中）"
    echo "   2. 运行GitHub Actions工作流开始部署"
    echo "   3. 监控部署日志确保成功"
else
    echo "⚠️  请先配置缺少的必需Secrets，然后重新运行验证。"
    echo
    echo "💡 快速配置方法："
    echo "   ./scripts/setup-github-secrets.sh"
fi
