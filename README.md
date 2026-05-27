# LuCI Advanced Uninstall Manager

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![OpenWrt](https://img.shields.io/badge/OpenWrt-23.05+-blue.svg)](https://openwrt.org/)

一个功能强大的 OpenWrt LuCI 高级卸载管理插件，提供软件包管理、Docker 容器清理、批量操作等功能。

![Screenshot](screenshot.png)

## 功能特性

### 🗑️ 软件包管理
- 查看已安装软件包列表
- 支持搜索和过滤
- 查看软件包详细信息
- 分析依赖关系

### 🐳 Docker 容器管理
- 自动检测关联的 Docker 容器
- 卸载时自动清理容器
- 支持清理容器卷

### 📦 安装功能
- 从 URL 安装 IPK 包
- 上传本地 IPK 文件安装
- 支持强制安装选项

### ⚡ 批量操作
- 多选软件包
- 批量卸载
- 批量 Docker 容器清理

### 📊 统计信息
- 已安装软件包数量
- Docker 关联统计
- 磁盘占用统计

### 📝 其他功能
- 卸载历史日志
- 软件包列表导出（JSON/TXT）
- 可配置的卸载选项

## 安装方法

### 方法一：从 Releases 下载

1. 前往 [Releases](https://github.com/your-username/luci-app-advanced-uninstall/releases) 页面
2. 下载最新版本的 `.ipk` 文件
3. 通过 LuCI 界面或命令行安装：

```bash
opkg install luci-app-advanced-uninstall_*.ipk
```

### 方法二：从源码编译

```bash
# 克隆仓库
git clone https://github.com/your-username/luci-app-advanced-uninstall.git

# 复制到 OpenWrt 源码目录
cp -r luci-app-advanced-uninstall /path/to/openwrt/feeds/luci/applications/

# 更新 feeds
./scripts/feeds update -a
./scripts/feeds install -a

# 编译
make package/luci-app-advanced-uninstall/compile V=s
```

### 方法三：使用 Makeself 安装包

```bash
# 下载 .run 安装包
wget https://github.com/your-username/luci-app-advanced-uninstall/releases/latest/download/luci-app-advanced-uninstall.run

# 添加执行权限
chmod +x luci-app-advanced-uninstall.run

# 运行安装
./luci-app-advanced-uninstall.run
```

## 使用说明

1. 安装后，在 LuCI 界面中找到 **系统 → 高级卸载**
2. 主界面显示已安装的软件包列表
3. 点击「卸载」按钮可卸载单个软件包
4. 勾选多个软件包可进行批量卸载
5. 点击「详情」可查看软件包的详细信息

## 依赖项

- `luci-base` - LuCI 基础框架
- `rpcd` - RPC 守护进程
- `opkg` - 包管理器
- `luci-lua-runtime` - Lua 运行时

## 配置

配置文件位于 `/etc/luci-app-advanced-uninstall/settings.json`，可配置项：

```json
{
  "auto_clean_docker": false,
  "auto_remove_deps": false,
  "show_system_packages": false,
  "confirm_before_remove": true
}
```

## API 接口

| 端点 | 方法 | 描述 |
|------|------|------|
| `/admin/system/uninstall/list` | GET | 获取软件包列表 |
| `/admin/system/uninstall/remove` | POST | 卸载软件包 |
| `/admin/system/uninstall/batch_remove` | POST | 批量卸载 |
| `/admin/system/uninstall/info` | GET | 获取软件包详情 |
| `/admin/system/uninstall/dependencies` | GET | 获取依赖关系 |
| `/admin/system/uninstall/install_from_url` | POST | 从 URL 安装 |
| `/admin/system/uninstall/install_upload` | POST | 上传安装 |
| `/admin/system/uninstall/search_files` | GET | 搜索文件 |
| `/admin/system/uninstall/history_log` | GET | 获取历史日志 |
| `/admin/system/uninstall/check_docker` | GET | 检查 Docker 环境 |
| `/admin/system/uninstall/docker_cleanup` | POST | 清理 Docker 容器 |

## 开发

### 项目结构

```
luci-app-advanced-uninstall/
├── Makefile                          # OpenWrt 编译配置
├── README.md                         # 说明文档
├── LICENSE                           # 许可证
├── src/
│   ├── controller/
│   │   └── uninstall.lua            # 后端控制器
│   ├── view/
│   │   └── uninstall/
│   │       └── main.htm             # 前端视图模板
│   ├── acl.d/
│   │   └── luci-app-advanced-uninstall.json  # ACL 配置
│   └── icons/                       # 图标资源
└── .github/
    └── workflows/
        └── build.yml                # GitHub Actions 构建
```

### 本地测试

```bash
# 在 OpenWrt 设备上测试
ssh root@192.168.1.1

# 查看日志
logread | grep uninstall

# 重启 LuCI
/etc/init.d/uhttpd restart
```

## 许可证

本项目使用 [Apache 2.0](LICENSE) 许可证。

## 贡献

欢迎提交 Issue 和 Pull Request！

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 创建 Pull Request

## 致谢

- [OpenWrt](https://openwrt.org/) - 优秀的路由器固件
- [LuCI](https://github.com/openwrt/luci) - OpenWrt Web 管理界面
- [Makeself](https://github.com/megastep/makeself) - 自解压归档工具

## 支持

如果觉得这个项目有帮助，请给个 ⭐️ Star 支持一下！
