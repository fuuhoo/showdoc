# 阿里云镜像仓库推送说明

本 workflow 在你 push 形如 `v*.*.*` 的 tag 时自动触发，会构建多平台镜像（linux/amd64 + linux/arm64）并推送到阿里云容器镜像仓库。

## 完整镜像地址

```
registry.cn-qingdao.aliyuncs.com/fubin/showdoc:latest
registry.cn-qingdao.aliyuncs.com/fubin/showdoc:vX.Y.Z
```

例如打 tag `v1.2.3` 后会同时推送：

- `registry.cn-qingdao.aliyuncs.com/fubin/showdoc:latest`
- `registry.cn-qingdao.aliyuncs.com/fubin/showdoc:v1.2.3`

## 一次性配置（GitHub Secrets）

进入仓库 `Settings -> Secrets and variables -> Actions -> New repository secret`，添加两个 secret：

| Secret 名 | 值 | 说明 |
| --- | --- | --- |
| `ALIYUN_REGISTRY_USERNAME` | 阿里云账号用户名（一般是邮箱或 RAM 子账号） | 阿里云镜像仓库登录用户名 |
| `ALIYUN_REGISTRY_PASSWORD` | 阿里云镜像仓库的独立密码 | **不是阿里云账号登录密码**。在阿里云控制台 `容器镜像服务 -> 个人实例 -> 访问凭证 -> 设置固定密码` 设置 |

## 使用步骤

### 1. 在阿里云创建命名空间和镜像仓库

首次推送前，请先在阿里云容器镜像服务控制台创建：

- 命名空间：`fubin`（若已存在可跳过）
- 镜像仓库：`showdoc`（地域选择 `cn-qingdao`，若已存在可跳过）
  - 代码源：本地仓库
  - 访问权限：私有（推荐）

### 2. 在 GitHub 配置 Secrets

按上表添加两个 secret。

### 3. 推送 tag 触发构建

```bash
git tag v1.0.0
git push origin v1.0.0
```

push tag 后到 `Actions` 页面查看构建进度，构建成功后即可在阿里云镜像仓库看到镜像。

### 4. 拉取镜像

```bash
docker login --username=<阿里云用户名> registry.cn-qingdao.aliyuncs.com
docker pull registry.cn-qingdao.aliyuncs.com/fubin/showdoc:latest
docker run -d --name showdoc -p 4999:80 registry.cn-qingdao.aliyuncs.com/fubin/showdoc:latest
```

## 常见问题

- **报错 `unauthorized: authentication required`**：检查 `ALIYUN_REGISTRY_USERNAME` / `ALIYUN_REGISTRY_PASSWORD` 是否正确。注意密码是阿里云镜像仓库的**独立密码**，不是阿里云主账号密码。
- **报错 `denied: requested access to the resource is denied`**：阿里云仓库不存在或没有推送权限。检查命名空间 `fubin` 和仓库 `showdoc` 是否在 `cn-qingdao` 地域下创建。
- **构建很慢**：首次构建要拉取 `webdevops/php-nginx:8.3-alpine` 基础镜像约 200MB，加上 npm/composer 依赖。如在国内，可在 Dockerfile 用 `--build-arg IN_CHINA=true` 加速（需要在 workflow 中加 `build-args`）。
- **构建报网络错误（pull 失败）**：可考虑开启 GitHub Actions 的「国内访问优化」，或者在 workflow 里加 `IN_CHINA=true` 构建参数。
