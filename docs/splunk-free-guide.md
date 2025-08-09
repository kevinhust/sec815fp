# Splunk Free版本使用指南

本指南将帮助您在SIEM项目中使用Splunk Free版本进行实验和学习。

## Splunk Free版本概述

### 特点
- **完全免费**：无需许可证密钥
- **每日500MB数据限制**：适合小规模测试和学习
- **核心搜索功能**：包含基本的搜索和分析能力
- **仪表板**：可以创建基本的可视化仪表板

### 限制
- **无告警功能**：不能设置自动告警
- **无分布式搜索**：只能单实例运行
- **数据保留限制**：默认保留时间较短
- **无调度搜索**：不能设置定时运行的搜索

## 获取Splunk Free

### 下载选项
1. **Docker镜像**（推荐用于Kubernetes）
   ```bash
   docker pull splunk/splunk:latest
   ```

2. **官网下载**
   - 访问：https://www.splunk.com/en_us/download/splunk-enterprise.html
   - 选择"Free Splunk"选项
   - 无需注册即可下载

## 配置GitHub Secrets（Splunk Free版本）

### 最小配置
只需要设置以下Secrets：

```bash
# Splunk管理员密码（必需）
SPLUNK_ADMIN_PASSWORD=YourSecurePassword123

# 指定使用免费版本
SPLUNK_LICENSE_TYPE=free

# HTTP事件收集器令牌（可选，系统会自动生成）
SPLUNK_HEC_TOKEN=auto-generated
```

### 设置步骤
1. 进入GitHub仓库设置
2. 选择 **Secrets and variables** → **Actions**
3. 添加上述Secrets

## Splunk Free版本的SIEM实现策略

由于Free版本的限制，我们需要调整SIEM实施策略：

### 1. 手动监控替代自动告警
```splunk
# 创建保存的搜索，定期手动运行
# 暴力破解检测
index=linux sourcetype=linux_secure "Failed password" 
| stats count by src_ip, dest_host 
| where count > 10 
| sort -count

# Root用户活动监控
index=cloudtrail sourcetype=aws:cloudtrail userIdentity.type=Root 
| table _time, sourceIPAddress, eventName, userIdentity.type
| sort -_time

# 异常登录时间检测
index=linux sourcetype=linux_secure "Accepted password" 
| eval hour=strftime(_time,"%H") 
| where hour > 22 OR hour < 6
| table _time, user, src_ip, hour
```

### 2. 仪表板监控
创建实时仪表板来可视化安全事件：

- **安全概览仪表板**
- **登录活动监控**
- **AWS资源使用情况**
- **网络流量分析**

### 3. 数据管理策略
```splunk
# 优化数据保留，重要安全事件保留更长时间
[index:security_critical]
maxDataSize = 5000
maxTotalDataSizeMB = 10000

[index:general_logs] 
maxDataSize = 1000
maxTotalDataSizeMB = 2000
```

## 升级路径

### 何时考虑升级
- **数据量超过500MB/天**
- **需要自动告警功能**
- **需要分布式部署**
- **生产环境使用**

### 升级选项
1. **Splunk Enterprise试用版**（60天免费）
2. **Splunk Cloud试用版**（14天免费）
3. **Splunk Enterprise许可证**（付费）

### 升级步骤
```bash
# 1. 获取试用许可证
# 访问 https://www.splunk.com/en_us/download/splunk-enterprise.html

# 2. 更新GitHub Secrets
SPLUNK_LICENSE_KEY=your_trial_license_key
SPLUNK_LICENSE_TYPE=enterprise

# 3. 重新部署
kubectl delete standalone splunk-standalone -n splunk-enterprise
kubectl apply -f k8s/splunk-enterprise.yaml -n splunk-enterprise
```

## 实验建议

### 阶段1：基础设置（Week 1）
- [ ] 部署Splunk Free到EKS
- [ ] 配置基本数据输入（CloudTrail示例数据）
- [ ] 创建基础仪表板

### 阶段2：数据集成（Week 2）
- [ ] 集成AWS CloudTrail
- [ ] 配置EC2日志收集
- [ ] 创建数据解析规则

### 阶段3：安全检测（Week 3）
- [ ] 实现暴力破解检测搜索
- [ ] 创建Root用户活动监控
- [ ] 开发异常行为检测规则

### 阶段4：可视化和报告（Week 4）
- [ ] 创建安全运营仪表板
- [ ] 实现趋势分析视图
- [ ] 文档化检测规则

## 学习资源

### Splunk官方资源
- **Splunk Fundamentals**: 免费在线课程
- **Splunk Education**: https://education.splunk.com/
- **Splunk Docs**: https://docs.splunk.com/

### 实践练习
- **Boss of the SOC**: Splunk安全竞赛数据集
- **Splunk Attack Range**: 安全测试环境
- **GitHub示例**: 社区贡献的配置示例

## 故障排除

### 常见问题
1. **数据索引失败**
   - 检查每日500MB限制
   - 验证数据格式
   - 查看splunkd.log

2. **搜索性能慢**
   - 限制搜索时间范围
   - 优化搜索语法
   - 使用适当的索引

3. **仪表板不更新**
   - 检查数据源连接
   - 验证搜索语法
   - 刷新仪表板

### 获取帮助
- **Splunk社区**: https://community.splunk.com/
- **Stack Overflow**: splunk标签
- **Splunk Slack**: 社区讨论

---

**注意**: Splunk Free版本非常适合学习和小规模实验，但在生产环境中建议使用完整版本以获得告警和高可用性功能。
