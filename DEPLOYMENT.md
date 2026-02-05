# TestAgent 完整部署指南

## 部署方案对比

| 方案 | 适用场景 | 复杂度 | 推荐度 |
|------|---------|--------|--------|
| **纯 Kubernetes YAML** | 快速体验、单环境 | ⭐⭐ | ⭐⭐⭐ |
| **Helm Chart** | 多环境、配置管理 | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Helm + Ansible + Jenkins** | 企业级 CI/CD | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |

## 快速选择

```
你是哪类用户？
├─ 开发测试 → 使用 Docker Compose
│   $ docker-compose up -d
│
├─ 单环境部署 → 使用 K8s YAML
│   $ kubectl apply -f k8s/
│
├─ 多环境管理 → 使用 Helm
│   $ helm install testagent helm/testagent
│
└─ 企业 CI/CD → 使用 Helm + Ansible + Jenkins
    $ git push origin main  # 自动触发部署
```

## 目录导航

```
部署相关文件：
├── k8s/                    # Kubernetes 原生配置
│   ├── *.yaml             # 各组件配置
│   ├── deploy.sh          # 一键部署脚本
│   └── README.md          # K8s 部署文档
│
├── helm/testagent/        # Helm Chart
│   ├── Chart.yaml         # Chart 定义
│   ├── values.yaml        # 默认配置
│   ├── templates/         # K8s 模板
│   └── values-*.yaml      # 环境特定配置
│
├── ansible/               # Ansible Playbook
│   ├── playbooks/
│   │   └── deploy.yml     # 主部署脚本
│   ├── inventory/         # 主机清单
│   └── templates/         # Jinja2 模板
│
└── jenkins/
    ├── Jenkinsfile        # CI/CD 流水线
    └── README.md          # Jenkins 配置
```

## 方案 1: Kubernetes 原生部署

适合：快速体验、单环境部署

```bash
cd k8s

# 修改配置
vim 02-configmap.yaml    # 配置环境变量
vim 03-secret.yaml       # 配置密钥
vim 08-ingress.yaml      # 配置域名

# 一键部署
chmod +x deploy.sh
./deploy.sh prod v1.0.0
```

## 方案 2: Helm 部署

适合：多环境管理、配置复用

```bash
# 安装/升级
helm upgrade --install testagent helm/testagent \
    --namespace testagent \
    --create-namespace \
    --values helm/testagent/values.yaml \
    --set frontend.image.tag=v1.0.0 \
    --set server.image.tag=v1.0.0

# 不同环境使用不同 values
helm upgrade --install testagent helm/testagent \
    --namespace testagent-prod \
    --values helm/testagent/values-prod.yaml

# 查看状态
helm status testagent -n testagent
helm list -n testagent
```

## 方案 3: Helm + Ansible + Jenkins CI/CD

适合：企业级生产环境

### 架构图

```
Developer          Jenkins           Ansible          K8s
    │                │                 │              │
    │  git push      │                 │              │
    ├───────────────►│                 │              │
    │                │  Build Image    │              │
    │                │  Run Tests      │              │
    │                │  Security Scan  │              │
    │                │                 │              │
    │                │  Deploy Call    │              │
    │                ├───────────────►│              │
    │                │                 │  Helm Install│
    │                │                 ├─────────────►│
    │                │                 │              │
    │                │  Notify Result  │              │
    │◄───────────────┤                 │              │
```

### 使用方式

```bash
# 1. 配置 Ansible 清单
vim ansible/inventory/hosts
vim ansible/inventory/group_vars/all.yml

# 2. 手动部署
ansible-playbook ansible/playbooks/deploy.yml \
    -e "deploy_version=v1.0.0" \
    -e "deploy_environment=prod"

# 3. 或推送到 Git 触发 Jenkins 自动部署
git tag v1.0.0
git push origin v1.0.0
```

## 三种方案对比详解

### 配置管理

| 场景 | K8s YAML | Helm | Helm+Ansible |
|------|---------|------|--------------|
| 修改副本数 | 编辑 YAML → apply | values.yaml → upgrade | group_vars → playbook |
| 多环境差异 | 多份 YAML | values-dev/staging/prod | inventory/group_vars |
| 敏感信息 | Secret YAML | Secret + values | Ansible Vault |
| 版本管理 | Git | Git + Helm history | Git + Ansible logs |

### 回滚操作

```bash
# K8s YAML
kubectl rollout undo deployment/testagent-server

# Helm
helm rollback testagent 2  # 回滚到版本 2

# Ansible+Jenkins
ansible-playbook ansible/playbooks/rollback.yml
```

### 常用命令速查

```bash
# 查看所有资源
kubectl get all -n testagent

# 查看日志
kubectl logs -f deployment/testagent-server -n testagent

# 进入容器
kubectl exec -it deployment/testagent-server -n testagent -- /bin/sh

# 扩缩容
kubectl scale deployment testagent-server --replicas=5 -n testagent

# 端口转发
kubectl port-forward svc/testagent-server 3000:3000 -n testagent
```

## 推荐工作流

### 开发环境
```
代码修改 → Docker Compose → 本地验证
```

### 测试环境
```
PR 合并 → Jenkins 自动部署到 Dev → QA 测试
```

### 生产环境
```
打 Tag → Jenkins 构建 → 审批 → Ansible 部署 → 监控验证
```

## 问题排查

| 问题 | 排查命令 |
|------|---------|
| Pod 无法启动 | `kubectl describe pod <pod>` |
| 服务无法访问 | `kubectl get svc,ep` |
| 配置未生效 | `kubectl get configmap -o yaml` |
| 性能问题 | `kubectl top pod` |
| 网络问题 | `kubectl get networkpolicy` |

## 安全建议

1. **生产环境必须使用**:
   - 外部托管数据库 (RDS/Cloud SQL)
   - 外部 Redis (ElastiCache/MemoryStore)
   - TLS 证书 (Let's Encrypt/cert-manager)
   - Network Policy
   - Pod Security Policy

2. **密钥管理**:
   - 开发: Secret YAML
   - 生产: Ansible Vault / Vault / AWS Secrets Manager

3. **镜像安全**:
   - 使用私有镜像仓库
   - 镜像签名验证
   - 定期安全扫描 (Trivy/Snyk)

## 获取帮助

- K8s 部署: 查看 `k8s/README.md`
- Helm Chart: 查看 `helm/testagent/Chart.yaml`
- CI/CD 配置: 查看 `jenkins/README.md`
