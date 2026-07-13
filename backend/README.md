# 知读后端

第一阶段后端地基：Node.js + Express + PostgreSQL + JWT + bcrypt。

暂不实现 embedding、RAG、思维导图、小U对话。

## 文件结构

```txt
backend/
  package.json
  .env.example
  server.js
  src/
    app.js
    server.js
    config/
      db.js
      env.js
    controllers/
      auth.controller.js
      entries.controller.js
    db/
      init.js
      schema.sql
    middleware/
      auth.js
      errorHandler.js
    repositories/
      entry.repository.js
      user.repository.js
    routes/
      auth.routes.js
      entries.routes.js
    utils/
      httpError.js
```

## 安装依赖

PowerShell 可能会拦截 `npm.ps1`，推荐使用：

```powershell
cd C:\Users\29319\Desktop\reader\backend
npm.cmd install
```

如果 npm 默认缓存目录没有权限，可以使用工作区缓存：

```powershell
npm.cmd install --cache .\.npm-cache
```

## PostgreSQL 安装步骤

### Windows 图形安装

1. 打开 PostgreSQL 官网下载安装包：https://www.postgresql.org/download/windows/
2. 安装 PostgreSQL 16 或 17。
3. 安装时记住 `postgres` 用户密码。
4. 保持默认端口 `5432`。
5. 安装完成后打开 pgAdmin 或 SQL Shell。

### 创建数据库

在 SQL Shell 或 pgAdmin 中执行：

```sql
CREATE DATABASE reader;
```

如果使用命令行：

```powershell
psql -U postgres -c "CREATE DATABASE reader;"
```

## .env 示例

复制 `.env.example` 为 `.env`：

```powershell
copy .env.example .env
```

示例内容：

```env
PORT=3000
HOST=127.0.0.1
NODE_ENV=development

JWT_SECRET=replace-with-a-long-random-secret
JWT_EXPIRES_IN=7d

DATABASE_URL=postgres://postgres:postgres@localhost:5432/reader
CORS_ORIGIN=http://localhost:3000
```

把 `DATABASE_URL` 中第二个 `postgres` 改成你安装 PostgreSQL 时设置的密码。

`JWT_SECRET` 请换成足够长的随机字符串。

## 初始化数据库表

后端启动时会自动执行 `src/db/schema.sql` 创建表。也可以手动执行：

```powershell
npm.cmd run db:init
```

会创建：

- `users`
- `user_entries`

## 启动后端

```powershell
cd C:\Users\29319\Desktop\reader\backend
npm.cmd start
```

开发模式：

```powershell
npm.cmd run dev
```

启动成功后访问：

```txt
http://localhost:3000/api/health
```

返回：

```json
{
  "status": "ok",
  "env": "development"
}
```

## API 设计

### 注册

```http
POST /api/auth/register
Content-Type: application/json
```

```json
{
  "email": "a@example.com",
  "password": "123456"
}
```

返回：

```json
{
  "user": {
    "id": "uuid",
    "email": "a@example.com",
    "created_at": "...",
    "updated_at": "..."
  },
  "token": "jwt"
}
```

### 登录

```http
POST /api/auth/login
Content-Type: application/json
```

```json
{
  "email": "a@example.com",
  "password": "123456"
}
```

返回同注册。

### 创建 user_entry

```http
POST /api/entries
Authorization: Bearer <token>
Content-Type: application/json
```

```json
{
  "source": "highlight",
  "book_id": "book-001",
  "book_title": "局外人",
  "chapter_index": "1",
  "chapter_title": "第一章",
  "original_text": "今天，妈妈死了。",
  "user_input": "",
  "ai_explanation": "",
  "auto_tags": ["划线"],
  "auto_summary": "",
  "metadata_json": {
    "color": "#B39DDB"
  }
}
```

说明：

- `source` 只允许 `highlight`、`thought`、`ai_explanation`、`manual`
- `user_id` 不从请求体读取，永远来自当前 JWT

### 查询自己的 entries

```http
GET /api/entries
Authorization: Bearer <token>
```

支持筛选：

```txt
GET /api/entries?book_id=book-001
GET /api/entries?source=highlight
GET /api/entries?tag=划线
GET /api/entries?created_at_from=2026-05-01&created_at_to=2026-05-16
```

返回：

```json
{
  "entries": []
}
```

## curl 测试

### 1. 健康检查

```powershell
curl.exe http://localhost:3000/api/health
```

### 2. 注册用户 A

```powershell
curl.exe -X POST http://localhost:3000/api/auth/register `
  -H "Content-Type: application/json" `
  -d "{\"email\":\"a@example.com\",\"password\":\"123456\"}"
```

复制返回里的 `token`。

### 3. 登录用户 A

```powershell
curl.exe -X POST http://localhost:3000/api/auth/login `
  -H "Content-Type: application/json" `
  -d "{\"email\":\"a@example.com\",\"password\":\"123456\"}"
```

### 4. 不带 token 访问 entries

```powershell
curl.exe http://localhost:3000/api/entries
```

预期返回 `401 Unauthorized`。

### 5. 带 token 创建 entry

```powershell
curl.exe -X POST http://localhost:3000/api/entries `
  -H "Content-Type: application/json" `
  -H "Authorization: Bearer <A_TOKEN>" `
  -d "{\"source\":\"highlight\",\"book_id\":\"book-001\",\"book_title\":\"局外人\",\"original_text\":\"今天，妈妈死了。\",\"auto_tags\":[\"划线\"],\"metadata_json\":{\"color\":\"#B39DDB\"}}"
```

### 6. 查询用户 A 的 entries

```powershell
curl.exe http://localhost:3000/api/entries `
  -H "Authorization: Bearer <A_TOKEN>"
```

### 7. 验证 A/B 用户隔离

注册或登录用户 B：

```powershell
curl.exe -X POST http://localhost:3000/api/auth/register `
  -H "Content-Type: application/json" `
  -d "{\"email\":\"b@example.com\",\"password\":\"123456\"}"
```

用 B 的 token 查询：

```powershell
curl.exe http://localhost:3000/api/entries `
  -H "Authorization: Bearer <B_TOKEN>"
```

预期看不到用户 A 创建的 entry。

## Postman 测试方式

1. 创建 `POST http://localhost:3000/api/auth/register`
2. Body 选择 raw JSON，填入 email/password
3. 从响应中复制 `token`
4. 创建 `POST http://localhost:3000/api/entries`
5. Authorization 选择 Bearer Token，填入 token
6. Body 填入 entry JSON
7. 创建 `GET http://localhost:3000/api/entries`
8. Authorization 填同一个 token，确认能看到自己的数据
9. 换另一个用户 token，确认看不到前一个用户的数据

## 确认 JWT 生效

JWT 生效的判断：

- 不带 `Authorization` 请求 `/api/entries` 返回 `401`
- `Authorization: Bearer <错误 token>` 返回 `401`
- `Authorization: Bearer <正确 token>` 可以创建和查询 entries
- A 用户 token 查询不到 B 用户数据，B 用户 token 查询不到 A 用户数据
## 隐私与社区治理

- DeepSeek Key 只配置在服务器 `.env` 的 `DEEPSEEK_API_KEY`。
- `POST /api/ai/chat` 与 `POST /api/ai/explain` 要求用户先完成
  `POST /api/auth/ai-consent`。
- `POST /api/auth/logout` 会撤销该账号现有 JWT；默认有效期为 7 天。
- `DELETE /api/auth/account` 需要当前密码，并删除账号关联云端数据。
- 明台帖子和评论要求先接受 `/api/mingtai/community/guidelines` 返回的当前规范。
- 举报入口：`POST /api/mingtai/community/reports`。
- 拉黑入口：`POST /api/mingtai/community/profiles/:userId/block`。
- 管理员举报队列：`GET /api/mingtai/community/admin/reports`。
- 管理员治理动作：`POST /api/mingtai/community/admin/moderate`。

授予管理员权限：

```bash
npm run admin:grant -- 2931952407@qq.com
```

每日 PostgreSQL 备份：

```bash
chmod +x scripts/backup-postgres.sh scripts/install-backup-cron.sh
sudo ./scripts/install-backup-cron.sh
```

备份默认每天 03:15 写入 `/home/ubuntu/backups/zhidu/daily`，保留 14 天，
每次备份都会使用 `pg_restore -l` 做可读性校验。

生产环境保持 `HOST=127.0.0.1`，只通过 Nginx 暴露 HTTPS API。不要把
Node 的 `3000` 端口或 PostgreSQL 的 `5432` 端口直接暴露到公网。
