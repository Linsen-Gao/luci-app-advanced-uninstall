-- SPDX-License-Identifier: Apache-2.0
-- LuCI Advanced Uninstall Manager Controller
-- Compatible with OpenWrt 23.05+ and 25.xx+ (opkg/apk)

module("luci.controller.uninstall", package.seeall)

function index()
	if not nixio.fs.access('/etc/config') then
		return
	end

	-- 主菜单入口
	entry({ 'admin', 'system', 'uninstall' }, firstchild(), _('高级卸载'), 60).dependent = true
	entry({ 'admin', 'system', 'uninstall', 'manage' }, view('uninstall/main'), _('软件包管理'), 10).acl_depends = { 'luci-app-advanced-uninstall' }

	-- API 端点
	local e
	
	e = entry({ 'admin', 'system', 'uninstall', 'list' }, call('action_list'))
	e.leaf = true
	e.acl_depends = { 'luci-app-advanced-uninstall' }

	e = entry({ 'admin', 'system', 'uninstall', 'remove' }, call('action_remove'))
	e.leaf = true
	e.acl_depends = { 'luci-app-advanced-uninstall' }

	e = entry({ 'admin', 'system', 'uninstall', 'search_files' }, call('action_search_files'))
	e.leaf = true
	e.acl_depends = { 'luci-app-advanced-uninstall' }

	e = entry({ 'admin', 'system', 'uninstall', 'info' }, call('action_info'))
	e.leaf = true
	e.acl_depends = { 'luci-app-advanced-uninstall' }

	e = entry({ 'admin', 'system', 'uninstall', 'dependencies' }, call('action_dependencies'))
	e.leaf = true
	e.acl_depends = { 'luci-app-advanced-uninstall' }

	e = entry({ 'admin', 'system', 'uninstall', 'install_from_url' }, call('action_install_from_url'))
	e.leaf = true
	e.acl_depends = { 'luci-app-advanced-uninstall' }

	e = entry({ 'admin', 'system', 'uninstall', 'install_upload' }, call('action_install_upload'))
	e.leaf = true
	e.acl_depends = { 'luci-app-advanced-uninstall' }

	e = entry({ 'admin', 'system', 'uninstall', 'check_install_status' }, call('action_check_install_status'))
	e.leaf = true
	e.acl_depends = { 'luci-app-advanced-uninstall' }

	e = entry({ 'admin', 'system', 'uninstall', 'check_docker' }, call('action_check_docker'))
	e.leaf = true
	e.acl_depends = { 'luci-app-advanced-uninstall' }

	e = entry({ 'admin', 'system', 'uninstall', 'docker_cleanup' }, call('action_docker_cleanup'))
	e.leaf = true
	e.acl_depends = { 'luci-app-advanced-uninstall' }

	e = entry({ 'admin', 'system', 'uninstall', 'history_log' }, call('action_history_log'))
	e.leaf = true
	e.acl_depends = { 'luci-app-advanced-uninstall' }

	e = entry({ 'admin', 'system', 'uninstall', 'save_settings' }, call('action_save_settings'))
	e.leaf = true
	e.acl_depends = { 'luci-app-advanced-uninstall' }

	e = entry({ 'admin', 'system', 'uninstall', 'get_settings' }, call('action_get_settings'))
	e.leaf = true
	e.acl_depends = { 'luci-app-advanced-uninstall' }

	e = entry({ 'admin', 'system', 'uninstall', 'batch_remove' }, call('action_batch_remove'))
	e.leaf = true
	e.acl_depends = { 'luci-app-advanced-uninstall' }

	e = entry({ 'admin', 'system', 'uninstall', 'export_list' }, call('action_export_list'))
	e.leaf = true
	e.acl_depends = { 'luci-app-advanced-uninstall' }
	
	e = entry({ 'admin', 'system', 'uninstall', 'system_info' }, call('action_system_info'))
	e.leaf = true
	e.acl_depends = { 'luci-app-advanced-uninstall' }
end

-- 引入必要的库
local http = require 'luci.http'
local sys = require 'luci.sys'
local json = require 'luci.jsonc'
local util = require 'luci.util'

-- 兼容性：尝试加载不同的模块
local fs
pcall(function() fs = require 'nixio.fs' end)
if not fs then
	pcall(function() fs = require 'luci.fs' end)
end

-- 检测包管理器类型
local function get_pkg_manager()
	-- 检测 apk
	if sys.call('command -v apk >/dev/null 2>&1') == 0 then
		return 'apk'
	end
	-- 检测 opkg
	if sys.call('command -v opkg >/dev/null 2>&1') == 0 then
		return 'opkg'
	end
	return nil
end

-- 配置常量
local CONFIG_DIR = '/etc/luci-app-advanced-uninstall'
local LOG_FILE = CONFIG_DIR .. '/uninstall.log'
local SETTINGS_FILE = CONFIG_DIR .. '/settings.json'

-- Docker 容器映射表
local DOCKER_CONTAINER_MAP = {
	['luci-app-istorepanel'] = {'1panel', 'istorepanel'},
	['luci-app-dpanel'] = {'dpanel'},
	['luci-app-alist'] = {'alist'},
	['luci-app-qbittorrent'] = {'qbittorrent', 'qbittorrent-ee'},
	['luci-app-emby'] = {'emby', 'embyserver'},
	['luci-app-jellyfin'] = {'jellyfin'},
	['luci-app-homeassistant'] = {'homeassistant', 'ha'},
	['luci-app-nextcloud'] = {'nextcloud'},
	['luci-app-syncthing'] = {'syncthing'},
	['luci-app-transmission'] = {'transmission'},
	['luci-app-aria2'] = {'aria2', 'ariang'},
	['luci-app-docker'] = {},
	['luci-app-dockerman'] = {},
	['luci-app-openclash'] = {'openclash'},
	['luci-app-passwall'] = {},
	['luci-app-vssr'] = {},
}

-- JSON 响应封装
local function json_response(tbl, code)
	code = code or 200
	http.status(code, '')
	http.header('Cache-Control', 'no-cache, no-store, must-revalidate')
	http.header('Pragma', 'no-cache')
	http.header('Expires', '0')
	http.prepare_content('application/json')
	http.write(json.stringify(tbl or {}))
end

-- 确保配置目录存在
local function ensure_config_dir()
	if fs and not fs.stat(CONFIG_DIR) then
		fs.mkdirr(CONFIG_DIR)
	elseif not fs then
		sys.call('mkdir -p ' .. CONFIG_DIR)
	end
end

-- 写入日志
local function write_log(message)
	ensure_config_dir()
	local timestamp = os.date('%Y-%m-%d %H:%M:%S')
	local log_entry = string.format('[%s] %s\n', timestamp, message)
	
	if fs then
		local f = io.open(LOG_FILE, 'a')
		if f then
			f:write(log_entry)
			f:close()
		end
	else
		sys.call(string.format('echo %q >> %q', log_entry, LOG_FILE))
	end
end

-- 检查 Docker 是否可用
local function has_docker()
	return sys.call('command -v docker >/dev/null 2>&1') == 0
end

-- 获取软件包关联的 Docker 容器
local function get_docker_containers(pkg)
	if not has_docker() then
		return {}
	end
	
	local containers = {}
	local pkg_containers = DOCKER_CONTAINER_MAP[pkg]
	
	if pkg_containers then
		for _, container_name in ipairs(pkg_containers) do
			local check_cmd = string.format(
				'docker ps -a --filter "name=^%s$" --format "{{.Names}}" 2>/dev/null',
				container_name
			)
			local result = sys.exec(check_cmd)
			if result and result ~= '' then
				table.insert(containers, container_name)
			end
		end
	end
	
	-- 也检查包含包名的容器
	local search_cmd = string.format(
		'docker ps -a --format "{{.Names}}" 2>/dev/null | grep -i "%s" || true',
		pkg:gsub('luci%-app%-', '')
	)
	local result = sys.exec(search_cmd)
	if result and result ~= '' then
		for container in result:gmatch('[^\r\n]+') do
			local found = false
			for _, c in ipairs(containers) do
				if c == container then
					found = true
					break
				end
			end
			if not found then
				table.insert(containers, container)
			end
		end
	end
	
	return containers
end

-- ============================================
-- APK 包管理器函数
-- ============================================

-- 获取已安装包列表 (apk)
local function apk_list_installed()
	local packages = {}
	local output = sys.exec('apk list --installed 2>/dev/null')
	
	if not output or output == '' then
		return packages
	end
	
	for line in output:gmatch('[^\r\n]+') do
		-- apk 输出格式: package-name-version description
		local name, version = line:match('^([^\s]+)-([^-]+%-%d+)')
		if name then
			table.insert(packages, {
				name = name,
				version = version,
				description = line:match('^%S+%s+(.*)$') or ''
			})
		end
	end
	
	return packages
end

-- 获取包信息 (apk)
local function apk_info(pkg)
	local output = sys.exec(string.format('apk info -a %s 2>/dev/null', pkg))
	if not output then
		return nil
	end
	
	local info = {}
	for line in output:gmatch('[^\r\n]+') do
		local key, value = line:match('^([^:]+):%s*(.*)')
		if key then
			info[key:lower():gsub('[%s%-]', '_')] = value
		end
	end
	
	return info
end

-- 卸载包 (apk)
local function apk_remove(pkg, force)
	local cmd = string.format('apk del %s', pkg)
	if force then
		cmd = string.format('apk del --force %s', pkg)
	end
	return sys.call(cmd .. ' 2>&1')
end

-- 安装包 (apk)
local function apk_install(filepath)
	local cmd = string.format('apk add --allow-untrusted %s', filepath)
	return sys.call(cmd .. ' 2>&1')
end

-- ============================================
-- OPKG 包管理器函数
-- ============================================

-- 获取已安装包列表 (opkg)
local function opkg_list_installed()
	local packages = {}
	local output = sys.exec('opkg list-installed 2>/dev/null')
	
	if not output or output == '' then
		return packages
	end
	
	for line in output:gmatch('[^\r\n]+') do
		local name, version = line:match('^([^%s]+)%s*%- ([^%s]+)')
		if name then
			table.insert(packages, {
				name = name,
				version = version,
				description = ''
			})
		end
	end
	
	return packages
end

-- 获取包信息 (opkg)
local function opkg_info(pkg)
	local output = sys.exec(string.format('opkg info %s 2>/dev/null', pkg))
	if not output then
		return nil
	end
	
	local info = {}
	for line in output:gmatch('[^\r\n]+') do
		local key, value = line:match('^([^:]+):%s*(.*)')
		if key then
			info[key:lower():gsub('%-', '_')] = value
		end
	end
	
	return info
end

-- 卸载包 (opkg)
local function opkg_remove(pkg, force, remove_deps)
	local cmd = string.format('opkg remove %s', pkg)
	if force then
		cmd = cmd .. ' --force-remove'
	end
	if remove_deps then
		cmd = cmd .. ' --autoremove'
	end
	return sys.call(cmd .. ' 2>&1')
end

-- 安装包 (opkg)
local function opkg_install(filepath)
	local cmd = string.format('opkg install --force-reinstall --force-overwrite %q', filepath)
	return sys.call(cmd .. ' 2>&1')
end

-- ============================================
-- 通用包管理接口
-- ============================================

-- 获取已安装的软件包列表
function action_list()
	local pkg_mgr = get_pkg_manager()
	if not pkg_mgr then
		return json_response({ error = '未找到包管理器', packages = {}, total = 0 }, 500)
	end
	
	local packages = {}
	
	if pkg_mgr == 'apk' then
		packages = apk_list_installed()
	else
		packages = opkg_list_installed()
	end
	
	-- 为每个包添加额外信息
	for i, pkg in ipairs(packages) do
		-- 检查是否有 Docker 容器
		local docker_containers = get_docker_containers(pkg.name)
		packages[i].has_docker = #docker_containers > 0
		packages[i].docker_containers = docker_containers
		
		-- 获取包大小 (opkg)
		if pkg_mgr == 'opkg' then
			local size_cmd = string.format('opkg status %s 2>/dev/null | grep "^Installed-Size:" | cut -d: -f2', pkg.name)
			local size = sys.exec(size_cmd):match('^%s*(.-)%s*$') or '0'
			packages[i].size = tonumber(size) or 0
		else
			packages[i].size = 0
		end
	end
	
	-- 按名称排序
	table.sort(packages, function(a, b) return a.name < b.name end)
	
	return json_response({
		packages = packages,
		total = #packages,
		pkg_manager = pkg_mgr
	})
end

-- 获取软件包详细信息
function action_info()
	local pkg = http.formvalue('package')
	if not pkg or pkg == '' then
		return json_response({ error = '未指定软件包名称' }, 400)
	end
	
	local pkg_mgr = get_pkg_manager()
	local info = {}
	
	if pkg_mgr == 'apk' then
		info = apk_info(pkg) or {}
	else
		info = opkg_info(pkg) or {}
	end
	
	if not info or next(info) == nil then
		return json_response({ error = '软件包不存在' }, 404)
	end
	
	-- 获取文件列表
	local files = {}
	local files_cmd
	if pkg_mgr == 'apk' then
		files_cmd = string.format('apk info -L %s 2>/dev/null', pkg)
	else
		files_cmd = string.format('opkg files %s 2>/dev/null', pkg)
	end
	
	local files_output = sys.exec(files_cmd)
	if files_output then
		for file in files_output:gmatch('[^\r\n]+') do
			if not file:match('^%s*$') and not file:match('^Package') and not file:match('^WARNING') then
				table.insert(files, file:match('^%s*(.-)%s*$'))
			end
		end
	end
	
	-- 获取 Docker 容器信息
	local docker_containers = get_docker_containers(pkg)
	
	return json_response({
		package = pkg,
		info = info,
		files = files,
		docker_containers = docker_containers,
		pkg_manager = pkg_mgr
	})
end

-- 获取依赖关系
function action_dependencies()
	local pkg = http.formvalue('package')
	if not pkg or pkg == '' then
		return json_response({ error = '未指定软件包名称' }, 400)
	end
	
	local pkg_mgr = get_pkg_manager()
	local dependencies = {}
	local dependents = {}
	
	if pkg_mgr == 'apk' then
		-- apk 依赖查询
		local deps_cmd = string.format('apk info -R %s 2>/dev/null', pkg)
		local deps_output = sys.exec(deps_cmd)
		if deps_output then
			for line in deps_output:gmatch('[^\r\n]+') do
				if not line:match('^%s*$') and line ~= pkg then
					table.insert(dependencies, line:match('^%s*(.-)%s*$'))
				end
			end
		end
		
		-- 反向依赖
		local rdeps_cmd = string.format('apk info -r %s 2>/dev/null', pkg)
		local rdeps_output = sys.exec(rdeps_cmd)
		if rdeps_output then
			for line in rdeps_output:gmatch('[^\r\n]+') do
				if not line:match('^%s*$') and line ~= pkg then
					table.insert(dependents, line:match('^%s*(.-)%s*$'))
				end
			end
		end
	else
		-- opkg 依赖查询
		local deps_cmd = string.format('opkg info %s 2>/dev/null | grep "^Depends:" | cut -d: -f2', pkg)
		local deps_str = sys.exec(deps_cmd):match('^%s*(.-)%s*$') or ''
		
		if deps_str ~= '' then
			for dep in deps_str:gmatch('[^,]+') do
				dep = dep:match('^%s*(.-)%s*$')
				if dep and dep ~= '' then
					table.insert(dependencies, dep)
				end
			end
		end
	end
	
	return json_response({
		package = pkg,
		dependencies = dependencies,
		dependents = dependents,
		pkg_manager = pkg_mgr
	})
end

-- 卸载软件包
function action_remove()
	local pkg = http.formvalue('package')
	local force = http.formvalue('force') == '1'
	local remove_deps = http.formvalue('remove_deps') == '1'
	local remove_docker = http.formvalue('remove_docker') == '1'
	
	if not pkg or pkg == '' then
		return json_response({ error = '未指定软件包名称' }, 400)
	end
	
	local pkg_mgr = get_pkg_manager()
	if not pkg_mgr then
		return json_response({ error = '未找到包管理器' }, 500)
	end
	
	-- 检查包是否存在
	local installed = false
	if pkg_mgr == 'apk' then
		installed = sys.call(string.format('apk info -e %s >/dev/null 2>&1', pkg)) == 0
	else
		installed = sys.call(string.format('opkg status %s 2>/dev/null | grep -q "^Status:"', pkg)) == 0
	end
	
	if not installed then
		return json_response({ error = '软件包未安装' }, 404)
	end
	
	-- 获取 Docker 容器
	local docker_containers = get_docker_containers(pkg)
	
	-- 如果需要清理 Docker 容器
	local docker_cleaned = {}
	if remove_docker and #docker_containers > 0 then
		for _, container in ipairs(docker_containers) do
			sys.call(string.format('docker stop %s 2>/dev/null', container))
			if sys.call(string.format('docker rm -f %s 2>/dev/null', container)) == 0 then
				table.insert(docker_cleaned, container)
				write_log(string.format('Docker 容器已删除: %s', container))
			end
		end
	end
	
	-- 卸载包
	local result
	if pkg_mgr == 'apk' then
		result = apk_remove(pkg, force)
	else
		result = opkg_remove(pkg, force, remove_deps)
	end
	
	if result == 0 then
		write_log(string.format('软件包已卸载: %s (%s)', pkg, pkg_mgr))
		return json_response({
			ok = true,
			message = string.format('软件包 %s 已成功卸载', pkg),
			docker_cleaned = docker_cleaned,
			pkg_manager = pkg_mgr
		})
	else
		return json_response({
			ok = false,
			error = '卸载失败，请尝试使用强制卸载'
		}, 500)
	end
end

-- 批量卸载
function action_batch_remove()
	local packages_str = http.formvalue('packages')
	local force = http.formvalue('force') == '1'
	local remove_docker = http.formvalue('remove_docker') == '1'
	
	if not packages_str or packages_str == '' then
		return json_response({ error = '未指定软件包列表' }, 400)
	end
	
	local ok, packages = pcall(json.parse, packages_str)
	if not ok or not packages or type(packages) ~= 'table' then
		return json_response({ error = '无效的软件包列表格式' }, 400)
	end
	
	local pkg_mgr = get_pkg_manager()
	if not pkg_mgr then
		return json_response({ error = '未找到包管理器' }, 500)
	end
	
	local results = {
		success = {},
		failed = {},
		docker_cleaned = {}
	}
	
	for _, pkg in ipairs(packages) do
		pkg = pkg:match('^%s*(.-)%s*$')
		if pkg and pkg ~= '' then
			-- 处理 Docker 容器
			if remove_docker then
				local containers = get_docker_containers(pkg)
				for _, container in ipairs(containers) do
					sys.call(string.format('docker stop %s 2>/dev/null', container))
					if sys.call(string.format('docker rm -f %s 2>/dev/null', container)) == 0 then
						table.insert(results.docker_cleaned, container)
					end
				end
			end
			
			-- 卸载包
			local result
			if pkg_mgr == 'apk' then
				result = apk_remove(pkg, force)
			else
				result = opkg_remove(pkg, force, false)
			end
			
			if result == 0 then
				table.insert(results.success, pkg)
				write_log(string.format('批量卸载成功: %s', pkg))
			else
				table.insert(results.failed, pkg)
				write_log(string.format('批量卸载失败: %s', pkg))
			end
		end
	end
	
	return json_response({
		ok = true,
		results = results,
		message = string.format('成功卸载 %d 个包，失败 %d 个', #results.success, #results.failed),
		pkg_manager = pkg_mgr
	})
end

-- 搜索软件包相关文件
function action_search_files()
	local keyword = http.formvalue('keyword')
	if not keyword or keyword == '' then
		return json_response({ error = '未指定搜索关键词' }, 400)
	end
	
	local results = {}
	
	-- 搜索已安装包的文件
	local search_cmd = string.format('find /usr /etc /opt -name "*%s*" -type f 2>/dev/null | head -100', keyword)
	local found_files = sys.exec(search_cmd)
	
	if found_files and found_files ~= '' then
		for file in found_files:gmatch('[^\r\n]+') do
			local owner = '未知'
			
			-- 根据包管理器查找文件所属
			local pkg_mgr = get_pkg_manager()
			if pkg_mgr == 'apk' then
				owner = sys.exec(string.format('apk info --who-owns %q 2>/dev/null | head -1', file)):match('^%s*(.-)%s*$') or '未知'
			else
				owner = sys.exec(string.format('opkg search %q 2>/dev/null | cut -d: -f1', file)):match('^%s*(.-)%s*$') or '未知'
			end
			
			table.insert(results, {
				file = file,
				package = owner
			})
		end
	end
	
	return json_response({
		keyword = keyword,
		results = results,
		total = #results
	})
end

-- 从 URL 安装
function action_install_from_url()
	local url = http.formvalue('url')
	if not url or url == '' then
		return json_response({ error = '未指定下载地址' }, 400)
	end
	
	if not url:match('^https?://') then
		return json_response({ error = '无效的 URL 格式' }, 400)
	end
	
	ensure_config_dir()
	
	local pkg_mgr = get_pkg_manager()
	if not pkg_mgr then
		return json_response({ error = '未找到包管理器' }, 500)
	end
	
	-- 确定文件扩展名
	local ext = '.ipk'
	if pkg_mgr == 'apk' then
		ext = '.apk'
	end
	
	local filename = url:match('[^/]+%' .. ext .. '$') or ('package' .. ext)
	local filepath = CONFIG_DIR .. '/' .. filename
	
	-- 下载文件
	local download_cmd = string.format('wget -q -O %q %q 2>&1', filepath, url)
	local result = sys.call(download_cmd)
	
	if result ~= 0 then
		download_cmd = string.format('curl -sL -o %q %q 2>&1', filepath, url)
		result = sys.call(download_cmd)
	end
	
	if result ~= 0 then
		return json_response({ error = '下载失败' }, 500)
	end
	
	-- 安装包
	if pkg_mgr == 'apk' then
		result = apk_install(filepath)
	else
		result = opkg_install(filepath)
	end
	
	-- 清理临时文件
	if fs then
		fs.remove(filepath)
	else
		sys.call('rm -f ' .. filepath)
	end
	
	if result == 0 then
		write_log(string.format('从 URL 安装成功: %s', url))
		return json_response({
			ok = true,
			message = '安装成功',
			pkg_manager = pkg_mgr
		})
	else
		return json_response({
			ok = false,
			error = '安装失败'
		}, 500)
	end
end

-- 上传安装
function action_install_upload()
	local fp
	
	luci.http.setfilehandler(function(meta, chunk, eof)
		if not fp then
			if meta and meta.file then
				ensure_config_dir()
				fp = io.open(CONFIG_DIR .. '/upload.tmp', 'wb')
			end
		end
		if fp and chunk then
			fp:write(chunk)
		end
		if fp and eof then
			fp:close()
		end
	end)
	
	-- 触发文件处理
	http.formvalue('file')
	
	local filepath = CONFIG_DIR .. '/upload.tmp'
	
	if not (fs and fs.stat(filepath)) and sys.call('test -f ' .. filepath) ~= 0 then
		return json_response({ error = '文件上传失败' }, 400)
	end
	
	local pkg_mgr = get_pkg_manager()
	if not pkg_mgr then
		return json_response({ error = '未找到包管理器' }, 500)
	end
	
	-- 安装包
	local result
	if pkg_mgr == 'apk' then
		result = apk_install(filepath)
	else
		result = opkg_install(filepath)
	end
	
	-- 清理
	if fs then
		fs.remove(filepath)
	else
		sys.call('rm -f ' .. filepath)
	end
	
	if result == 0 then
		write_log('上传安装成功')
		return json_response({
			ok = true,
			message = '安装成功',
			pkg_manager = pkg_mgr
		})
	else
		return json_response({
			ok = false,
			error = '安装失败，请检查包格式'
		}, 500)
	end
end

-- 检查安装状态
function action_check_install_status()
	local pkg = http.formvalue('package')
	if not pkg or pkg == '' then
		return json_response({ error = '未指定软件包名称' }, 400)
	end
	
	local pkg_mgr = get_pkg_manager()
	local installed = false
	
	if pkg_mgr == 'apk' then
		installed = sys.call(string.format('apk info -e %s >/dev/null 2>&1', pkg)) == 0
	else
		installed = sys.call(string.format('opkg status %s 2>/dev/null | grep -q "^Status:"', pkg)) == 0
	end
	
	return json_response({
		package = pkg,
		installed = installed,
		pkg_manager = pkg_mgr
	})
end

-- 检查 Docker 环境
function action_check_docker()
	local available = has_docker()
	local running = false
	local containers = {}
	
	if available then
		running = sys.call('docker info >/dev/null 2>&1') == 0
		
		if running then
			local ps_output = sys.exec('docker ps -a --format "{{.Names}}|{{.Status}}|{{.Image}}" 2>/dev/null')
			if ps_output then
				for line in ps_output:gmatch('[^\r\n]+') do
					local name, status, image = line:match('^([^|]+)|([^|]+)|(.+)$')
					if name then
						table.insert(containers, {
							name = name,
							status = status,
							image = image
						})
					end
				end
			end
		end
	end
	
	return json_response({
		available = available,
		running = running,
		containers = containers
	})
end

-- 清理 Docker 容器
function action_docker_cleanup()
	if not has_docker() then
		return json_response({ error = 'Docker 未安装' }, 400)
	end
	
	local container = http.formvalue('container')
	local remove_volumes = http.formvalue('remove_volumes') == '1'
	
	if not container or container == '' then
		return json_response({ error = '未指定容器名称' }, 400)
	end
	
	sys.call(string.format('docker stop %q 2>/dev/null', container))
	
	local result = sys.call(string.format('docker rm -f %q 2>/dev/null', container))
	
	if result == 0 then
		if remove_volumes then
			sys.call(string.format('docker volume rm $(docker inspect -f \'{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}} {{end}}{{end}}\' %q 2>/dev/null) 2>/dev/null || true', container))
		end
		
		write_log(string.format('Docker 容器已清理: %s', container))
		return json_response({
			ok = true,
			message = string.format('容器 %s 已删除', container)
		})
	else
		return json_response({
			ok = false,
			error = '删除容器失败'
		}, 500)
	end
end

-- 获取历史日志
function action_history_log()
	local limit = tonumber(http.formvalue('limit')) or 100
	local logs = {}
	
	local content
	if fs and fs.stat(LOG_FILE) then
		content = fs.readfile(LOG_FILE)
	else
		content = sys.exec(string.format('cat %q 2>/dev/null', LOG_FILE))
	end
	
	if content then
		local lines = {}
		for line in content:gmatch('[^\r\n]+') do
			table.insert(lines, line)
		end
		
		local start_idx = math.max(1, #lines - limit + 1)
		for i = start_idx, #lines do
			table.insert(logs, lines[i])
		end
	end
	
	return json_response({
		logs = logs,
		total = #logs
	})
end

-- 保存设置
function action_save_settings()
	ensure_config_dir()
	
	local body = http.content()
	if not body or body == '' then
		return json_response({ error = '无效的请求数据' }, 400)
	end
	
	local ok, data = pcall(json.parse, body)
	if not ok or not data then
		return json_response({ error = 'JSON 解析失败' }, 400)
	end
	
	local content = json.stringify(data, true)
	
	if fs then
		local tmp_file = SETTINGS_FILE .. '.tmp'
		fs.writefile(tmp_file, content)
		sys.call(string.format('mv -f %q %q', tmp_file, SETTINGS_FILE))
	else
		sys.call(string.format('echo %q > %q', content, SETTINGS_FILE))
	end
	
	return json_response({
		ok = true,
		message = '设置已保存'
	})
end

-- 获取设置
function action_get_settings()
	ensure_config_dir()
	
	local settings = {
		auto_clean_docker = false,
		auto_remove_deps = false,
		show_system_packages = false,
		confirm_before_remove = true
	}
	
	local content
	if fs and fs.stat(SETTINGS_FILE) then
		content = fs.readfile(SETTINGS_FILE)
	else
		content = sys.exec(string.format('cat %q 2>/dev/null', SETTINGS_FILE))
	end
	
	if content then
		local ok, parsed = pcall(json.parse, content)
		if ok and parsed then
			for k, v in pairs(parsed) do
				settings[k] = v
			end
		end
	end
	
	return json_response(settings)
end

-- 获取系统信息
function action_system_info()
	local pkg_mgr = get_pkg_manager()
	
	-- 检测 OpenWrt 版本
	local version = '未知'
	local version_file = '/etc/openwrt_release'
	if fs and fs.stat(version_file) then
		local content = fs.readfile(version_file)
		if content then
			version = content:match("DISTRIB_DESCRIPTION='([^']+)'") or version
		end
	else
		version = sys.exec(string.format('cat %q 2>/dev/null | grep DISTRIB_DESCRIPTION | cut -d"\'" -f2', version_file)):match('^%s*(.-)%s*$') or version
	end
	
	-- 包管理器信息
	local pkg_mgr_version = '未知'
	if pkg_mgr == 'apk' then
		pkg_mgr_version = sys.exec('apk --version 2>/dev/null | head -1'):match('^%s*(.-)%s*$') or '未知'
	elseif pkg_mgr == 'opkg' then
		pkg_mgr_version = sys.exec('opkg --version 2>/dev/null | head -1'):match('^%s*(.-)%s*$') or '未知'
	end
	
	-- Docker 版本
	local docker_version = '未安装'
	if has_docker() then
		docker_version = sys.exec('docker --version 2>/dev/null'):match('^%s*(.-)%s*$') or '未知'
	end
	
	return json_response({
		openwrt_version = version,
		pkg_manager = pkg_mgr or '未找到',
		pkg_manager_version = pkg_mgr_version,
		docker_version = docker_version,
		docker_available = has_docker()
	})
end

-- 导出软件包列表
function action_export_list()
	local format = http.formvalue('format') or 'json'
	
	local pkg_mgr = get_pkg_manager()
	local packages = {}
	
	if pkg_mgr == 'apk' then
		packages = apk_list_installed()
	else
		packages = opkg_list_installed()
	end
	
	if format == 'json' then
		http.header('Content-Type', 'application/json')
		http.header('Content-Disposition', 'attachment; filename="packages.json"')
		http.write(json.stringify(packages, true))
	elseif format == 'txt' then
		http.header('Content-Type', 'text/plain')
		http.header('Content-Disposition', 'attachment; filename="packages.txt"')
		for _, pkg in ipairs(packages) do
			http.write(string.format('%s - %s\n', pkg.name, pkg.version))
		end
	else
		return json_response({ error = '不支持的导出格式' }, 400)
	end
end
