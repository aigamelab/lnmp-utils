lnmp-utils
==========

简介
===

> Linux (RHEL 8+/Rocky Linux 8+/Debian 10+/Ubuntu 20.04+) + OpenResty/Nginx + MariaDB + PHP + Redis + FastDFS 一键源码编译安装包。
> 经过实践检验，适合开发/生产环境的架构预研和部署。

> 项目组织: [aigamelab](https://github.com/aigamelab)
> 源码仓库: [https://github.com/aigamelab/lnmp-utils](https://github.com/aigamelab/lnmp-utils)
> 备用仓库: [https://gitee.com/aigamelab/lnmp-utils](https://gitee.com/aigamelab/lnmp-utils)

安装
===

- 安装方式: 源码编译，适合开发/生产环境的早期架构预研和部署。
- 支持系统: Rocky Linux 8/10, CentOS Stream 9, Debian 11/12, Ubuntu 22.04/24.04

+ 基础硬件要求:
  - CPU: 4核
  - 内存: 16G
  - 硬盘: 128G 以上 SSD/HDD

原生安装
----

```shell
git clone https://github.com/aigamelab/lnmp-utils.git
cd lnmp-utils
./install.sh
```

Docker 部署
----

```shell
git clone https://github.com/aigamelab/lnmp-utils.git
cd lnmp-utils
./install-docker.sh up     # 启动 LNMP 容器 (默认rockylinux)
./install-docker.sh build  # 本地构建镜像
./install-docker.sh status # 查看状态
./install-docker.sh shell  # 进入容器
```

组件
=======

+ [openresty 1.29.2.5](https://github.com/openresty/openresty.git) — Nginx + LuaJIT
+ [mariadb 11.4.12](https://mariadb.org/) — 关系型数据库 (MySQL 兼容)
+ [php 8.4.21 / 8.5.6](http://www.php.net/) — PHP-FPM
  + PECL 扩展: redis, mongodb, memcached, igbinary, ssh2
+ [redis 8.6.3](https://redis.io/) — 键值存储
+ [memcached 1.6.42](http://www.memcached.org/) — 内存缓存
+ [fastdfs 6.07](https://github.com/happyfish100/fastdfs) — 分布式文件存储
+ [lsyncd](https://github.com/lsyncd/lsyncd) — 文件实时同步
+ [node.js 24.16.0](https://nodejs.org/) — JavaScript 运行时

安装单个组件
---

```shell
git clone https://github.com/aigamelab/lnmp-utils.git
cd lnmp-utils

# OpenResty
./install.sh -c openresty

# MariaDB
./install.sh -c mariadb

# PHP (默认 8.4.21)
./install.sh -c php

# Redis
./install.sh -c redis

# Memcached
./install.sh -c memcached

# Node.js
./install.sh -c node

# FastDFS
./install.sh -c fastdfs

# Lsyncd
./install.sh -c lsyncd
```

编译模式 (使用本地源码)
---

```shell
# 先克隆构建仓库
git clone https://github.com/aigamelab/lnmp-utils-build.git ../lnmp-utils-build

# 使用 build 模式编译 (不下载预编译包)
./install.sh -b -c mariadb php openresty redis
```

Docker 多发行版测试
---

支持 4 个发行版的 Docker 镜像构建:

| 发行版 | Dockerfile | 基础镜像 |
|--------|-----------|---------|
| Rocky Linux 10 | `docker/Dockerfile.rockylinux` | `rockylinux/rockylinux:10` |
| CentOS Stream 9 | `docker/Dockerfile.centos` | `quay.io/centos/centos:stream9` |
| Debian 12 | `docker/Dockerfile.debian` | `debian:12` |
| Ubuntu 24.04 | `docker/Dockerfile.ubuntu` | `ubuntu:24.04` |

```shell
# 全部发行版测试
docker compose -f docker/docker-compose.yml build

# 单发行版测试
./install-docker.sh build debian
```

相关仓库
=======

+ [lnmp-utils-build](https://github.com/aigamelab/lnmp-utils-build) — 组件源码树和编译脚本
+ [lnmp-utils-packages](https://github.com/aigamelab/lnmp-utils-packages) — 预编译包分发

License
=======

MIT License — 详见 [LICENSE](LICENSE)
