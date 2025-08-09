#!/bin/bash

# SIEM部署监控脚本
# 使用方法：./scripts/monitor-deployment.sh [run_id]

set -e

# 获取最新的运行ID或使用提供的ID
if [ -n "$1" ]; then
    RUN_ID="$1"
else
    RUN_ID=$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId')
fi

echo "🔍 监控GitHub Actions部署..."
echo "📋 运行ID: $RUN_ID"
echo "🌐 GitHub链接: https://github.com/kevinhust/sec815fp/actions/runs/$RUN_ID"
echo

# 监控循环
while true; do
    echo "⏰ $(date '+%Y-%m-%d %H:%M:%S') - 检查部署状态..."
    
    # 获取运行状态
    STATUS=$(gh run view $RUN_ID --json status --jq '.status')
    CONCLUSION=$(gh run view $RUN_ID --json conclusion --jq '.conclusion')
    
    echo "📊 当前状态: $STATUS"
    
    if [ "$STATUS" = "completed" ]; then
        echo
        echo "🎉 部署完成！结果: $CONCLUSION"
        
        if [ "$CONCLUSION" = "success" ]; then
            echo "✅ 部署成功！"
            echo
            echo "🔍 验证部署结果..."
            
            # 检查EKS集群
            echo "📋 EKS集群状态:"
            aws eks describe-cluster --name siem-eks-cluster --region us-east-1 --query 'cluster.status' --output text 2>/dev/null || echo "❌ 无法连接到EKS集群"
            
            # 检查节点
            echo "🖥️  EKS节点状态:"
            aws eks describe-nodegroup --cluster-name siem-eks-cluster --nodegroup-name siem-eks-cluster-nodes --region us-east-1 --query 'nodegroup.status' --output text 2>/dev/null || echo "❌ 无法获取节点状态"
            
            echo
            echo "🚀 下一步操作："
            echo "1. 配置kubectl连接到集群"
            echo "2. 部署Splunk Enterprise"
            echo "3. 配置数据源"
            
        else
            echo "❌ 部署失败！"
            echo "📋 查看详细错误信息:"
            gh run view $RUN_ID --log-failed
        fi
        
        break
    elif [ "$STATUS" = "in_progress" ]; then
        echo "⏳ 部署进行中..."
        
        # 显示各个作业的状态
        echo "📋 作业进度:"
        gh run view $RUN_ID --json jobs --jq '.jobs[] | "  \(.name): \(.status) (\(.conclusion // "running"))"'
        
    else
        echo "⚠️  未知状态: $STATUS"
    fi
    
    echo "----------------------------------------"
    echo "⏰ 下次检查: 60秒后..."
    echo
    
    sleep 60
done

echo
echo "🎯 监控完成！"
