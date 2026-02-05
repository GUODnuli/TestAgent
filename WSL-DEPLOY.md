# TestAgent WSL 本地部署指南

## ✅ 可行性确认

**完全可以！** WSL2 + Docker Desktop 是开发测试的最佳组合：

- ✅ WSL2 完整 Linux 内核支持
- ✅ Docker Desktop 集成 Kubernetes
- ✅ Windows 浏览器直接访问
- ✅ 与生产环境一致的容器化部署

## 🛠️ 前置条件

### 1. 安装 WSL2

```powershell
# 以管理员身份运行 PowerShell
wsl --install

# 设置为 WSL2 默认版本
wsl --set-default-version 2

# 安装 Ubuntu
wsl --install -d Ubuntu
```

### 2. 安装 Docker Desktop

1. 下载安装: https://docs.docker.com/desktop/install/windows-install/
2. Settings → Resources → WSL Integration → 启用 Ubuntu
3. Settings → Kubernetes → ✅ Enable Kubernetes
4. Apply & Restart

### 3. WSL Ubuntu 中安装工具

```bash
# 更新系统
sudo apt update && sudo apt upgrade -y

# 安装必要工具
sudo apt install -y curl wget git make

# 安装 kubectl
sudo apt install -y apt-transport-https ca-certificates curl gnupg
mkdir -p ~/.kube
curl -LO "https://dl.k8s/release/$(curl -L -s https://dl.k8s/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# 验证 kubectl 连接 (Docker Desktop 会自动配置)
kubectl cluster-info
# 输出: Kubernetes control plane is running at https://kubernetes.docker.internal:6443

# 可选：安装 Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

## 🚀 部署方式选择

| 方式 | 复杂度 | 适用场景 | 访问地址 |
|------|--------|---------|----------|
| **Docker Compose** ⭐推荐 | ⭐ | 快速体验 | http://localhost |
| **Kubectl + WSL 脚本** | ⭐⭐ | 学习 K8s | http://localhost:30080 |
| **Helm** | ⭐⭐⭐ | 多环境测试 | http://localhost:30080 |

---

## 方式 1: Docker Compose（最简单）

```bash
# 进入项目目录
cd /mnt/c/Users/YourName/Project/TestAgent  # 根据你的实际路径

# 一键启动
chmod +x k8s/wsl-deploy.sh
docker-compose -f wsl-docker-compose.yml up --build

# 或后台运行
docker-compose -f wsl-docker-compose.yml up -d

# 查看日志
docker-compose -f wsl-docker-compose.yml logs -f

# 停止
docker-compose -f wsl-docker-compose.yml down
```

**访问：**
- 前端: http://localhost
- API: http://localhost:3000
- 数据库: localhost:5433 (避免与本地 5432 冲突)

---

## 方式 2: Kubernetes + WSL 脚本

```bash
# 进入项目目录
cd /mnt/c/Users/YourName/Project/TestAgent

# 使用 WSL 专用部署脚本
chmod +x k8s/wsl-deploy.sh
./k8s/wsl-deploy.sh
```

脚本会自动：
1. 检查 Docker Desktop K8s
2. 安装 Ingress Controller
3. 构建镜像
4. 部署到本地 K8s
5. 配置 NodePort

**访问：**
- 前端: http://localhost:30080
- API: http://localhost:30081

---

## 方式 3: Helm（推荐用于学习）

```bash
# 创建本地 values 文件
cat > /tmp/local-values.yaml <<EOF
environment: local

frontend:
  replicaCount: 1
  service:
    type: NodePort
    nodePort: 30080
  ingress:
    enabled: false
  autoscaling:
    enabled: false

server:
  replicaCount: 1
  service:
    type: NodePort
    nodePort: 30081
  ingress:
    enabled: false
  autoscaling:
    enabled: false
  secrets:
    jwtSecret: "local-secret"

postgresql:
  persistence:
    size: 5Gi

redis:
  persistence:
    enabled: false
EOF

# 部署
helm upgrade --install testagent ./helm/testagent \
    --namespace testagent \
    --create-namespace \
    --values /tmp/local-values.yaml \
    --wait

# 查看状态
kubectl get all -n testagent
```

---

## 🔧 常见问题

### 1. kubectl 无法连接

```bash
# 检查 Docker Desktop K8s 是否启用
docker ps
kubectl cluster-info

# 如果失败，手动配置 kubeconfig
mkdir -p ~/.kube
cp /mnt/c/Users/$USER/.kube/config ~/.kube/config
sed -i 's|C:|/mnt/c|' ~/.kube/config
kubectl cluster-info
```

### 2. 镜像拉取失败

```bash
# WSL 本地镜像需要特殊处理
# 方案 A: 使用本地镜像 (pullPolicy: Never)
kubectl set image deployment/testagent-frontend frontend=testagent-frontend:latest -n testagent

# 方案 B: 加载镜像到 kind (如果使用 kind)
# kind load docker-image testagent-frontend:latest --name testagent
```

### 3. 端口冲突

```bash
# 检查端口占用
sudo netstat -tlnp | grep 30080
sudo lsof -i :30080

# 修改 NodePort (30000-32767 范围)
kubectl patch svc testagent-frontend -n testagent -p '{"spec":{"ports":[{"port":80,"nodePort":30082}]}}'
```

### 4. 存储问题

```bash
# WSL 默认存储类可能不同
kubectl get storageclass

# 如果没有默认 SC，使用本地路径
kubectl get pvc -n testagent
```

### 5. Windows 浏览器无法访问

```bash
# 方案 A: 使用端口转发
kubectl port-forward svc/testagent-frontend 8080:80 -n testagent
# 访问: http://localhost:8080

# 方案 B: 检查 WSL IP
ip addr | grep eth0
# 使用 WSL IP 访问: http://<WSL_IP>:30080

# 方案 C: 使用 hostPort (不推荐生产环境)
# 修改 deployment 添加 hostPort
```

---

## 📝 开发工作流

### 代码修改后重新部署

```bash
# Docker Compose 方式
docker-compose -f wsl-docker-compose.yml up -d --build

# K8s 方式（滚动更新）
kubectl rollout restart deployment/testagent-server -n testagent
kubectl rollout restart deployment/testagent-frontend -n testagent
```

### 查看日志

```bash
# Docker Compose
docker-compose -f wsl-docker-compose.yml logs -f server

# K8s
kubectl logs -f deployment/testagent-server -n testagent
kubectl logs -f deployment/testagent-frontend -n testagent
```

### 进入容器调试

```bash
# Docker Compose
docker-compose -f wsl-docker-compose.yml exec server /bin/sh

# K8s
kubectl exec -it deployment/testagent-server -n testagent -- /bin/sh
```

---

## 🧹 清理资源

```bash
# Docker Compose 清理
docker-compose -f wsl-docker-compose.yml down -v

# K8s 清理
kubectl delete namespace testagent

# 删除所有资源（包括存储）
kubectl delete namespace testagent
kubectl delete pvc --all -n testagent
```

---

## 🌐 网络访问汇总

| 服务 | Docker Compose | Kubernetes NodePort | kubectl port-forward |
|------|----------------|---------------------|---------------------|
| 前端 | http://localhost | http://localhost:30080 | http://localhost:8080 |
| API | http://localhost:3000 | http://localhost:30081 | - |
| 数据库 | localhost:5433 | - | - |
| Redis | localhost:6379 | - | - |

---

## 💡 进阶配置

### 使用自定义域名

```bash
# Windows 侧: 修改 C:\Windows\System32\drivers\etc\hosts
# 添加:
127.0.0.1 testagent.local
127.0.0.1 api.testagent.local

# WSL 侧: 修改 /etc/hosts
echo '127.0.0.1 testagent.local api.testagent.local' | sudo tee -a /etc/hosts

# 然后使用域名访问: http://testagent.local:30080
```

### 使用 VS Code + WSL 开发

```bash
# 在 WSL 中安装 code 命令
curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
sudo install -o root -g root -m 644 microsoft.gpg /etc/apt/trusted.gpg.d/
echo "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main" | sudo tee /etc/apt/sources.list.d/vscode.list
sudo apt update
sudo apt install code

# 在项目目录打开 VS Code
code .
# 自动连接到 WSL 环境
```

---

## ✅ 验证清单

部署完成后检查：

```bash
# 1. 容器运行状态
docker ps  # 或 kubectl get pods -n testagent

# 2. 服务可访问
curl http://localhost:3000/health  # API 健康检查

# 3. 数据库连接
psql -h localhost -p 5433 -U mcp_user -d testagent

# 4. 前端页面
# 浏览器访问 http://localhost (或 http://localhost:30080)
```

---

## 🆘 获取帮助

遇到问题？

1. 查看 Docker Desktop 状态: `docker ps`
2. 查看 K8s 状态: `kubectl get all -n testagent`
3. 查看日志: `kubectl logs -n testagent <pod-name>`
4. WSL 网络诊断: `ip addr`, `cat /etc/resolv.conf`
