# ============================================================
# writing/php85-alpine-base —— PHP 8.5 生产运行镜像
# 设计依据：docs/php85-docker-image-design.md 第 4 节
#
# 只含运行时：无 composer / git / 编译器 / 包管理器工具链。
# 构建：docker build -t writing/php85-alpine-base:8.5.12-alpine3.24 .
# CI：.github/workflows/build.yml 在 push 到 main 时构建并推送 latest + 版本 tag
# ============================================================
ARG PHP_IMAGE=php:8.5.12-cli-alpine3.24
ARG PHP_DIGEST=sha256:1ff5b45922ab30f418447c6089dbe2eba5f01e0b2742863d0327ac349305d70f

########## builder：编译扩展 ##########
FROM ${PHP_IMAGE}@${PHP_DIGEST} AS builder

# 编译期依赖：$PHPIZE_DEPS 已含 autoconf/automake/libtool/make/gcc/g++
RUN apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS pkgconf linux-headers \
        brotli-dev bzip2-dev freetype-dev gmp-dev icu-dev \
        libjpeg-turbo-dev libpng-dev libxml2-dev libzip-dev openssl-dev zlib-dev \
 && docker-php-ext-configure gd --with-freetype --with-jpeg \
 && docker-php-ext-install -j"$(nproc)" \
        bcmath exif gd gmp intl pcntl pdo_mysql sockets zip

# PECL：swoole 6.2.6 的配置项全部是 PHP_ARG_ENABLE，无交互提示。
# 坑 1：swoole configure 必定探测 libssl，缺 openssl-dev + pkgconf 会失败：
#       configure: error: Package requirements (libssl) were not met
# 坑 2：pecl 产物带调试符号，swoole.so 未 strip 时约 49MB，必须 strip
RUN apk add --no-cache binutils \
 && pecl install swoole-6.2.6 redis-6.3.0 \
 && docker-php-ext-enable swoole redis \
 && find /usr/local/lib/php/extensions -name '*.so' -exec strip --strip-unneeded {} \;

########## runtime：最小运行面 ##########
FROM ${PHP_IMAGE}@${PHP_DIGEST}

# 仅运行时库（无 -dev），并设为上海时区
RUN apk add --no-cache \
        freetype libjpeg-turbo libpng brotli-libs libbz2 gmp icu-libs \
        libgcc libstdc++ libzip xz-libs zstd-libs tzdata \
 && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
 && echo 'Asia/Shanghai' > /etc/timezone

COPY --from=builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=builder /usr/local/etc/php/conf.d/ /usr/local/etc/php/conf.d/

# 生产安全基线
# 官方 cli-alpine 镜像不带 php.ini（只有 php.ini-production），先补上作为完整默认值
RUN cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" \
 && sed -i 's/^memory_limit = .*/memory_limit = 512M/' "$PHP_INI_DIR/php.ini"
COPY php.ini /usr/local/etc/php/conf.d/zzz_custom.ini
# 宿主文件权限可能是 600，nobody 读不到会导致整份 ini 被静默跳过（实测踩过）
RUN chmod 0644 /usr/local/etc/php/conf.d/zzz_custom.ini

# 非 root：沿用 alpine 内置 nobody（uid/gid 65534）
RUN mkdir -p /var/www/html \
 && chown -R nobody:nobody /var/www/html

ENV TZ=Asia/Shanghai

USER nobody
WORKDIR /var/www/html
EXPOSE 8000
