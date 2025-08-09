# GitHub Secrets 配置指导

为了让GitHub Actions能够安全地部署您的SIEM项目到AWS环境，您需要配置以下Secrets。

## 必需的AWS凭证

### 1. AWS访问密钥
在您的GitHub仓库中添加以下Secrets：

- **`AWS_ACCESS_KEY_ID`**: 您的AWS访问密钥ID
- **`AWS_SECRET_ACCESS_KEY`**: 您的AWS秘密访问密钥
- **`AWS_DEFAULT_REGION`**: AWS区域（如：`us-east-1`）

### 2. EKS集群配置
- **`EKS_CLUSTER_NAME`**: 您的EKS集群名称
- **`EKS_ROLE_ARN`**: EKS服务角色ARN（如：`arn:aws:iam::ACCOUNT:role/eks-service-role`）

## Splunk配置

### 3. Splunk许可证和配置

#### 免费试用选项（推荐用于实验）

**选项1：Splunk Free（推荐用于学习）**
- 免费版本，每日最多500MB数据索引
- 功能限制：无告警、无分布式搜索、数据保留时间有限
- **不需要许可证密钥**，直接使用免费版

**选项2：Splunk Enterprise 60天试用**
- 完整功能的60天免费试用
- 需要注册获取试用许可证
- 访问：https://www.splunk.com/en_us/download/splunk-enterprise.html

**选项3：Splunk Cloud 14天试用**
- 完全托管的云版本
- 访问：https://www.splunk.com/en_us/products/splunk-cloud-platform.html

#### 推荐配置（使用Splunk Free）
- **`SPLUNK_LICENSE_TYPE`**: `free` （使用免费版本）
- **`SPLUNK_ADMIN_PASSWORD`**: Splunk管理员密码（至少8位字符）
- **`SPLUNK_HEC_TOKEN`**: HTTP事件收集器令牌（可选，用于日志收集）

#### 如果使用试用许可证
- **`SPLUNK_LICENSE_KEY`**: 从Splunk官网获取的试用许可证密钥
- **`SPLUNK_ADMIN_PASSWORD`**: Splunk管理员密码（至少8位字符）
- **`SPLUNK_HEC_TOKEN`**: HTTP事件收集器令牌（可选，用于日志收集）

## 通知和告警配置

### 4. 邮件通知（AWS SES）
- **`AWS_SES_SMTP_USERNAME`**: SES SMTP用户名
- **`AWS_SES_SMTP_PASSWORD`**: SES SMTP密码
- **`NOTIFICATION_EMAIL`**: 接收告警的邮箱地址

### 5. Slack集成（可选）
- **`SLACK_WEBHOOK_URL`**: Slack Webhook URL
- **`SLACK_CHANNEL`**: Slack频道名称（如：`#security-alerts`）

## 如何添加GitHub Secrets

### 方法1：通过GitHub Web界面
1. 进入您的GitHub仓库
2. 点击 **Settings** 标签
3. 在左侧菜单中选择 **Secrets and variables** → **Actions**
4. 点击 **New repository secret**
5. 输入Secret名称和值
6. 点击 **Add secret**

### 方法2：使用GitHub CLI
```bash
# 安装GitHub CLI（如果尚未安装）
# macOS: brew install gh
# Windows: choco install gh
# Linux: 参考官方文档

# 登录GitHub
gh auth login

# 添加Secrets
gh secret set AWS_ACCESS_KEY_ID
gh secret set AWS_SECRET_ACCESS_KEY
gh secret set AWS_DEFAULT_REGION
gh secret set EKS_CLUSTER_NAME
gh secret set SPLUNK_LICENSE_KEY
gh secret set SPLUNK_ADMIN_PASSWORD
# ... 继续添加其他secrets
```

## AWS IAM权限要求

确保您的AWS凭证具有以下权限：

### EKS权限
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "eks:DescribeCluster",
                "eks:ListClusters",
                "eks:DescribeNodegroup",
                "eks:ListNodegroups"
            ],
            "Resource": "*"
        }
    ]
}
```

### EC2权限
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeVpcs",
                "ec2:DescribeSubnets"
            ],
            "Resource": "*"
        }
    ]
}
```

### CloudWatch和CloudTrail权限
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cloudwatch:GetMetricStatistics",
                "cloudwatch:ListMetrics",
                "cloudtrail:LookupEvents",
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams"
            ],
            "Resource": "*"
        }
    ]
}
```

## 安全最佳实践

### 1. 最小权限原则
- 只授予GitHub Actions所需的最小权限
- 定期审查和更新IAM策略

### 2. 访问密钥轮换
- 定期轮换AWS访问密钥
- 使用AWS IAM角色（推荐用于生产环境）

### 3. 环境分离
```bash
# 为不同环境设置不同的Secrets
# 开发环境
AWS_ACCESS_KEY_ID_DEV
AWS_SECRET_ACCESS_KEY_DEV

# 生产环境
AWS_ACCESS_KEY_ID_PROD
AWS_SECRET_ACCESS_KEY_PROD
```

## 验证配置

配置完成后，您可以通过运行以下GitHub Actions工作流来验证配置：

```yaml
name: Verify AWS Connectivity
on:
  workflow_dispatch:

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_DEFAULT_REGION }}
      
      - name: Test AWS connectivity
        run: |
          aws sts get-caller-identity
          aws eks describe-cluster --name ${{ secrets.EKS_CLUSTER_NAME }}
```

## 故障排除

### 常见问题
1. **权限不足错误**: 检查IAM策略是否包含所需权限
2. **区域不匹配**: 确保AWS_DEFAULT_REGION与您的资源所在区域一致
3. **集群不存在**: 验证EKS_CLUSTER_NAME是否正确

### 获取帮助
如果遇到问题，请检查：
- AWS CloudTrail日志
- GitHub Actions运行日志
- EKS集群状态

---

**注意**: 保护好您的凭证信息，永远不要将Secrets提交到代码仓库中。
