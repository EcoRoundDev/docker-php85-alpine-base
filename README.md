# docker-php85-alpine-base

[Laravel Octane](https://laravel.com/docs/octane)（Swoole）生产用 PHP 8.5 运行时镜像。
只包含运行时，**不含** composer / git / 编译器 / 包管理器工具链。

- 基础镜像：`php:8.5.12-cli-alpine3.24`（digest 固定）
- 体积：约 141 MB
- 用户：`nobody`（uid/gid 65534），非 root
- 标签：`writing/php85-alpine-base:8.5.12-alpine3.24`、`latest`

## 包含的扩展

| 类型 | 扩展 |
| --- | --- |
| 编译 | `bcmath exif gd gmp intl pcntl pdo_mysql sockets zip` |
| PECL | `swoole-6.2.6`、`redis-6.3.0` |
| 官方镜像内置 | `curl dom mbstring openssl sodium sqlite3 xml zlib fileinfo ctype iconv opcache posix xmlreader xmlwriter` |

**不安装**：`imagick`、`mysqli`、`bz2`、`ldap/odbc/pgsql/snmp/soap/tidy/xsl/ftp`。项目未使用，减少体积与 CVE 面。
若后续需要，在 `builder` 阶段加 `docker-php-ext-install` 或 `pecl install`，并把对应运行时库加进 runtime 阶段的 `apk add`。

## php.ini 安全基线

`php.ini` 会被 COPY 为 `/usr/local/etc/php/conf.d/zzz_custom.ini`（以 zzz 开头，保证最后加载）。

| 指令 | 值 |
| --- | --- |
| `expose_php` / `display_errors` | `Off` |
| `log_errors` / `error_log` | `On` / `/dev/stderr` |
| `memory_limit` | `512M` |
| `date.timezone` | `Asia/Shanghai` |
| `opcache.enable_cli` | `1`（Octane 是 CLI 常驻进程，不开等于没开 opcache） |
| `opcache.validate_timestamps` | `0`（**改代码必须重建镜像**） |
| `allow_url_fopen` / `allow_url_include` | `Off` / `Off` |
| `swoole.use_shortname` | `Off` |
| `disable_functions` | `shell_exec,system,passthru,popen,phpinfo` |

> **不要禁用 `exec`**：Octane 停机时 `vendor/laravel/octane/src/Exec.php` 用 `exec('pgrep -P ...')` 找子进程，
> 禁用后 `SIGTERM` 阶段会抛 `Call to undefined function Laravel\Octane\exec()`，进程无法优雅退出。

## 构建

```sh
docker build -t writing/php85-alpine-base:8.5.12-alpine3.24 .
```

> 本机 Docker Desktop 会注入不可达的代理（`127.0.0.1:2888`），导致 `apk` 报 Connection refused。
> 本地构建时追加：
> `--build-arg http_proxy= --build-arg https_proxy= --build-arg HTTP_PROXY= --build-arg HTTPS_PROXY= --build-arg no_proxy= --build-arg NO_PROXY=`
> 若 BuildKit 写 buildx 活动目录报 `operation not permitted`，改用 `DOCKER_BUILDKIT=0`。

## 验证

```sh
# 扩展齐备
docker run --rm writing/php85-alpine-base:8.5.12-alpine3.24 php -m

# 非 root
docker run --rm writing/php85-alpine-base:8.5.12-alpine3.24 id

# 安全基线生效（应输出完整 disable_functions 列表，空则说明 ini 未被加载）
docker run --rm writing/php85-alpine-base:8.5.12-alpine3.24 php -r 'echo ini_get("disable_functions"), PHP_EOL;'

# 漏洞扫描
trivy image --severity HIGH,CRITICAL writing/php85-alpine-base:8.5.12-alpine3.24
```

## 在项目中使用

```dockerfile
FROM writing/php85-alpine-base:8.5.12-alpine3.24
```

注意：

1. 镜像默认 `USER nobody`。多阶段构建中若要在该镜像上 `COPY`/`chown`/`composer install`，需先显式 `USER root`，结束前再切回 `USER nobody`。
2. 源码中权限为 `600` 的文件以 `nobody` 运行时读不到，构建期需 `chmod -R a+rX`。
3. 镜像不含 composer，项目侧用 `COPY --from=composer:2 /usr/bin/composer` 引入二进制。
4. Octane 驱动需显式设置 `OCTANE_SERVER=swoole`（Laravel Octane 默认是 roadrunner）。

## 发布

`.github/workflows/build.yml` 在 push 到 `main`（或手动触发）时构建并推送 `linux/amd64` 镜像到 Docker Hub。
需要在仓库 Secrets 配置：

| Secret | 说明 |
| --- | --- |
| `DOCKERHUB_USERNAME` | Docker Hub 用户名 |
| `DOCKERHUB_TOKEN` | Docker Hub Access Token（非密码） |

## 升级流程

1. 改 `Dockerfile` 的 `ARG PHP_IMAGE` / `ARG PHP_DIGEST`：
   `docker buildx imagetools inspect php:8.5.x-cli-alpine3.24` 取新 digest。
2. 按需改 `pecl install swoole-x.y.z redis-x.y.z`，确认 [Swoole 支持的 PHP 版本矩阵](https://github.com/swoole/swoole-src/blob/master/SUPPORTED.md)。
3. 本地构建并跑上面「验证」四条。
4. 推新 tag；项目侧同步改 `ARG BASE_IMAGE`。

## 设计文档

完整设计、风险清单与实测记录见项目仓库 `docs/php85-docker-image-design.md`。
