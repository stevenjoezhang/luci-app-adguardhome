module("luci.controller.AdGuardHome",package.seeall)
local fs=require"nixio.fs"
local http=require"luci.http"
local uci=require"luci.model.uci".cursor()
function index()
entry({"admin", "services", "AdGuardHome"},alias("admin", "services", "AdGuardHome", "base"),_("AdGuard Home"), 10).dependent = true
entry({"admin","services","AdGuardHome","base"},cbi("AdGuardHome/base"),_("Plugin Settings"),1).leaf = true
entry({"admin","services","AdGuardHome","log"},form("AdGuardHome/log"),_("Log"),2).leaf = true
entry({"admin","services","AdGuardHome","manual"},cbi("AdGuardHome/manual"),_("Manual Config"),3).leaf = true
entry({"admin","services","AdGuardHome","status"},call("act_status")).leaf=true
entry({"admin", "services", "AdGuardHome", "check"}, call("check_update"))
entry({"admin", "services", "AdGuardHome", "doupdate"}, call("do_update"))
entry({"admin", "services", "AdGuardHome", "getlog"}, call("get_log"))
entry({"admin", "services", "AdGuardHome", "dodellog"}, call("do_dellog"))
entry({"admin", "services", "AdGuardHome", "reloadconfig"}, call("reload_config"))
entry({"admin", "services", "AdGuardHome", "gettemplateconfig"}, call("get_template_config"))
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
