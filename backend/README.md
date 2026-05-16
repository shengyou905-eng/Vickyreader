# 知读 后端

## API 清单

| 方法 | 路径 | 鉴权 | 说明 |
|------|------|------|------|
| GET | `/api/health` | 无 | 健康检查 |
| POST | `/api/register` | 无 | 邮箱注册（限流 20次/15分钟） |
| POST | `/api/login` | 无 | 邮箱登录（限流 20次/15分钟） |
| GET | `/api/classes/:table` | Bearer | 查询数据（where/order/limit） |
| POST | `/api/classes/:table` | Bearer | 新增数据 |
| GET | `/api/classes/:table/:id` | Bearer | 查单条 |
| PUT | `/api/classes/:table/:id` | Bearer | 更新数据 |
| DELETE | `/api/classes/:table/:id` | Bearer | 删除数据 |
| POST | `/api/chunk` | Bearer | 文本切片 |
| GET | `/api/cache` | Bearer | 查询 AI 缓存 |
| POST | `/api/cache` | Bearer | 写入 AI 缓存 |

## 已实现功能

- ✅ JWT 用户鉴权（bcrypt 密码哈希）
- ✅ 环境变量配置（dotenv + .env.example）
- ✅ 请求日志（morgan）
- ✅ 登录/注册限流（express-rate-limit）
- ✅ AI 缓存（in-memory，1 小时 TTL）
- ✅ 文本切片 API
- ✅ CORS 跨域
- ✅ 部署脚本（deploy.sh + PM2）
- ✅ Nginx HTTPS 反向代理模板

## 快速开始

```bash
# 1. 配置环境变量
cp .env.example .env
# 编辑 .env，修改 JWT_SECRET 为随机字符串

# 2. 安装运行
npm install
npm start
```

## 部署到服务器

```bash
scp -r backend/ root@你的服务器IP:/opt/reader-backend
ssh root@你的服务器IP
cd /opt/reader-backend
chmod +x deploy.sh && ./deploy.sh
```

## 配置 HTTPS

1. 安装 nginx + certbot
2. 将 `nginx.conf` 中的 `YOUR_DOMAIN` 替换为你的域名
3. `cp nginx.conf /etc/nginx/sites-available/reader && ln -s ...`
4. `certbot --nginx -d YOUR_DOMAIN`
5. 更新 Flutter 端 `constants.dart` → `apiBaseUrl = 'https://YOUR_DOMAIN'`

## 你需要准备的

| 事项 | 说明 |
|------|------|
| 云服务器 | 1 核 1G 即可，开放 80/443/3000 端口 |
| 域名 | 已备案（如使用国内服务器） |
| SSL 证书 | certbot 自动申请（免费） |
