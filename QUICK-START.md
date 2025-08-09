# 🚀 SIEM项目快速启动指南

## ✅ 当前状态
所有必需的配置已完成！您现在可以开始部署SIEM系统。

### 📋 已配置的信息
- ✅ AWS访问凭证：已配置到GitHub Secrets (us-east-1)
- ✅ 通知邮箱：kevinhust@gmail.com
- ✅ Splunk配置：免费版本
- ✅ GitHub Actions工作流：已准备就绪

## 🎯 下一步操作（3步完成部署）

### 步骤1：设置GitHub Secrets
```bash
# 一键设置所有Secrets
./scripts/setup-github-secrets.sh

# 验证配置
./scripts/verify-secrets.sh
```

### 步骤2：测试AWS连接（可选）
```bash
# 本地测试AWS连接
./scripts/test-aws-connection.sh
```

### 步骤3：触发GitHub Actions部署
1. 将代码推送到GitHub仓库
2. 在GitHub Actions中手动触发"Deploy SIEM to AWS EKS"工作流
3. 监控部署进度

## 📊 部署时间预估
- **基础设施部署**：10-15分钟（EKS集群创建）
- **Splunk部署**：5-10分钟
- **数据源配置**：2-5分钟
- **总计**：约20-30分钟

## 🔍 验证部署成功

### 1. 检查EKS集群
```bash
aws eks describe-cluster --name siem-eks-cluster --region us-east-1
```

### 2. 访问Splunk Web界面
- URL：通过GitHub Actions日志获取LoadBalancer地址
- 用户名：`admin`
- 密码：`SiemAdmin2024!`

### 3. 验证数据收集
在Splunk中搜索：
```splunk
index=cloudtrail | head 10
index=cloudwatch | head 10
```

## 📧 告警配置
所有安全告警将发送到：`kevinhust@gmail.com`

## 💰 成本估算（每月）
- **EKS控制平面**：~$73
- **工作节点EC2**：~$50-150（取决于实例类型）
- **存储和网络**：~$20-50
- **总计**：约$150-300/月

⚠️ **重要**：完成实验后请及时清理资源！

## 🛟 故障排除

### 常见问题
1. **GitHub Actions失败**
   - 检查Secrets是否正确配置
   - 验证AWS权限
   - 查看详细错误日志

2. **EKS集群创建失败**
   - 检查区域配额限制
   - 验证IAM权限
   - 确认VPC配置

3. **Splunk无法访问**
   - 检查安全组配置
   - 验证LoadBalancer状态
   - 查看Pod日志

### 获取帮助
- 查看GitHub Actions运行日志
- 检查AWS CloudTrail事件
- 运行 `kubectl get pods -n splunk-enterprise`

## 📚 相关文档
- [GitHub Secrets配置指导](.github/secrets-setup-guide.md)
- [Splunk免费版使用指南](docs/splunk-free-guide.md)
- [任务管理](.taskmaster/tasks/tasks.json)

## 🎉 开始部署！

现在您可以开始部署您的SIEM系统了：

```bash
# 1. 设置所有Secrets
./scripts/setup-github-secrets.sh

# 2. 推送到GitHub并触发部署
git add .
git commit -m "feat: 初始化SIEM项目配置"
git push origin main
```

祝您部署顺利！🚀
