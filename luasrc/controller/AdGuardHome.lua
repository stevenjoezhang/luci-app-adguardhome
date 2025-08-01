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
	http.write('')
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
	fs.writefile("/var/run/AdG_log_pos","0")
	http.prepare_content("application/json")
	http.write('')
	local arg
	if luci.http.formvalue("force") == "1" then
		arg="force"
	else
		arg=""
	end
	if fs.access("/var/run/AdG_update_core") then
		if arg=="force" then
			luci.sys.exec("kill $(pgrep /usr/share/AdGuardHome/update_core.sh) ; sh /usr/share/AdGuardHome/update_core.sh "..arg.." >/tmp/AdGuardHome_update.log 2>&1 &")
		end
	else
		luci.sys.exec("sh /usr/share/AdGuardHome/update_core.sh "..arg.." >/tmp/AdGuardHome_update.log 2>&1 &")
	end
end
function get_log()
	local logfile=uci:get("AdGuardHome","AdGuardHome","logfile")
	if (logfile==nil) then
		http.write("no log available\n")
		return
	elseif (logfile=="syslog") then
		if not fs.access("/var/run/AdG_syslog") then
			luci.sys.exec("(/usr/share/AdGuardHome/getsyslog.sh &); sleep 1;")
		end
		logfile="/tmp/AdGuardHome.log"
		fs.writefile("/var/run/AdG_syslog","1")
	elseif not fs.access(logfile) then
		http.write("")
		return
	end
	http.prepare_content("text/plain; charset=utf-8")
	local fdp=tonumber(fs.readfile("/var/run/AdG_log_pos")) or 0
	local f=io.open(logfile, "r+")
	f:seek("set",fdp)
	local a=f:read(2048000) or ""
	fdp=f:seek()
	fs.writefile("/var/run/AdG_log_pos",tostring(fdp))
	f:close()
	http.write(a)
end
function do_dellog()
	local logfile=uci:get("AdGuardHome","AdGuardHome","logfile")
	fs.writefile(logfile,"")
	http.prepare_content("application/json")
	http.write('')
end
function check_update()
	http.prepare_content("text/plain; charset=utf-8")
	local fdp=tonumber(fs.readfile("/var/run/AdG_log_pos")) or 0
	local f=io.open("/tmp/AdGuardHome_update.log", "r+")
	f:seek("set",fdp)
	local a=f:read(2048000) or ""
	fdp=f:seek()
	fs.writefile("/var/run/AdG_log_pos",tostring(fdp))
	f:close()
if fs.access("/var/run/AdG_update_core") then
	http.write(a)
else
	http.write(a.."\0")
end
end
