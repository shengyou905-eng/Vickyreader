#!/bin/bash
# 知读 阅读器后端一键部署脚本
# 用法: chmod +x deploy.sh && ./deploy.sh

set -e

echo "=== 知读 后端部署 ==="

# 检测系统
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$ID
else
  OS="unknown"
fi

# 安装 Node.js（如未安装）
if ! command -v node &>/dev/null; then
  echo ">> 安装 Node.js 20.x..."
  if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
  elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ]; then
    curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
    sudo yum install -y nodejs
  else
    echo "不支持的系统，请手动安装 Node.js: https://nodejs.org"
    exit 1
  fi
fi

echo ">> Node.js $(node -v)"

# 安装 PM2（全局进程守护）
if ! command -v pm2 &>/dev/null; then
  echo ">> 安装 PM2..."
  sudo npm install -g pm2
fi

# 安装依赖
echo ">> 安装项目依赖..."
cd "$(dirname "$0")"
npm install --production

# 创建 .env（如果不存在）
if [ ! -f .env ]; then
  cp .env.example .env
  # 自动生成 JWT_SECRET
  if command -v openssl &>/dev/null; then
    sed -i "s/change-me-to-a-random-64-char-string/$(openssl rand -hex 32)/" .env
  fi
  echo ">> .env 已创建，JWT_SECRET 已随机生成"
fi

# 创建数据目录
mkdir -p data

# 启动服务
echo ">> 启动后端服务..."
pm2 delete reader-backend 2>/dev/null || true
pm2 start server.js --name reader-backend --cwd "$(pwd)"

# 开机自启
pm2 save
sudo env PATH=$PATH pm2 startup systemd -u $(whoami) --hp $HOME 2>/dev/null || true

# 检查
sleep 2
if curl -s http://localhost:3000/api/health | grep -q ok; then
  echo ""
  echo "========================================"
  echo "  部署成功！后端运行在端口 3000"
  echo "  健康检查: http://$(hostname -I | awk '{print $1}'):3000/api/health"
  echo "  查看日志: pm2 logs reader-backend"
  echo "========================================"
else
  echo "⚠ 健康检查失败，请查看日志: pm2 logs reader-backend"
fi
