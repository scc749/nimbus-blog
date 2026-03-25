# Nimbus Blog

Nimbus Blog 的聚合仓库：通过 Git Submodule 管理后端与前端代码，并在 `deploy/` 提供生产部署所需的 Dockerfile、Nginx 配置与基础设施脚本。

仓库地址：`git@github.com:scc749/nimbus-blog.git`

## 概览

- 后端：Go + Fiber，详细见 https://github.com/scc749/nimbus-blog-api/blob/main/README.md
- 前端：Next.js App Router，详细见 https://github.com/scc749/nimbus-blog-web/blob/main/README.md
- 部署：推荐同域名反代（`/api/*` → 后端，站点根路径 → 前端），相关文件在 `deploy/`

## 仓库结构

- `nimbus-blog-api/`：后端子模块（跟踪 `main` 分支）
- `nimbus-blog-web/`：前端子模块（跟踪 `main` 分支）
- `deploy/`
  - `deploy/backend/Dockerfile`：后端镜像构建
  - `deploy/nginx/nimbus-blog.conf`：Nginx 反向代理示例
  - `deploy/infra/docker-run.sh`：PostgreSQL/Redis/MinIO 启动脚本（持久化）

## 子模块

### Clone（推荐）

```bash
git clone --recurse-submodules git@github.com:scc749/nimbus-blog.git
```

### 同步到主仓库锁定版本

```bash
git pull --recurse-submodules
git submodule update --init --recursive
```

### 初始化（已 clone 的情况下）

```bash
git submodule update --init --recursive
```

### 更新到远端 main 最新提交

主仓库记录的是“子模块指针”（具体 commit），因此更新后需要在主仓库提交一次变更。

```bash
git submodule update --remote --recursive
git status
```

## 本地开发

本仓库仅负责聚合与部署入口；开发请直接按子模块 README 操作：

- 后端本地开发：https://github.com/scc749/nimbus-blog-api/blob/main/README.md
- 前端本地开发：https://github.com/scc749/nimbus-blog-web/blob/main/README.md

## 生产部署（Ubuntu + Docker + Nginx 同域）

### 部署文件

- 后端镜像构建：[deploy/backend/Dockerfile](deploy/backend/Dockerfile)
- Nginx 配置示例：[deploy/nginx/nimbus-blog.conf](deploy/nginx/nimbus-blog.conf)
- 基础设施启动脚本：[deploy/infra/docker-run.sh](deploy/infra/docker-run.sh)

### 服务器目录与文件约定

```text
/srv/nimbus/                       # 仓库根目录（上传）
  nimbus-blog-api/                 # 后端子模块
    config.yaml                    # 迁移专用配置：仅包含 PostgreSQL（host=localhost）
    migrations/                    # 迁移 SQL
    dist/                          # 上传的二进制（如 dist/nimbus-blog-api、dist/migrate）
  nimbus-blog-web/                 # 前端子模块
  deploy/                          # 部署文件
    backend/Dockerfile
    nginx/nimbus-blog.conf
    infra/docker-run.sh

/etc/nimbus/config.yaml            # 后端容器运行时读取的生产配置（宿主机）

/srv/postgres                      # PostgreSQL 持久化目录（宿主机）
/srv/redis/data                    # Redis 持久化目录（宿主机）
/srv/minio/data                    # MinIO 持久化目录（宿主机）
```

### 部署流程（总览）

1. 安装 Docker 与 Nginx，准备目录与网络
2. 启动 PostgreSQL/Redis/MinIO（持久化）
3. 准备后端生产配置 `/etc/nimbus/config.yaml`（容器互联使用容器名）
4. 执行数据库迁移（依赖 `config.yaml` 与 `migrations/`）
5. 构建并运行后端容器（加入 `nimbus-net`，对外暴露 8080）
6. 部署前端（建议在服务器安装依赖并用 PM2 启动）
7. 配置 Nginx 反代为同域并验证访问

<details>
<summary>展开：部署详细步骤</summary>

### 步骤 1：安装 Docker 与 Nginx

```bash
sudo apt update
sudo apt install -y docker.io nginx
```

### 步骤 2：启动 PostgreSQL / Redis / MinIO（持久化）

```bash
sudo mkdir -p /srv/postgres /srv/redis/data /srv/minio/data
sudo docker network inspect nimbus-net >/dev/null 2>&1 || sudo docker network create nimbus-net
chmod +x deploy/infra/docker-run.sh
sudo ./deploy/infra/docker-run.sh
```

### 步骤 3：准备后端配置（生产）

生产配置放到：`/etc/nimbus/config.yaml`。

后端在容器内运行时，不能用 `localhost` 访问其他容器，请使用容器名：

```yaml
postgres:
  host: postgres
  port: 5432
redis:
  host: redis
  port: 6379
minio:
  endpoint: minio-server:9000
  use_ssl: false
```

文件存储对外访问地址（`file_storage.public_base_url`）：
- 生产环境使用 MinIO 同域反代：配置为 `https://<服务器域名>/minio`
- 使用自定义存储域名（CDN/对象存储网关域名）：配置为对应的自定义域名

示例：

```yaml
file_storage:
  provider: minio
  public_base_url: https://<服务器域名>/minio
```

### 步骤 4：执行数据库迁移（生产）

迁移程序依赖两样东西：

- `config.yaml`：迁移程序运行时从当前工作目录读取
- `migrations/`：迁移 SQL 目录

因此在服务器上建议准备目录：`/srv/nimbus/nimbus-blog-api/`，保证该目录下同时存在 `config.yaml` 与 `migrations/`，并在该目录执行迁移命令。

`config.yaml` 示例（仅展示迁移所需的最小连接配置，可按需补全）：

```yaml
postgres:
  host: localhost
  port: 5432
  user: user
  password: myp455w0rd
  dbname: blog_db
  sslmode: disable
  time_zone: Asia/Shanghai
  max_idle_conns: 10
  max_open_conns: 100
```

先准备迁移程序（生成 `dist/migrate`），再执行迁移。

#### 4.1) 准备迁移程序（Windows 编译并上传）

```cmd
set GOOS=linux
set GOARCH=amd64
set CGO_ENABLED=0
cd nimbus-blog-api
mkdir dist
go build -o dist\migrate .\cmd\migrate
```

上传到服务器：

- 上传 `dist/migrate` 到 `/srv/nimbus/nimbus-blog-api/dist/`
- 确保服务器目录 `/srv/nimbus/nimbus-blog-api/` 下存在 `config.yaml` 与 `migrations/`

#### 4.2) 执行迁移

在目录 `/srv/nimbus/nimbus-blog-api/` 执行迁移：

```bash
chmod +x ./dist/migrate
./dist/migrate
```

其中：

- `./dist/migrate` 等价于 `./dist/migrate -dir migrations -action up`
- 查看当前版本：

```bash
./dist/migrate -dir migrations -action version
```

其它操作（按需）：

```bash
# 回滚最近 N 步
./dist/migrate -dir migrations -action steps -steps 1
# 全部回滚（谨慎）
./dist/migrate -dir migrations -action down
# 强制设置版本（修复脏迁移）
./dist/migrate -dir migrations -action force -to 1761272640
# 丢弃全部（危险操作）
./dist/migrate -dir migrations -action drop
```

### 步骤 5：构建并运行后端容器

后端镜像构建依赖二进制文件：`nimbus-blog-api/dist/nimbus-blog-api`（见 `deploy/backend/Dockerfile` 的 `COPY` 指令）。

#### 5.1) 准备后端程序（Windows 编译并上传）

```cmd
set GOOS=linux
set GOARCH=amd64
set CGO_ENABLED=0
cd nimbus-blog-api
mkdir dist
go build -o dist\nimbus-blog-api .\cmd\app
```

上传到服务器：

- 上传 `dist/nimbus-blog-api` 到 `/srv/nimbus/nimbus-blog-api/dist/`

#### 5.2) 构建并运行后端容器

构建镜像（在 `/srv/nimbus` 仓库根执行）：

```bash
sudo docker build -f deploy/backend/Dockerfile -t nimbus-blog-api:latest .
```

运行后端：

```bash
sudo docker run -d --name nimbus-api \
  --network nimbus-net \
  -p 8080:8080 --restart=always \
  -v /etc/nimbus/config.yaml:/app/config.yaml:ro \
  nimbus-blog-api:latest
```

如果需要修改后端配置文件：直接在服务器上编辑 `/etc/nimbus/config.yaml`，保存后执行下面命令重启后端容器生效：

```bash
sudo docker restart nimbus-api
```

### 步骤 6：前端构建与启动（SSR）

服务器首次安装（Node.js 20 + pnpm + PM2）：

```bash
sudo apt update
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
sudo npm install -g pnpm pm2
```

Windows 预构建并上传：

在 Windows 构建：

```cmd
cd nimbus-blog-web
pnpm install
```

并将 `.env.local` 里的 `NEXT_PUBLIC_API_BASE=http://localhost:8080` 改成 `https://<你的域名>`

```cmd
pnpm build
```

上传到服务器 `nimbus-blog-web/`：`.next`、`public`、`package.json`、`pnpm-lock.yaml`

在服务器安装依赖并启动前端（在 `nimbus-blog-web/` 内执行）：

```bash
cd /srv/nimbus/nimbus-blog-web
pnpm install --prod --frozen-lockfile
pm2 start pnpm --name nimbus-web -- start
pm2 save
pm2 startup systemd -u root --hp /root
```

更新前端产物后（例如重新构建并同步到服务器），重载：

```bash
pm2 reload nimbus-web
```

前端环境变量与构建要求见：https://github.com/scc749/nimbus-blog-web/blob/main/README.md

### 步骤 7：配置 Nginx 反向代理（同域 HTTPS）

- 拷贝配置文件：

```bash
sudo cp deploy/nginx/nimbus-blog.conf /etc/nginx/sites-available/nimbus-blog.conf
sudo ln -s /etc/nginx/sites-available/nimbus-blog.conf /etc/nginx/sites-enabled/nimbus-blog.conf
```

- 编辑替换 `SERVER_NAME`、`SSL_CERT_PATH`、`SSL_KEY_PATH` 为你的域名与证书路径（如 Let’s Encrypt）
- 检查并重载：

```bash
sudo nginx -t
sudo systemctl reload nginx
```

- 端口映射（Nginx 反代）：
  - `/` → 前端 `http://127.0.0.1:3000`
  - `/api/` → 后端 `http://127.0.0.1:8080`

</details>
