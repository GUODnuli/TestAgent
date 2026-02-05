# Jenkins + Helm + Ansible CI/CD 配置指南

## 架构流程

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Git Push   │────►│   Jenkins   │────►│ Helm/Ansible│────►│    K8s      │
│  (GitHub)   │     │  Pipeline   │     │   Deploy    │     │  Cluster    │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
                            │
                            ▼
                     ┌─────────────┐
                     │   Docker    │
                     │   Build     │
                     └─────────────┘
```

## 1. Jenkins 环境准备

### 1.1 安装必要插件

- **Pipeline** - 流水线支持
- **Docker Pipeline** - Docker 构建
- **Kubernetes CLI** - kubectl 命令
- **Ansible** - Ansible 集成
- **Credentials Binding** - 凭证管理
- **HTML Publisher** - 测试报告
- **Slack Notification** - 通知（可选）

### 1.2 配置 Jenkins Credentials

在 Jenkins 管理界面添加以下凭证：

| ID | 类型 | 说明 |
|----|------|------|
| `docker-registry-url` | Secret text | Docker 仓库地址 |
| `docker-registry-credentials` | Username/Password | Docker 仓库登录凭据 |
| `kubeconfig` | Secret file | kubectl 配置文件 |
| `ansible-vault-password` | Secret text | Ansible Vault 密码（可选） |

### 1.3 安装工具

在 Jenkins 节点上安装：

```bash
# Docker
apt-get install docker.io
usermod -aG docker jenkins

# kubectl
curl -LO "https://dl.k8s/release/$(curl -L -s https://dl.k8s/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && mv kubectl /usr/local/bin/

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Ansible
apt-get install ansible

# Trivy (安全扫描)
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh
```

## 2. 创建 Jenkins Pipeline 任务

### 2.1 新建 Pipeline 任务

1. Jenkins 首页 → New Item
2. 输入名称: `TestAgent-CI`
3. 选择类型: **Pipeline**
4. 点击 OK

### 2.2 配置 Pipeline

在 Pipeline 配置中选择:

```
Definition: Pipeline script from SCM
SCM: Git
Repository URL: https://github.com/your-org/testagent.git
Credentials: (Git 仓库凭据)
Script Path: jenkins/Jenkinsfile
Branches to build: */
```

### 2.3 配置 Webhook（自动触发）

**GitHub:**
1. 仓库 Settings → Webhooks → Add webhook
2. Payload URL: `https://jenkins.yourdomain.com/github-webhook/`
3. Content type: `application/json`
4. Events: Push events, Pull requests

**GitLab:**
1. 项目 Settings → Webhooks
2. URL: `https://jenkins.yourdomain.com/project/TestAgent-CI`
3. Triggers: Push events, Merge request events

## 3. 多环境配置

### 3.1 目录结构

```
ansible/
├── inventory/
│   ├── hosts                    # 主机清单
│   └── group_vars/
│       ├── all.yml             # 通用变量
│       ├── dev.yml             # 开发环境
│       ├── staging.yml         # 测试环境
│       └── prod.yml            # 生产环境
├── playbooks/
│   ├── deploy.yml              # 主部署脚本
│   ├── rollback.yml            # 回滚脚本
│   └── maintenance.yml         # 维护脚本
├── roles/
│   ├── k8s/                    # K8s 角色
│   └── helm/                   # Helm 角色
└── templates/
    ├── values-dev.yml.j2
    ├── values-staging.yml.j2
    └── values-prod.yml.j2
```

### 3.2 环境变量配置

```bash
# 开发环境
export DEPLOY_ENV=dev
export HELM_NAMESPACE=testagent-dev

# 生产环境
export DEPLOY_ENV=prod
export HELM_NAMESPACE=testagent
export USE_EXTERNAL_DB=true
```

## 4. 常用操作

### 4.1 手动触发部署

```bash
# 使用 Ansible 部署到指定环境
ansible-playbook -i ansible/inventory/hosts \
    ansible/playbooks/deploy.yml \
    -e "deploy_environment=prod" \
    -e "deploy_version=v1.2.3" \
    --ask-vault-pass

# 使用 Helm 直接部署
helm upgrade --install testagent helm/testagent \
    --namespace testagent \
    --values helm/testagent/values.yaml \
    --set frontend.image.tag=v1.2.3 \
    --set server.image.tag=v1.2.3
```

### 4.2 回滚操作

```bash
# Helm 回滚到上一版本
helm rollback testagent 0 --namespace testagent

# 回滚到指定版本
helm rollback testagent 3 --namespace testagent

# 查看历史版本
helm history testagent --namespace testagent
```

### 4.3 查看部署状态

```bash
# Helm 状态
helm status testagent --namespace testagent

# K8s 资源
kubectl get all -n testagent

# Pod 日志
kubectl logs -f deployment/testagent-server -n testagent

# 事件查看
kubectl get events -n testagent --sort-by='.lastTimestamp'
```

## 5. 多分支流水线配置

如果需要为每个分支创建独立环境，使用 Jenkins Multibranch Pipeline:

```groovy
// Jenkinsfile (multibranch)
pipeline {
    agent any
    
    stages {
        stage('Determine Environment') {
            steps {
                script {
                    // 根据分支确定环境
                    env.DEPLOY_ENV = env.BRANCH_NAME == 'main' ? 'prod' :
                                     env.BRANCH_NAME == 'develop' ? 'dev' :
                                     env.BRANCH_NAME.startsWith('release/') ? 'staging' :
                                     'preview'
                    
                    env.NAMESPACE = "testagent-${DEPLOY_ENV}"
                }
            }
        }
        
        // ... 后续阶段
    }
}
```

## 6. 蓝绿部署/金丝雀发布

使用 Helm 实现金丝雀发布:

```bash
# 1. 部署金丝雀版本 (10% 流量)
helm upgrade --install testagent-canary helm/testagent \
    --namespace testagent \
    --values values-canary.yaml \
    --set server.replicaCount=1 \
    --set server.labels.canary=true

# 2. 验证金丝雀
kubectl run test --rm -i --restart=Never \
    --image=curlimages/curl \
    -- curl testagent-server-canary:3000/health

# 3. 推广到全部流量
helm upgrade testagent helm/testagent \
    --namespace testagent \
    --values values.yaml \
    --set server.image.tag=new-version

# 4. 清理金丝雀
helm delete testagent-canary --namespace testagent
```

## 7. 监控和告警

### 7.1 部署 Prometheus ServiceMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: testagent-metrics
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: testagent
  endpoints:
    - port: http
      path: /metrics
      interval: 30s
```

### 7.2 Jenkins 告警配置

```groovy
post {
    failure {
        slackSend(
            color: 'danger',
            message: "❌ Build failed: ${env.JOB_NAME} #${env.BUILD_NUMBER}"
        )
    }
    fixed {
        slackSend(
            color: 'good', 
            message: "✅ Build fixed: ${env.JOB_NAME} #${env.BUILD_NUMBER}"
        )
    }
}
```

## 8. 故障排查

### Jenkins 构建失败

```bash
# 查看 Jenkins 日志
tail -f /var/log/jenkins/jenkins.log

# 检查 Docker 权限
groups jenkins

# 验证 kubectl 配置
sudo -u jenkins kubectl cluster-info
```

### Helm 部署失败

```bash
# 查看 Helm 历史
helm history testagent --namespace testagent

# 调试渲染后的模板
helm template testagent helm/testagent --debug

# 查看失败原因
kubectl describe pod <pod-name> -n testagent
```
