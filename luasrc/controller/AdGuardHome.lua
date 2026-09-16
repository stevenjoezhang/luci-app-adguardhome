module("luci.controller.AdGuardHome",package.seeall)
local fs=require"nixio.fs"
local http=require"luci.http"
local uci=require"luci.model.uci".cursor()
function index()
entry({"admin", "services", "AdGuardHome"},alias("admin", "services", "AdGuardHome", "base"),_("AdGuard Home"), 10).dependent = true
entry({"admin","services","AdGuardHome","base"},cbi("AdGuardHome/base"),_("Plugin Settings"),1).leaf = true
entry({"admin","services","AdGuardHome","manual"},cbi("AdGuardHome/manual"),_("Manual Config"),2).leaf = true
entry({"admin","services","AdGuardHome","log"},form("AdGuardHome/log"),_("Log"),3).leaf = true
entry({"admin","services","AdGuardHome","status"},call("act_status")).leaf=true
entry({"admin", "services", "AdGuardHome", "check"}, call("check_update"))
entry({"admin", "services", "AdGuardHome", "doupdate"}, call("do_update"))
entry({"admin", "services", "AdGuardHome", "getlog"}, call("get_log"))
entry({"admin", "services", "AdGuardHome", "dodellog"}, call("do_dellog"))
entry({"admin", "services", "AdGuardHome", "reloadconfig"}, call("reload_config"))
entry({"admin", "services", "AdGuardHome", "gettemplateconfig"}, call("get_template_config"))
entry({"admin", "services", "AdGuardHome", "upstream_file"}, call("get_upstream_file"))
end 
function get_template_config()
	local template_file = "/usr/share/AdGuardHome/AdGuardHome_template.yaml"
	http.prepare_content("text/plain; charset=utf-8")

	if fs.access(template_file) then
		local content = fs.readfile(template_file)
		http.write(content or "")
	else
		http.write("")
	end
end

local function trim_config_value(value)
	value = (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if (value:sub(1, 1) == "'" and value:sub(-1) == "'") or
	   (value:sub(1, 1) == '"' and value:sub(-1) == '"') then
		value = value:sub(2, -2)
	end
	return value
end

-- Read the active upstream_dns_file from the core YAML.  The UCI option is
-- only a fallback because the native AdGuard Home editor may change the YAML
-- path without updating the plugin's UCI value.
local function read_dns_option(path, name)
	if not path or not fs.access(path) then return nil end
	local data = fs.readfile(path) or ""
	local in_dns = false
	for line in data:gmatch("[^\n]+") do
		line = line:gsub("\r$", "")
		if line:match("^dns:%s*$") then
			in_dns = true
		elseif in_dns and line:match("^%S") then
			in_dns = false
		end
		if in_dns then
			local value = line:match("^%s+"..name..":%s*(.-)%s*$")
			if value ~= nil then return trim_config_value(value) end
		end
	end
	return nil
end

function get_upstream_file()
	local configpath = uci:get("AdGuardHome", "AdGuardHome", "configpath")
	if not configpath or configpath == "" then configpath = "/etc/AdGuardHome.yaml" end
	local path = read_dns_option(configpath, "upstream_dns_file")
	if not path or path == "" then
		path = uci:get("AdGuardHome", "AdGuardHome", "upstream_dns_file")
	end
	if not path or path == "" then path = "/usr/bin/AdGuardHome/upstream_dns.conf" end
	-- Only allow absolute, local paths supplied by the administrator.
	if path:sub(1, 1) ~= "/" or path:find("[^%w%._/-]") then
		http.prepare_content("text/plain; charset=utf-8")
		http.write("")
		return
	end
	http.prepare_content("text/plain; charset=utf-8")
	local file = io.open(path, "rb")
	if not file then
		http.write("")
		return
	end
	-- Stream in chunks instead of loading a potentially large generated file
	-- into one LuCI response string.
	while true do
		local chunk = file:read(32768)
		if not chunk then break end
		http.write(chunk)
	end
	file:close()
end
function reload_config()
	fs.remove("/tmp/AdGuardHometmpconfig.yaml")
	http.prepare_content("application/json")
	http.write("{}")
end
function act_status()
	local e={}
	local binpath=uci:get("AdGuardHome","AdGuardHome","binpath")
	e.running=luci.sys.call("pgrep "..binpath.." >/dev/null")==0
	e.redirect=(fs.readfile("/var/run/AdG_redir")=="1")
	http.prepare_content("application/json")
	http.write_json(e)
end
function do_update()
	local arg
	if luci.http.formvalue("force") == "1" then
		arg="force"
	else
		arg=""
	end
	if luci.sys.call("pgrep -f /usr/share/AdGuardHome/update_core.sh >/dev/null") == 0 then
		if arg=="force" then
			luci.sys.exec("kill $(pgrep -f /usr/share/AdGuardHome/update_core.sh) ; sh /usr/share/AdGuardHome/update_core.sh "..arg.." >/tmp/AdGuardHome_update.log 2>&1 &")
		end
	else
		luci.sys.exec("sh /usr/share/AdGuardHome/update_core.sh "..arg.." >/tmp/AdGuardHome_update.log 2>&1 &")
	end
	http.prepare_content("application/json")
	http.write("{}")
end
function get_log()
	http.prepare_content("application/json")
	local logfile=uci:get("AdGuardHome","AdGuardHome","logfile")
	if (logfile==nil) then
		http.write_json({ pos = 0, content = "" })
		return
	elseif (logfile=="syslog") then
		if not fs.access("/var/run/AdG_syslog") then
			luci.sys.exec("(/usr/share/AdGuardHome/getsyslog.sh &); sleep 1;")
		end
		logfile="/tmp/AdGuardHome.log"
		fs.writefile("/var/run/AdG_syslog","1")
	elseif not fs.access(logfile) then
		http.write_json({ pos = 0, content = "" })
		return
	end
	-- support client-managed position via ?pos=
	local pos = tonumber(luci.http.formvalue("pos")) or 0
	local f = io.open(logfile, "r")
	local content = ""
	local newpos = pos
	if f then
		f:seek("set", pos)
		content = f:read(1048576) or ""
		newpos = f:seek()
		f:close()
	end
	http.write_json({ pos = newpos, content = content })
end
function do_dellog()
	local logfile=uci:get("AdGuardHome","AdGuardHome","logfile")
	fs.writefile(logfile,"")
	http.prepare_content("application/json")
	http.write("{}")
end
function check_update()
	-- Now supports client-managed position: accepts `pos` param and returns JSON
	local pos = tonumber(luci.http.formvalue("pos")) or 0
	local fpath = "/tmp/AdGuardHome_update.log"
	local content = ""
	local newpos = pos
	if fs.access(fpath) then
		local f = io.open(fpath, "r")
		if f then
			f:seek("set", pos)
			content = f:read(1048576) or ""
			newpos = f:seek()
			f:close()
		end
	end

	local running = luci.sys.call("pgrep -f /usr/share/AdGuardHome/update_core.sh >/dev/null") == 0
	local status
	if running then
		status = "running"
	elseif fs.access("/var/run/AdG_update_error") then
		status = "failed"
	else
		status = "succeeded"
	end

	http.prepare_content("application/json")
	http.write_json({ pos = newpos, content = content, status = status })
end
