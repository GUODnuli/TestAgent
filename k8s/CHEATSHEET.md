# TestAgent K8s 命令速查表

## 快速命令

```bash
# 部署
kubectl apply -f k8s/

# 查看状态
kubectl get all -n testagent

# 日志
kubectl logs -f deployment/testagent-server -n testagent

# 扩容
kubectl scale deployment testagent-server --replicas=5 -n testagent

# 重启
kubectl rollout restart deployment/testagent-server -n testagent
```

## 目录结构

```
k8s/
├── 01-namespace.yaml          # 命名空间
├── 02-configmap.yaml          # 配置
├── 03-secret.yaml             # 密钥
├── 04-postgres.yaml           # 数据库
├── 05-redis.yaml              # 缓存
├── 06-server-deployment.yaml  # 后端
├── 07-frontend-deployment.yaml # 前端
├── 08-ingress.yaml            # 入口
├── 09-hpa.yaml                # 自动扩缩容
├── frontend-Dockerfile
├── server-Dockerfile
├── nginx.conf
├── deploy.sh
└── README.md
```

## 关键配置修改点

1. **域名** → `08-ingress.yaml` 第 35 行
2. **镜像仓库** → `deploy.sh` 第 22 行
3. **数据库密码** → `03-secret.yaml`
4. **资源限制** → `06-server-deployment.yaml` 第 78 行
