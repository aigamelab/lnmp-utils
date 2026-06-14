# lnmp-utils

> 一键源码编译安装 LNMP 集群环境 | One-click source-compile LNMP stack installer

[English](#english) | [中文](#中文)

---

## English

A source-compilation installer for building LNMP (Linux + Nginx/OpenResty + MariaDB + PHP + Redis) clusters from scratch. Designed for production-grade deployment on RHEL/Debian-family distributions, with full Docker support for multi-distro testing and deployment.

### Supported Systems

| Family | Distributions |
|--------|--------------|
| RHEL | Rocky Linux 8/10, CentOS Stream 9 |
| Debian | Debian 11/12, Ubuntu 22.04/24.04 |

### Hardware Requirements

- CPU: 4 cores
- RAM: 16 GB
- Disk: 128 GB+ SSD/HDD

### Quick Start

**Native Install:**
```shell
git clone https://github.com/aigamelab/lnmp-utils.git
cd lnmp-utils
./install.sh
```

**Docker Deploy:**
```shell
git clone https://github.com/aigamelab/lnmp-utils.git
cd lnmp-utils
./install-docker.sh up        # start LNMP container (default: rockylinux)
./install-docker.sh build     # build image locally
./install-docker.sh status    # check status
./install-docker.sh shell     # enter container
```

### Components

| Component | Version | Description |
|-----------|---------|-------------|
| [OpenResty](https://github.com/openresty/openresty.git) | 1.29.2.5 | Nginx + LuaJIT |
| [MariaDB](https://mariadb.org/) | 11.4.12 | Relational database (MySQL-compatible) |
| [PHP](http://www.php.net/) | 8.4.21 / 8.5.6 | PHP-FPM with PECL extensions (redis, mongodb, memcached, igbinary, ssh2) |
| [Redis](https://redis.io/) | 8.6.3 | In-memory key-value store |
| [Memcached](http://www.memcached.org/) | 1.6.42 | Memory object cache |
| [FastDFS](https://github.com/happyfish100/fastdfs) | 6.07 | Distributed file system |
| [Lsyncd](https://github.com/lsyncd/lsyncd) | — | Real-time file sync |
| [Node.js](https://nodejs.org/) | 24.16.0 | JavaScript runtime |

### Install Individual Components

```shell
./install.sh -c openresty     # OpenResty + LuaJIT
./install.sh -c mariadb       # MariaDB
./install.sh -c php           # PHP-FPM (default 8.4.21)
./install.sh -c redis         # Redis
./install.sh -c memcached     # Memcached
./install.sh -c node          # Node.js
./install.sh -c fastdfs       # FastDFS
./install.sh -c lsyncd        # Lsyncd
```

### Build Mode (local sources, no download)

```shell
git clone https://github.com/aigamelab/lnmp-utils-build.git ../lnmp-utils-build
./install.sh -b -c mariadb php openresty redis
```

### Docker Multi-Distro Build

| Distro | Base Image |
|--------|-----------|
| Rocky Linux 10 | `rockylinux/rockylinux:10` |
| CentOS Stream 9 | `quay.io/centos/centos:stream9` |
| Debian 12 | `debian:12` |
| Ubuntu 24.04 | `ubuntu:24.04` |

```shell
# Build all distros
docker compose -f docker/docker-compose.yml build

# Build single distro
./install-docker.sh build debian
```

### Repository Mirrors

| Platform | URL |
|----------|-----|
| GitHub | https://github.com/aigamelab/lnmp-utils |
| Gitee | https://gitee.com/aigamelab/lnmp-utils |

### Related Repos

- [lnmp-utils-build](https://github.com/aigamelab/lnmp-utils-build) — Component source trees & compile scripts
- [lnmp-utils-packages](https://github.com/aigamelab/lnmp-utils-packages) — Pre-built package distribution

### License

[MIT](LICENSE)

---

## 中文

从源码编译构建 LNMP（Linux + Nginx/OpenResty + MariaDB + PHP + Redis）集群的一键安装工具。面向生产环境设计，支持 RHEL/Debian 系发行版，并提供 Docker 多发行版测试与部署能力。

### 支持系统

| 系列 | 发行版 |
|------|--------|
| RHEL | Rocky Linux 8/10, CentOS Stream 9 |
| Debian | Debian 11/12, Ubuntu 22.04/24.04 |

### 硬件要求

- CPU：4 核
- 内存：16 GB
- 硬盘：128 GB 以上 SSD/HDD

### 快速开始

**原生安装：**
```shell
git clone https://github.com/aigamelab/lnmp-utils.git
cd lnmp-utils
./install.sh
```

**Docker 部署：**
```shell
git clone https://github.com/aigamelab/lnmp-utils.git
cd lnmp-utils
./install-docker.sh up        # 启动 LNMP 容器（默认 rockylinux）
./install-docker.sh build     # 本地构建镜像
./install-docker.sh status    # 查看状态
./install-docker.sh shell     # 进入容器
```

### 组件

| 组件 | 版本 | 说明 |
|------|------|------|
| [OpenResty](https://github.com/openresty/openresty.git) | 1.29.2.5 | Nginx + LuaJIT |
| [MariaDB](https://mariadb.org/) | 11.4.12 | 关系型数据库（兼容 MySQL） |
| [PHP](http://www.php.net/) | 8.4.21 / 8.5.6 | PHP-FPM，含 PECL 扩展（redis, mongodb, memcached, igbinary, ssh2） |
| [Redis](https://redis.io/) | 8.6.3 | 内存键值存储 |
| [Memcached](http://www.memcached.org/) | 1.6.42 | 内存对象缓存 |
| [FastDFS](https://github.com/happyfish100/fastdfs) | 6.07 | 分布式文件存储 |
| [Lsyncd](https://github.com/lsyncd/lsyncd) | — | 文件实时同步 |
| [Node.js](https://nodejs.org/) | 24.16.0 | JavaScript 运行时 |

### 安装单个组件

```shell
./install.sh -c openresty     # OpenResty + LuaJIT
./install.sh -c mariadb       # MariaDB
./install.sh -c php           # PHP-FPM（默认 8.4.21）
./install.sh -c redis         # Redis
./install.sh -c memcached     # Memcached
./install.sh -c node          # Node.js
./install.sh -c fastdfs       # FastDFS
./install.sh -c lsyncd        # Lsyncd
```

### 编译模式（使用本地源码，不下载预编译包）

```shell
git clone https://github.com/aigamelab/lnmp-utils-build.git ../lnmp-utils-build
./install.sh -b -c mariadb php openresty redis
```

### Docker 多发行版构建

| 发行版 | 基础镜像 |
|--------|---------|
| Rocky Linux 10 | `rockylinux/rockylinux:10` |
| CentOS Stream 9 | `quay.io/centos/centos:stream9` |
| Debian 12 | `debian:12` |
| Ubuntu 24.04 | `ubuntu:24.04` |

```shell
# 构建所有发行版
docker compose -f docker/docker-compose.yml build

# 构建单个发行版
./install-docker.sh build debian
```

### 仓库镜像

| 平台 | 地址 |
|------|------|
| GitHub | https://github.com/aigamelab/lnmp-utils |
| Gitee | https://gitee.com/aigamelab/lnmp-utils |

### 相关仓库

- [lnmp-utils-build](https://github.com/aigamelab/lnmp-utils-build) — 组件源码树与编译脚本
- [lnmp-utils-packages](https://github.com/aigamelab/lnmp-utils-packages) — 预编译包分发

### 开源协议

[MIT](LICENSE)
