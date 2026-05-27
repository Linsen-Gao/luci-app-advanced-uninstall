# LuCI Advanced Uninstall Manager

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![OpenWrt](https://img.shields.io/badge/OpenWrt-23.05%2B%20%7C%2025.xx%2B-blue.svg)](https://openwrt.org/)

一个功能强大的 OpenWrt LuCI 高级卸载管理插件，**兼容 OpenWrt 23.05 (opkg) 和 25.xx+ (apk)**，提供软件包管理、Docker 容器清理、批量操作等功能。

## 🔄 版本兼容性

| OpenWrt 版本 | 包管理器 | 状态 |
|-------------|---------|------|
| 23.05.x | opkg | ✅ 完全支持 |
| 24.10.x | opkg/apk | ✅ 完全支持 |
| 25.xx+ | apk | ✅ 完全支持 |

### 自动检测

插件会自动检测系统使用的包管理器：
- **opkg**: 传统 OpenWrt 包管理器
- **apk**: 新版 Alpine 包管理器

## 功能特性

### 🗑️ 软件包管理
- 查看已安装软件包列表
- 支持搜索和过滤
- 查看软件包详细信息
- 分析依赖关系
- **自动适配 opkg/apk 命令**

### 🐳 Docker 容器管理
- 自动检测关联的 Docker 容器
- 卸载时自动清理容器
- 支持清理容器卷

### 📦 安装功能
- 从 URL 安装 IPK/APK 包
- 上传本地包文件安装
- 支持强制安装选项

### ⚡ 批量操作
- 多选软件包
- 批量卸载
- 批量 Docker 容器清理

### 📊 统计信息
- 已安装软件包数量
- Docker 关联统计
- 系统信息显示

### 📝 其他功能
- 卸载历史日志
- 软件包列表导出（JSON/TXT）
- 可配置的卸载选项

## 安装方法

### 方法一：从 Releases 下载

1. 前往 [Releases](https://github.com/your-username/luci-app-advanced-uninstall/releases) 页面
2. 下载最新版本的安装包
3. 通过 LuCI 界面或命令行安装：

```bash
# OpenWrt 23.05 (opkg)
opkg install luci-app-advanced-uninstall_*.ipk

# OpenWrt 25.xx (apk)
apk add --allow-untrusted luci-app-advanced-uninstall_*.apk
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
3. 界面会自动显示当前使用的包管理器类型
4. 点击「卸载」按钮可卸载单个软件包
5. 勾选多个软件包可进行批量卸载
6. 点击「详情」可查看软件包的详细信息

## 依赖项

- `luci-base` - LuCI 基础框架
- `rpcd` - RPC 守护进程
- `opkg` 或 `apk` - 包管理器（自动检测）

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
| `/admin/system/uninstall/system_info` | GET | 获取系统信息 |

所有 API 响应中包含 `pkg_manager` 字段，标识当前使用的包管理器类型。

## 开发

### 项目结构

```
luci-app-advanced-uninstall/
├── Makefile                          # OpenWrt 编译配置
├── README.md                         # 说明文档
├── LICENSE                           # 许可证
├── src/
│   ├── controller/
│   │   └── uninstall.lua            # 后端控制器（支持 opkg/apk）
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

### 兼容性实现

控制器使用以下方式实现双包管理器兼容：

```lua
-- 检测包管理器类型
local function get_pkg_manager()
    if sys.call('command -v apk >/dev/null 2>&1') == 0 then
        return 'apk'
    end
    if sys.call('command -v opkg >/dev/null 2>&1') == 0 then
        return 'opkg'
    end
    return nil
end

-- 为每种包管理器提供独立的实现
local function apk_list_installed() ... end
local function opkg_list_installed() ... end
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
