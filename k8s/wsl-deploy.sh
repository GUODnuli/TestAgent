#!/bin/bash

# TestAgent WSL 本地部署脚本
# 适用于 WSL2 + Docker Desktop Kubernetes

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="testagent"
LOCAL_MODE=true

echo "🚀 TestAgent WSL 本地部署"
echo "=========================="

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查函数
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}❌ $1 未安装${NC}"
        return 1
    else
        echo -e "${GREEN}✅ $1 已安装${NC}"
        return 0
    fi
}

# 检查依赖
echo ""
echo "📋 检查依赖..."
check_command kubectl || exit 1
check_command docker || exit 1

# 检查 Docker Desktop K8s
echo ""
echo "🔗 检查 Kubernetes 连接..."
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ 无法连接到 Kubernetes 集群${NC}"
    echo ""
    echo "请确保："
    echo "  1. Docker Desktop 已安装并运行"
    echo "  2. Settings → Kubernetes → Enable Kubernetes 已勾选"
    echo "  3. 等待 Kubernetes 启动完成"
    exit 1
fi
echo -e "${GREEN}✅ Kubernetes 连接正常${NC}"
kubectl cluster-info

# 启用 Ingress Controller（如果没有）
echo ""
echo "🌐 检查 Ingress Controller..."
if ! kubectl get pods -n ingress-nginx 2>/dev/null | grep -q "ingress-nginx"; then
    echo -e "${YELLOW}⚠️ 未检测到 Ingress Controller，正在安装...${NC}"
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
    
    echo "等待 Ingress Controller 就绪..."
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=90s
fi
echo -e "${GREEN}✅ Ingress Controller 就绪${NC}"

# 创建命名空间
echo ""
echo "📁 创建命名空间..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# 为本地部署修改配置
echo ""
echo "⚙️  准备本地部署配置..."

# 创建本地专用的 values 文件
cat > /tmp/testagent-local-values.yaml <<EOF
environment: local

global:
  imageRegistry: ""

frontend:
  replicaCount: 1
  image:
    repository: testagent-frontend
    tag: latest
    pullPolicy: Never  # 本地镜像不拉取
  
  service:
    type: NodePort
    port: 80
    nodePort: 30080  # 通过 localhost:30080 访问
  
  ingress:
    enabled: false  # 本地使用 NodePort
  
  autoscaling:
    enabled: false
  
  resources:
    limits:
      cpu: 500m
      memory: 256Mi
    requests:
      cpu: 100m
      memory: 128Mi

server:
  replicaCount: 1
  image:
    repository: testagent-server
    tag: latest
    pullPolicy: Never
  
  service:
    type: NodePort
    port: 3000
    nodePort: 30081
  
  ingress:
    enabled: false
  
  autoscaling:
    enabled: false
  
  resources:
    limits:
      cpu: 1000m
      memory: 512Mi
    requests:
      cpu: 250m
      memory: 256Mi
  
  secrets:
    jwtSecret: "local-dev-secret-change-in-production"

postgresql:
  enabled: true
  persistence:
    enabled: true
    size: 5Gi
    # WSL 使用默认存储类
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 250m
      memory: 256Mi

redis:
  enabled: true
  persistence:
    enabled: false  # 本地开发不持久化
  resources:
    limits:
      cpu: 200m
      memory: 256Mi
    requests:
      cpu: 100m
      memory: 128Mi

persistence:
  uploads:
    enabled: true
    size: 5Gi
    accessMode: ReadWriteOnce
EOF

# 检查本地镜像
echo ""
echo "🐳 检查本地镜像..."

build_image() {
    local name=$1
    local dockerfile=$2
    local context=$3
    
    if ! docker images "$name:latest" --format "{{.Repository}}" | grep -q "$name"; then
        echo -e "${YELLOW}⚠️ 镜像 $name:latest 不存在，需要构建${NC}"
        echo "构建 $name..."
        
        # 检查 Dockerfile 是否存在
        if [ ! -f "$SCRIPT_DIR/$dockerfile" ]; then
            echo -e "${RED}❌ Dockerfile 不存在: $SCRIPT_DIR/$dockerfile${NC}"
            return 1
        fi
        
        docker build -f "$SCRIPT_DIR/$dockerfile" -t "$name:latest" "$context"
        
        # 加载到 kind/k3d（如果使用）
        # kind load docker-image "$name:latest" --name testagent 2>/dev/null || true
    else
        echo -e "${GREEN}✅ 镜像 $name:latest 已存在${NC}"
    fi
}

# 询问是否构建镜像
echo ""
read -p "是否构建 Docker 镜像? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # 构建后端（先编译）
    echo "编译后端..."
    cd "$SCRIPT_DIR/../Client/server"
    npm ci
    npm run build
    cd - > /dev/null
    
    build_image "testagent-frontend" "frontend-Dockerfile" "$SCRIPT_DIR/../Client"
    build_image "testagent-server" "server-Dockerfile" "$SCRIPT_DIR/../Client"
else
    echo -e "${YELLOW}⚠️ 跳过镜像构建，使用已有镜像${NC}"
fi

# 部署
echo ""
echo "🚀 开始部署..."

# 使用 Helm 或 Kubectl
cd "$SCRIPT_DIR/../helm"

if command -v helm &> /dev/null; then
    echo "使用 Helm 部署..."
    helm upgrade --install testagent ./testagent \
        --namespace "$NAMESPACE" \
        --values /tmp/testagent-local-values.yaml \
        --wait \
        --timeout 300s
else
    echo "使用 kubectl 部署..."
    # 使用 kustomize 或直接 apply
    cd "$SCRIPT_DIR"
    kubectl apply -f 01-namespace.yaml
    kubectl apply -f 02-configmap.yaml
    kubectl apply -f 03-secret.yaml -n "$NAMESPACE"
    kubectl apply -f 04-postgres.yaml -n "$NAMESPACE"
    kubectl apply -f 05-redis.yaml -n "$NAMESPACE"
    kubectl apply -f 06-server-deployment.yaml -n "$NAMESPACE"
    kubectl apply -f 07-frontend-deployment.yaml -n "$NAMESPACE"
fi

# 等待就绪
echo ""
echo "⏳ 等待服务就绪..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=testagent -n "$NAMESPACE" --timeout=180s || true

# 显示状态
echo ""
echo "📊 部署状态:"
kubectl get all -n "$NAMESPACE"

# 端口转发（如果不用 NodePort）
echo ""
echo "🌐 访问方式:"
echo ""
echo "方式 1 - 直接访问 (NodePort):"
echo "  前端: http://localhost:30080"
echo "  API:  http://localhost:30081"
echo ""
echo "方式 2 - 使用 kubectl port-forward:"
echo "  kubectl port-forward svc/testagent-frontend 8080:80 -n $NAMESPACE"
echo "  然后访问: http://localhost:8080"
echo ""

# 配置 hosts（可选）
echo "💡 提示: 如需使用自定义域名，请修改 /etc/hosts:"
echo "  echo '127.0.0.1 testagent.local api.testagent.local' | sudo tee -a /etc/hosts"
echo ""

# 显示日志命令
echo "📜 常用命令:"
echo "  查看日志:    kubectl logs -f deployment/testagent-server -n $NAMESPACE"
echo "  进入容器:    kubectl exec -it deployment/testagent-server -n $NAMESPACE -- /bin/sh"
echo "  删除部署:    kubectl delete namespace $NAMESPACE"
echo ""

echo -e "${GREEN}✅ 部署完成！${NC}"
echo ""
echo "🎯 下一步:"
echo "  1. 打开浏览器访问: http://localhost:30080"
echo "  2. 查看日志: kubectl logs -f deployment/testagent-server -n $NAMESPACE"
echo "  3. 有问题? 查看 WSL-DEPLOY.md 常见问题部分"
