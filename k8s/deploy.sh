#!/bin/bash

# TestAgent Kubernetes 部署脚本
# 用法: ./deploy.sh [环境]

set -e

ENV=${1:-prod}
NAMESPACE="testagent"

echo "🚀 TestAgent K8s 部署开始..."
echo "环境: $ENV"
echo ""

# 检查依赖
echo "📋 检查依赖..."
command -v kubectl >/dev/null 2>&1 || { echo "❌ kubectl 未安装"; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "❌ docker 未安装"; exit 1; }

# 检查集群连接
echo "🔗 检查 K8s 集群连接..."
kubectl cluster-info || { echo "❌ 无法连接到 K8s 集群"; exit 1; }

# 设置镜像标签
TAG=${2:-latest}
REGISTRY=${DOCKER_REGISTRY:-"your-registry.com"}
FRONTEND_IMAGE="$REGISTRY/testagent-frontend:$TAG"
SERVER_IMAGE="$REGISTRY/testagent-server:$TAG"

echo ""
echo "📦 镜像信息:"
echo "  Frontend: $FRONTEND_IMAGE"
echo "  Server: $SERVER_IMAGE"
echo ""

# 构建镜像（如果需要）
if [ "$BUILD" = "true" ]; then
    echo "🔨 构建 Docker 镜像..."
    
    # 构建前端
    echo "  构建 frontend..."
    docker build -f frontend-Dockerfile -t $FRONTEND_IMAGE ../Client
    docker push $FRONTEND_IMAGE
    
    # 构建后端
    echo "  构建 server..."
    cd ../Client/server
    npm run build
    cd ../../k8s
    docker build -f server-Dockerfile -t $SERVER_IMAGE ../Client
    docker push $SERVER_IMAGE
fi

# 应用配置
echo ""
echo "📋 应用 K8s 资源配置..."

echo "  创建 Namespace..."
kubectl apply -f 01-namespace.yaml

echo "  应用 ConfigMap..."
kubectl apply -f 02-configmap.yaml

echo "  应用 Secret..."
kubectl apply -f 03-secret.yaml

echo "  部署 PostgreSQL..."
kubectl apply -f 04-postgres.yaml

echo "  部署 Redis..."
kubectl apply -f 05-redis.yaml

echo "  部署 Server..."
kubectl apply -f 06-server-deployment.yaml

echo "  部署 Frontend..."
kubectl apply -f 07-frontend-deployment.yaml

echo "  应用 Ingress..."
kubectl apply -f 08-ingress.yaml

echo "  应用 HPA..."
kubectl apply -f 09-hpa.yaml

echo ""
echo "⏳ 等待服务就绪..."
kubectl wait --for=condition=ready pod -l app=postgres -n $NAMESPACE --timeout=120s || true
kubectl wait --for=condition=ready pod -l app=redis -n $NAMESPACE --timeout=60s || true
kubectl wait --for=condition=ready pod -l app=testagent-server -n $NAMESPACE --timeout=120s || true
kubectl wait --for=condition=ready pod -l app=testagent-frontend -n $NAMESPACE --timeout=60s || true

echo ""
echo "✅ 部署完成!"
echo ""
echo "📊 查看状态:"
echo "  kubectl get all -n $NAMESPACE"
echo ""
echo "📜 查看日志:"
echo "  kubectl logs -f deployment/testagent-server -n $NAMESPACE"
echo ""
echo "🌐 访问地址:"
echo "  Frontend: https://testagent.yourdomain.com"
echo "  API: https://api.testagent.yourdomain.com"
