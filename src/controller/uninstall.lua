-- SPDX-License-Identifier: Apache-2.0
-- LuCI Advanced Uninstall Manager Controller

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
end

-- 引入必要的库
local http = require 'luci.http'
local sys = require 'luci.sys'
local ipkg = require 'luci.model.ipkg'
local json = require 'luci.jsonc'
local fs = require 'nixio.fs'
local util = require 'luci.util'

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
	if not fs.stat(CONFIG_DIR) then
		fs.mkdirr(CONFIG_DIR)
	end
end

-- 写入日志
local function write_log(message)
	ensure_config_dir()
	local timestamp = os.date('%Y-%m-%d %H:%M:%S')
	local log_entry = string.format('[%s] %s\n', timestamp, message)
	
	local f = io.open(LOG_FILE, 'a')
	if f then
		f:write(log_entry)
		f:close()
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

-- 获取已安装的软件包列表
function action_list()
	local packages = {}
	
	-- 获取所有已安装的包
	local installed = sys.exec('opkg list-installed 2>/dev/null')
	if not installed or installed == '' then
		return json_response({ packages = {}, total = 0 })
	end
	
	for line in installed:gmatch('[^\r\n]+') do
		local name, version, desc = line:match('^([^%s]+)%s*%- ([^%s]+)')
		if name then
			-- 获取包大小
			local size_cmd = string.format('opkg status %s 2>/dev/null | grep "^Installed-Size:" | cut -d: -f2', name)
			local size = sys.exec(size_cmd):match('^%s*(.-)%s*$') or '0'
			
			-- 检查是否有 Docker 容器
			local docker_containers = get_docker_containers(name)
			
			-- 获取依赖信息
			local dep_cmd = string.format('opkg info %s 2>/dev/null | grep "^Depends:" | cut -d: -f2', name)
			local depends = sys.exec(dep_cmd):match('^%s*(.-)%s*$') or ''
			
			table.insert(packages, {
				name = name,
				version = version or '',
				size = tonumber(size) or 0,
				depends = depends,
				has_docker = #docker_containers > 0,
				docker_containers = docker_containers,
				description = desc or ''
			})
		end
	end
	
	-- 按名称排序
	table.sort(packages, function(a, b) return a.name < b.name end)
	
	return json_response({
		packages = packages,
		total = #packages
	})
end

-- 获取软件包详细信息
function action_info()
	local pkg = http.formvalue('package')
	if not pkg or pkg == '' then
		return json_response({ error = '未指定软件包名称' }, 400)
	end
	
	-- 获取包信息
	local info_cmd = string.format('opkg info %s 2>/dev/null', pkg)
	local info_output = sys.exec(info_cmd)
	
	if not info_output or info_output == '' then
		return json_response({ error = '软件包不存在' }, 404)
	end
	
	local info = {}
	for line in info_output:gmatch('[^\r\n]+') do
		local key, value = line:match('^([^:]+):%s*(.*)')
		if key then
			info[key:lower():gsub('%-', '_')] = value
		end
	end
	
	-- 获取文件列表
	local files_cmd = string.format('opkg files %s 2>/dev/null', pkg)
	local files_output = sys.exec(files_cmd)
	local files = {}
	if files_output then
		for file in files_output:gmatch('[^\r\n]+') do
			if not file:match('^%s*$') and not file:match('^Package') then
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
		docker_containers = docker_containers
	})
end

-- 获取依赖关系
function action_dependencies()
	local pkg = http.formvalue('package')
	if not pkg or pkg == '' then
		return json_response({ error = '未指定软件包名称' }, 400)
	end
	
	-- 获取依赖
	local depends_cmd = string.format('opkg info %s 2>/dev/null | grep "^Depends:" | cut -d: -f2', pkg)
	local depends_str = sys.exec(depends_cmd):match('^%s*(.-)%s*$') or ''
	
	local dependencies = {}
	local dependents = {}
	
	-- 解析依赖
	if depends_str ~= '' then
		for dep in depends_str:gmatch('[^,]+') do
			dep = dep:match('^%s*(.-)%s*$')
			if dep and dep ~= '' then
				table.insert(dependencies, dep)
			end
		end
	end
	
	-- 获取反向依赖（哪些包依赖此包）
	local all_packages = sys.exec('opkg list-installed 2>/dev/null')
	if all_packages then
		for line in all_packages:gmatch('[^\r\n]+') do
			local name = line:match('^([^%s]+)')
			if name and name ~= pkg then
				local check_cmd = string.format('opkg info %s 2>/dev/null | grep "^Depends:" | grep -w "%s"', name, pkg)
				if sys.call(check_cmd .. ' >/dev/null 2>&1') == 0 then
					table.insert(dependents, name)
				end
			end
		end
	end
	
	return json_response({
		package = pkg,
		dependencies = dependencies,
		dependents = dependents
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
	
	-- 检查包是否存在
	local check_cmd = string.format('opkg status %s 2>/dev/null | grep -q "^Status:"', pkg)
	if sys.call(check_cmd) ~= 0 then
		return json_response({ error = '软件包未安装' }, 404)
	end
	
	-- 获取 Docker 容器
	local docker_containers = get_docker_containers(pkg)
	
	-- 如果需要清理 Docker 容器
	local docker_cleaned = {}
	if remove_docker and #docker_containers > 0 then
		for _, container in ipairs(docker_containers) do
			local stop_cmd = string.format('docker stop %s 2>/dev/null', container)
			local rm_cmd = string.format('docker rm -f %s 2>/dev/null', container)
			sys.call(stop_cmd)
			if sys.call(rm_cmd) == 0 then
				table.insert(docker_cleaned, container)
				write_log(string.format('Docker 容器已删除: %s', container))
			end
		end
	end
	
	-- 卸载包
	local remove_cmd = string.format('opkg remove %s', pkg)
	if force then
		remove_cmd = remove_cmd .. ' --force-remove'
	end
	if remove_deps then
		remove_cmd = remove_cmd .. ' --autoremove'
	end
	
	local result = sys.call(remove_cmd .. ' 2>&1')
	
	if result == 0 then
		write_log(string.format('软件包已卸载: %s', pkg))
		return json_response({
			ok = true,
			message = string.format('软件包 %s 已成功卸载', pkg),
			docker_cleaned = docker_cleaned
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
	
	-- 解析包列表
	local packages = json.parse(packages_str)
	if not packages or type(packages) ~= 'table' then
		return json_response({ error = '无效的软件包列表格式' }, 400)
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
			local remove_cmd = string.format('opkg remove %s', pkg)
			if force then
				remove_cmd = remove_cmd .. ' --force-remove'
			end
			
			if sys.call(remove_cmd .. ' >/dev/null 2>&1') == 0 then
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
		message = string.format('成功卸载 %d 个包，失败 %d 个', #results.success, #results.failed)
	})
end

-- 搜索软件包相关文件
function action_search_files()
	local keyword = http.formvalue('keyword')
	if not keyword or keyword == '' then
		return json_response({ error = '未指定搜索关键词' }, 400)
	end
	
	-- 使用 opkg search 或 find 命令搜索
	local results = {}
	
	-- 搜索已安装包的文件
	local search_cmd = string.format('find /usr /etc /opt -name "*%s*" -type f 2>/dev/null | head -100', keyword)
	local found_files = sys.exec(search_cmd)
	
	if found_files and found_files ~= '' then
		for file in found_files:gmatch('[^\r\n]+') do
			-- 查找文件所属的包
			local owner_cmd = string.format('opkg search %s 2>/dev/null | cut -d: -f1', file)
			local owner = sys.exec(owner_cmd):match('^%s*(.-)%s*$') or '未知'
			
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
	
	-- 验证 URL 格式
	if not url:match('^https?://') then
		return json_response({ error = '无效的 URL 格式' }, 400)
	end
	
	ensure_config_dir()
	
	-- 下载文件
	local filename = url:match('[^/]+%.ipk$') or 'package.ipk'
	local filepath = CONFIG_DIR .. '/' .. filename
	
	local download_cmd = string.format('wget -q -O %q %q 2>&1', filepath, url)
	local result = sys.call(download_cmd)
	
	if result ~= 0 then
		-- 尝试使用 curl
		download_cmd = string.format('curl -sL -o %q %q 2>&1', filepath, url)
		result = sys.call(download_cmd)
	end
	
	if result ~= 0 then
		return json_response({ error = '下载失败' }, 500)
	end
	
	-- 安装包
	local install_cmd = string.format('opkg install --force-reinstall --force-overwrite %q 2>&1', filepath)
	result = sys.call(install_cmd)
	
	-- 清理临时文件
	fs.remove(filepath)
	
	if result == 0 then
		write_log(string.format('从 URL 安装成功: %s', url))
		return json_response({
			ok = true,
			message = '安装成功'
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
	local filedata = ''
	
	luci.http.setfilehandler(function(meta, chunk, eof)
		if not fp then
			if meta and meta.file then
				ensure_config_dir()
				fp = io.open(CONFIG_DIR .. '/upload.ipk', 'wb')
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
	local value = http.formvalue('file')
	
	local filepath = CONFIG_DIR .. '/upload.ipk'
	
	if not fs.stat(filepath) then
		return json_response({ error = '文件上传失败' }, 400)
	end
	
	-- 安装包
	local install_cmd = string.format('opkg install --force-reinstall --force-overwrite %q 2>&1', filepath)
	local result = sys.call(install_cmd)
	
	-- 清理
	fs.remove(filepath)
	
	if result == 0 then
		write_log('上传安装成功')
		return json_response({
			ok = true,
			message = '安装成功'
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
	
	local check_cmd = string.format('opkg status %s 2>/dev/null | grep "^Status:"', pkg)
	local status = sys.exec(check_cmd)
	
	local installed = status and status:match('install ok installed') ~= nil
	
	return json_response({
		package = pkg,
		installed = installed
	})
end

-- 检查 Docker 环境
function action_check_docker()
	local available = has_docker()
	local running = false
	local containers = {}
	
	if available then
		-- 检查 Docker 是否运行
		running = sys.call('docker info >/dev/null 2>&1') == 0
		
		if running then
			-- 获取运行中的容器
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
	
	-- 停止并删除容器
	sys.call(string.format('docker stop %q 2>/dev/null', container))
	
	local rm_cmd = string.format('docker rm -f %q 2>/dev/null', container)
	local result = sys.call(rm_cmd)
	
	if result == 0 then
		-- 可选：删除关联的卷
		if remove_volumes then
			sys.call(string.format('docker volume rm $(docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}} {{end}}{{end}}' %q 2>/dev/null) 2>/dev/null || true', container))
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
	
	if fs.stat(LOG_FILE) then
		local content = fs.readfile(LOG_FILE)
		if content then
			local lines = {}
			for line in content:gmatch('[^\r\n]+') do
				table.insert(lines, line)
			end
			
			-- 获取最后 N 行
			local start_idx = math.max(1, #lines - limit + 1)
			for i = start_idx, #lines do
				table.insert(logs, lines[i])
			end
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
	
	-- 写入设置文件
	local content = json.stringify(data, true)
	local tmp_file = SETTINGS_FILE .. '.tmp'
	
	fs.writefile(tmp_file, content)
	sys.call(string.format('mv -f %q %q', tmp_file, SETTINGS_FILE))
	
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
	
	if fs.stat(SETTINGS_FILE) then
		local content = fs.readfile(SETTINGS_FILE)
		if content then
			local ok, parsed = pcall(json.parse, content)
			if ok and parsed then
				for k, v in pairs(parsed) do
					settings[k] = v
				end
			end
		end
	end
	
	return json_response(settings)
end

-- 导出软件包列表
function action_export_list()
	local format = http.formvalue('format') or 'json'
	
	local installed = sys.exec('opkg list-installed 2>/dev/null')
	local packages = {}
	
	if installed then
		for line in installed:gmatch('[^\r\n]+') do
			local name, version = line:match('^([^%s]+)%s*%- ([^%s]+)')
			if name then
				table.insert(packages, {
					name = name,
					version = version or ''
				})
			end
		end
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
