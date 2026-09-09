# =============================================================================
# ShowDoc 统一 Docker 镜像（amd64 / arm64 / arm/v7）
#
# 默认基础镜像 webdevops/php-nginx:8.3-alpine 支持 amd64 + arm64。
# 需要 32 位 ARM(arm/v7) 等平台时，注入旧版基础镜像：
#   docker build --build-arg BASE_IMAGE=wordpress:php8.1 \
#                --build-arg IN_CHINA=true .
#
# 国内镜像：docker build --build-arg=IN_CHINA=true .
# =============================================================================

ARG BASE_IMAGE=webdevops/php-nginx:8.3-alpine
FROM ${BASE_IMAGE}

# ===== 构建参数 =====
# 注意：FROM 之前的 ARG 作用域仅限 FROM 行，此处需重新声明
ARG BASE_IMAGE=webdevops/php-nginx:8.3-alpine
ARG IN_CHINA=false
ARG TARGETVARIANT

# 环境变量
ENV SHOWDOC_DOCKER_VERSION=3.4.2
ENV IN_CHINA=${IN_CHINA}
ENV BASE_IMAGE=${BASE_IMAGE}
ENV TARGETVARIANT=${TARGETVARIANT}

WORKDIR /showdoc_data/html
COPY . .

# ---------- Office 导入转换器 anydoc（musl 静态，见 server/bin/VERSION） ----------
# 注意：.dockerignore 已排除 server/bin/*（防二进制被整包拷进 web 根），
# 但用 !server/bin/anydoc 反排除了本文件，所以这里仍可 COPY
COPY --chmod=755 server/bin/anydoc /usr/local/bin/anydoc

# 旧版基础镜像（wordpress:*，如 arm/v7）：代码需放入 apache 网站根目录 /var/www/html，
# 并提供 PHP 渲染 web/index.html 的入口，同时放宽权限以兼容历史行为。
# 注意：RUN 默认 /bin/sh（POSIX），须用 case 而非 [[ ]]
RUN case "$BASE_IMAGE" in \
        wordpress:*) \
            cp -R /showdoc_data/html/. /var/www/html/ && \
            rm -f /var/www/html/server/bin/anydoc && \
            echo "<?php echo file_get_contents('index.html'); ?>" > /var/www/html/web/index.php && \
            chmod -R 777 /var/www/html/ \
        ;; \
    esac

# ---------- 前端构建（web_src -> web/） ----------
# 在构建镜像时直接执行 npm run build，保证镜像内的 web/ 是最新代码产物，
# 避免依赖人工先 build 再 docker build。
# 注意：必须放在 COPY . . 之后（保证拿到 web_src 源码），且放在 RUN entrypoint.sh --build 之前
# （避免 entrypoint.sh --build 阶段安装的 npm 被本步骤的 install 干扰）。
# node_modules 与 package-lock.json 通过 .dockerignore 排除，强制在容器内重装。
# 基础镜像 webdevops/php-nginx:8.3-alpine 默认不含 nodejs，需要先 apk add。
# IN_CHINA=true 时使用阿里云镜像源加速。
RUN if [ "$IN_CHINA" = "true" ]; then \
        sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/' /etc/apk/repositories; \
        npm_config_registry=https://registry.npmmirror.com/; \
    fi && \
    apk add --no-cache nodejs npm && \
    if [ "$IN_CHINA" = "true" ]; then npm config set registry https://registry.npmmirror.com/; fi && \
    # 兼容 Windows 上大小写不敏感的导入：项目里大量文件写 `@/components/Message`，
    # 但实际目录是 `message`（小写）。Linux 严格区分大小写，构建前补一份大小写都能命中的副本。
    # 同时 message/index.ts 里 import './index.vue'（小写）但实际文件是 Index.vue，
    # 也补一份小写副本。
    if [ ! -d /showdoc_data/html/web_src/src/components/Message ] && [ -d /showdoc_data/html/web_src/src/components/message ]; then \
        cp -R /showdoc_data/html/web_src/src/components/message /showdoc_data/html/web_src/src/components/Message && \
        # message/index.ts 内部用 './index.vue' 引用，文件实际是 Index.vue。
        # 在两个目录都补小写副本，避免 Linux 大小写敏感导致解析失败。
        cp /showdoc_data/html/web_src/src/components/message/Index.vue /showdoc_data/html/web_src/src/components/message/index.vue && \
        cp /showdoc_data/html/web_src/src/components/Message/Index.vue /showdoc_data/html/web_src/src/components/Message/index.vue; \
    fi && \
    cd /showdoc_data/html/web_src && \
    npm install --no-audit --no-fund && \
    npm run build && \
    # 构建完成后清理：减小镜像体积，并避免 entrypoint 阶段 rsync 拖慢首次启动
    rm -rf /showdoc_data/html/web_src/node_modules \
           /showdoc_data/html/web_src/dist \
           /showdoc_data/html/web_src/src/components/Message \
           /showdoc_data/html/web_src/src/components/message/index.vue 2>/dev/null; \
    true

RUN bash entrypoint.sh --build

CMD ["bash", "entrypoint.sh"]
