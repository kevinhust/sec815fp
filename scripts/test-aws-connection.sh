#!/bin/bash

# AWS连接测试脚本
# 使用方法：./scripts/test-aws-connection.sh

set -e

echo "🔍 测试AWS连接..."
echo

# 设置AWS凭证（请手动配置您的AWS凭证）
# export AWS_ACCESS_KEY_ID="your_access_key_here"
# export AWS_SECRET_ACCESS_KEY="your_secret_key_here"
export AWS_DEFAULT_REGION="us-east-1"

echo "⚠️  请确保已配置AWS凭证："
echo "   方法1: aws configure"
echo "   方法2: 设置环境变量 AWS_ACCESS_KEY_ID 和 AWS_SECRET_ACCESS_KEY"
echo

echo "📍 当前AWS区域: $AWS_DEFAULT_REGION"
echo

# 检查AWS CLI是否已安装
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI未安装，请先安装："
    echo "macOS: brew install awscli"
    echo "Windows: 下载安装包或使用 pip install awscli"
    echo "Linux: sudo apt-get install awscli 或 pip install awscli"
    exit 1
fi

echo "🔐 验证AWS身份..."
if aws sts get-caller-identity; then
    echo "✅ AWS身份验证成功"
else
    echo "❌ AWS身份验证失败，请检查凭证"
    exit 1
fi

echo
echo "🌐 检查可用区..."
aws ec2 describe-availability-zones --query 'AvailabilityZones[].ZoneName' --output table

echo
echo "🏗️  检查现有EKS集群..."
existing_clusters=$(aws eks list-clusters --query 'clusters' --output text)
if [ -n "$existing_clusters" ]; then
    echo "✅ 发现现有EKS集群："
    aws eks list-clusters --query 'clusters' --output table
else
    echo "ℹ️  未发现现有EKS集群（这是正常的，将通过GitHub Actions创建）"
fi

echo
echo "🔍 检查VPC配置..."
vpc_count=$(aws ec2 describe-vpcs --query 'length(Vpcs)')
echo "✅ 发现 $vpc_count 个VPC"

echo
echo "💰 检查服务限制（重要）..."
echo "📊 当前区域EKS配额："
# 注意：这需要Support API访问权限，可能会失败
aws service-quotas get-service-quota --service-code eks --quota-code L-1194D53C --query 'Quota.Value' --output text 2>/dev/null || echo "⚠️  无法获取EKS配额信息（需要Support权限）"

echo
echo "🎯 建议的下一步操作："
echo "1. ✅ AWS连接测试通过"
echo "2. 🚀 运行 ./scripts/setup-github-secrets.sh 设置所有Secrets"
echo "3. 📋 运行 ./scripts/verify-secrets.sh 验证配置"
echo "4. 🏗️  通过GitHub Actions触发基础设施部署"
echo "5. 📊 监控部署进度和日志"

echo
echo "⚠️  重要提醒："
echo "- EKS集群部署大约需要10-15分钟"
echo "- 确保AWS账户有足够的权限创建EKS、EC2、VPC等资源"
echo "- 监控AWS成本，EKS集群会产生费用"
echo "- 完成实验后及时清理资源以避免不必要的费用"
