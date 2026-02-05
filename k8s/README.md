# TestAgent Kubernetes 部署指南

## 架构概览

```
┌─────────────────────────────────────────────────────────────────┐
│                         Ingress (Nginx)                         │
│  ┌──────────────────┐         ┌──────────────────┐             │
│  │ testagent.your   │         │ api.testagent    │             │
│  │ domain.com       │         │ .yourdomain.com  │             │
│  └────────┬─────────┘         └────────┬─────────┘             │
└───────────┼────────────────────────────┼───────────────────────┘
            │                            │
            ▼                            ▼
┌──────────────────────┐    ┌──────────────────────┐
│  Frontend Service    │    │  Server Service      │
│  (Nginx + Vue.js)    │    │  (Node.js/Fastify)   │
│  - 2+ Replicas       │    │  - 2+ Replicas       │
│  - HPA 自动扩缩容     │    │  - HPA 自动扩缩容     │
└──────────┬───────────┘    └──────────┬───────────┘
           │                           │
           │     ┌─────────────────┐   │
           └────►│  PostgreSQL     │◄──┘
                 │  (StatefulSet)  │
                 └─────────────────┘
                 ┌─────────────────┐
           ┌────►│  Redis          │◄──┐
           │     │  (Deployment)   │   │
           │     └─────────────────┘   │
           │                           │
           └───────────────────────────┘
```

## 前置条件

- Kubernetes 集群 (1.24+)
- kubectl 配置完成
- Docker (用于构建镜像)
- Ingress Controller (推荐 NGINX)
- cert-manager (用于 HTTPS 证书，可选)
- 云存储类 (用于持久化数据)

## 快速开始

### 1. 配置域名和证书

编辑 `08-ingress.yaml`，替换域名：
```yaml
hosts:
  - testagent.yourdomain.com
  - api.testagent.yourdomain.com
```

### 2. 配置密钥

编辑 `03-secret.yaml`，设置安全的密钥：
```bash
# 生成随机 JWT 密钥
openssl rand -base64 32
```

### 3. 配置镜像仓库（可选）

如果使用私有仓库，编辑 deploy.sh：
```bash
export DOCKER_REGISTRY="your-registry.com"
```

### 4. 一键部署

```bash
cd k8s

# 直接部署（使用本地镜像）
./deploy.sh

# 构建并推送镜像后部署
BUILD=true ./deploy.sh

# 指定版本部署
./deploy.sh prod v1.0.0
```

## 详细部署步骤

### 步骤 1: 构建镜像

```bash
# 前端镜像
docker build -f frontend-Dockerfile -t testagent-frontend:latest ../Client

# 后端镜像（先编译）
cd ../Client/server
npm ci
npm run build
cd ../../k8s
docker build -f server-Dockerfile -t testagent-server:latest ../Client

# 推送镜像到仓库（如果需要）
docker tag testagent-frontend:latest your-registry.com/testagent-frontend:latest
docker push your-registry.com/testagent-frontend:latest
docker tag testagent-server:latest your-registry.com/testagent-server:latest
docker push your-registry.com/testagent-server:latest
```

### 步骤 2: 部署基础资源

```bash
kubectl apply -f 01-namespace.yaml
kubectl apply -f 02-configmap.yaml
kubectl apply -f 03-secret.yaml
```

### 步骤 3: 部署数据库

```bash
kubectl apply -f 04-postgres.yaml
kubectl apply -f 05-redis.yaml

# 等待数据库就绪
kubectl wait --for=condition=ready pod -l app=postgres -n testagent --timeout=120s
kubectl wait --for=condition=ready pod -l app=redis -n testagent --timeout=60s
```

### 步骤 4: 部署应用

```bash
kubectl apply -f 06-server-deployment.yaml
kubectl apply -f 07-frontend-deployment.yaml
```

### 步骤 5: 配置 Ingress

```bash
kubectl apply -f 08-ingress.yaml
```

### 步骤 6: 启用自动扩缩容

```bash
kubectl apply -f 09-hpa.yaml
```

## 验证部署

```bash
# 查看所有资源
kubectl get all -n testagent

# 查看 Pod 状态
kubectl get pods -n testagent -w

# 查看服务日志
kubectl logs -f deployment/testagent-server -n testagent
kubectl logs -f deployment/testagent-frontend -n testagent

# 进入 Pod 调试
kubectl exec -it deployment/testagent-server -n testagent -- /bin/sh
```

## 配置说明

### 环境变量 (02-configmap.yaml)

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `DATABASE_URL` | PostgreSQL 连接字符串 | - |
| `REDIS_URL` | Redis 连接字符串 | - |
| `JWT_SECRET` | JWT 签名密钥 | - |
| `LOG_LEVEL` | 日志级别 | info |
| `MAX_FILE_SIZE` | 最大上传文件大小 | 100MB |

### 资源限制

| 组件 | CPU 请求 | CPU 限制 | 内存请求 | 内存限制 |
|------|---------|---------|---------|---------|
| Frontend | 50m | 100m | 64Mi | 128Mi |
| Server | 500m | 1000m | 512Mi | 1Gi |
| PostgreSQL | 250m | 500m | 256Mi | 512Mi |
| Redis | 100m | 200m | 128Mi | 256Mi |

### 持久化存储

| 组件 | 存储大小 | 访问模式 |
|------|---------|---------|
| PostgreSQL | 10Gi | ReadWriteOnce |
| Redis | 5Gi | ReadWriteOnce |
| Uploads | 10Gi | ReadWriteMany |

## 生产环境建议

### 1. 使用托管数据库

修改 `02-configmap.yaml`，使用云服务商的托管数据库：
```yaml
DATABASE_URL: "postgresql://user:pass@rds.amazonaws.com:5432/testagent"
```

删除 `04-postgres.yaml` 的部署。

### 2. 使用托管 Redis

```yaml
REDIS_URL: "redis://elasticache.abc.cache.amazonaws.com:6379"
```

删除 `05-redis.yaml` 的部署。

### 3. 配置证书

使用 cert-manager 自动管理证书：
```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
```

### 4. 监控和日志

部署 Prometheus + Grafana：
```bash
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.enabled=true
```

### 5. 备份策略

创建定时备份任务：
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-backup
spec:
  schedule: "0 2 * * *"  # 每天凌晨2点
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: postgres:16-alpine
            command:
            - /bin/sh
            - -c
            - pg_dump -h postgres -U mcp_user testagent > /backup/testagent-$(date +%Y%m%d).sql
          restartPolicy: OnFailure
```

## 故障排查

### Pod 无法启动

```bash
# 查看事件
kubectl get events -n testagent --sort-by='.lastTimestamp'

# 查看 Pod 详情
kubectl describe pod <pod-name> -n testagent
```

### 数据库连接失败

```bash
# 检查数据库 Pod
kubectl get pods -l app=postgres -n testagent

# 查看数据库日志
kubectl logs -l app=postgres -n testagent

# 测试连接
kubectl run pg-test --rm -it --image=postgres:16-alpine -- \
  psql postgresql://mcp_user:mcp_password@postgres:5432/testagent
```

### Ingress 无法访问

```bash
# 检查 Ingress 状态
kubectl get ingress -n testagent

# 查看 Ingress Controller 日志
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
```

## 更新部署

```bash
# 滚动更新 Server
kubectl rollout restart deployment/testagent-server -n testagent

# 查看更新进度
kubectl rollout status deployment/testagent-server -n testagent

# 回滚（如有问题）
kubectl rollout undo deployment/testagent-server -n testagent
```

## 清理资源

```bash
# 删除所有资源
kubectl delete namespace testagent

# 删除存储卷（注意：数据会丢失！）
kubectl delete pvc --all -n testagent
```

## 相关文档

- [Kubernetes 官方文档](https://kubernetes.io/docs/)
- [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [cert-manager 文档](https://cert-manager.io/docs/)
