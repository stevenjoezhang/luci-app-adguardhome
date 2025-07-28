require("luci.sys")
require("luci.util")
require("io")
local m,s,o,o1
local fs=require"nixio.fs"
local uci=require"luci.model.uci".cursor()
local configpath=uci:get("AdGuardHome","AdGuardHome","configpath") or "/etc/AdGuardHome.yaml"
local binpath=uci:get("AdGuardHome","AdGuardHome","binpath") or "/usr/bin/AdGuardHome/AdGuardHome"
httpport=uci:get("AdGuardHome","AdGuardHome","httpport") or "3000"
m = Map("AdGuardHome", "AdGuard Home")
m.description = translate("Free and open source, powerful network-wide ads & trackers blocking DNS server")
m:section(SimpleSection).template  = "AdGuardHome/AdGuardHome_status"

s = m:section(TypedSection, "AdGuardHome")
s.anonymous=true
s.addremove=false

---- Basic Settings ----
s:tab("basic", translate("Basic Settings"))

-- enable
o = s:taboption("basic", Flag, "enabled", translate("Enable"))
o.default = 0
o.optional = false

-- httpport
o = s:taboption("basic", Value, "httpport", translate("Browser management port"))
o.default=3000
o.datatype="port"
o.optional = false
o.description = translate("<input type=\"button\" style=\"width:210px;border-color:Teal; text-align:center;font-weight:bold;color:Green;\" value=\"AdGuardHome Web: "..httpport.."\" onclick=\"window.open('http://'+window.location.hostname+':"..httpport.."/')\"/>")

-- username
o = s:taboption("basic", Value, "username", translate("Browser management username"), translate("If no change is needed, leave it empty"))
o.default     = ""
o.datatype    = "string"
o.optional = false

-- chpass
o = s:taboption("basic", Value, "hashpass", translate("Browser management password"), translate("Press culculate and then save/apply").."<br/>"..translate("If no change is needed, leave it empty"))
o.default     = ""
o.datatype    = "string"
o.template = "AdGuardHome/AdGuardHome_chpass"
o.optional = false

-- update warning not safe
local e = ""
if not fs.access(binpath) then
	e = "<font color=red>"..translate("No core").."</font>"
else
	local tmp = luci.sys.exec(binpath.." --version 2>/dev/null | grep -m 1 -E '[0-9]+[.][Bbeta0-9\.\-]+' -o")
	local version = string.sub(tmp, 1, -2)
	if version == "" then
		e = "<font color=red>"..translate("Core error").."</font>"
	else
		e = "<font color=green>"..version.."</font>"
	end
end
if not fs.access(configpath) then
	e = e.." ".."<font color=red>"..translate("No config").."</font>"
end
o = s:taboption("basic", Button,"restart",translate("Update"))
o.inputtitle=translate("Update core version")
o.template = "AdGuardHome/AdGuardHome_update"
o.showfastconfig = (not fs.access(configpath))
o.description = string.format(translate("Core version:").." <strong><font color=green>%s</font></strong><br/>"..translate("If you've modified any related core settings, please save/apply the changes before clicking Update"), e)

-- Redirect
o = s:taboption("basic", ListValue, "redirect", translate("DNS redirect mode"))
o:value("none", translate("None"))
o:value("redirect", translate("Redirect 53 port to AdGuardHome"))
o:value("dnsmasq-upstream", translate("Run as dnsmasq upstream server"))
o:value("exchange", translate("Use port 53 replace dnsmasq"))
o.default     = "none"
o.optional = false

-- wait net on boot
o = s:taboption("basic", Flag, "waitonboot", translate("Restart when the network is ready after boot"))
o.default = 1
o.optional = false

-- upgrade protect
o = s:taboption("basic", DynamicList, "upprotect", translate("Keep files when system upgrade"))
o:value("$binpath",translate("core executable"))
o:value("$configpath",translate("config file"))
o:value("$logfile",translate("log file"))
o:value("$workdir/data/filters","filters")
o:value("$workdir/data/stats.db","stats.db")
o:value("$workdir/data/querylog.json","querylog.json")
o:value("$workdir/data/sessions.db","sessions.db")
o.default = nil
o.optional = false

-- backup workdir on shutdown
local workdir=uci:get("AdGuardHome","AdGuardHome","workdir") or "/usr/bin/AdGuardHome"
o = s:taboption("basic", MultiValue, "backupfile", translate("Backup workdir files when shutdown"))
o1 = s:taboption("basic", Value, "backupwdpath", translate("Backup workdir path"))
local name
o:value("filters","filters")
o:value("stats.db","stats.db")
o:value("querylog.json","querylog.json")
o:value("sessions.db","sessions.db")
o1:depends ("backupfile", "filters")
o1:depends ("backupfile", "stats.db")
o1:depends ("backupfile", "querylog.json")
o1:depends ("backupfile", "sessions.db")
for name in fs.glob(workdir.."/data/*")
do
	name=fs.basename (name)
	if name~="filters" and name~="stats.db" and name~="querylog.json" and name~="sessions.db" then
		o:value(name,name)
		o1:depends ("backupfile", name)
	end
end
o.widget = "checkbox"
o.default = nil
o.optional=false
o.description=translate("Will be restore when workdir/data is empty")

-- backup workdir path

o1.default     = "/usr/bin/AdGuardHome"
o1.datatype    = "string"
o1.optional = false
o1.validate=function(self, value)
if fs.stat(value,"type")=="reg" then
	if m.message then
	m.message =m.message.."\nerror!backup dir is a file"
	else
	m.message ="error!backup dir is a file"
	end
	return nil
end
if string.sub(value,-1)=="/" then
	return string.sub(value, 1, -2)
else
	return value
end
end

---- Core Settings ----
s:tab("core", translate("Core Settings"))

-- bin path
o = s:taboption("core", Value, "binpath", translate("AdGuardHome executable file path"), translate("If the executable file does not exist, it will be downloaded automatically"))
o.default     = "/usr/bin/AdGuardHome/AdGuardHome"
o.datatype    = "string"
o.optional = false
o.rmempty=false
o.validate=function(self, value)
if value=="" then return nil end
if fs.stat(value,"type")=="dir" then
	fs.rmdir(value)
end
if fs.stat(value,"type")=="dir" then
	if (m.message) then
	m.message =m.message.."\nerror!bin path is a dir"
	else
	m.message ="error!bin path is a dir"
	end
	return nil
end 
return value
end
--- arch
o = s:taboption("core", ListValue, "arch", translate("Executable file architecture"))
o:value("",translate("Auto"))
o:value("386",translate("i386"))
o:value("amd64",translate("x86_64"))
o:value("armv5",translate("armv5"))
o:value("armv6",translate("armv6"))
o:value("armv7",translate("armv7"))
o:value("arm64",translate("aarch64"))
o:value("mips_softfloat",translate("mips"))
o:value("mips64_softfloat",translate("mips64"))
o:value("mipsle_softfloat",translate("mipsel"))
o:value("mips64le_softfloat",translate("mips64el"))
o:value("ppc64le",translate("powerpc64"))
o.default=""
o.rmempty=true

--- upx
o = s:taboption("core", ListValue, "upxflag", translate("Use upx to compress executable"))
o:value("", translate("None"))
o:value("-1", translate("Compress faster"))
o:value("-9", translate("Compress better"))
o:value("--best", translate("Compress best (slow)"))
o:value("--brute", translate("Try all available compression methods & filters (slower)"))
o:value("--ultra-brute", translate("Try even more compression variants (very slow)"))
o.default     = ""
o.description=translate("Reduce executable size, but may have compatibility issues after compression")
o.rmempty = true

-- config path
o = s:taboption("core", Value, "configpath", translate("Config path"))
o.default     = "/etc/AdGuardHome.yaml"
o.datatype    = "string"
o.optional = false
o.rmempty=false
o.validate=function(self, value)
if value==nil then return nil end
if fs.stat(value,"type")=="dir" then
	fs.rmdir(value)
end
if fs.stat(value,"type")=="dir" then
	if m.message then
	m.message =m.message.."\nerror!config path is a dir"
	else
	m.message ="error!config path is a dir"
	end
	return nil
end 
return value
end

-- work dir
o = s:taboption("core", Value, "workdir", translate("Work dir"), translate("AdGuardHome work dir will store query logs, database and other files"))
o.default     = "/usr/bin/AdGuardHome"
o.datatype    = "string"
o.optional = false
o.rmempty=false
o.validate=function(self, value)
if value=="" then return nil end
if fs.stat(value,"type")=="reg" then
	if m.message then
	m.message =m.message.."\nerror!work dir is a file"
	else
	m.message ="error!work dir is a file"
	end
	return nil
end 
if string.sub(value, -1)=="/" then
	return string.sub(value, 1, -2)
else
	return value
end
end

-- log file
o = s:taboption("core", Value, "logfile", translate("Runtime log file path"), translate("If set to syslog, logs will be written to the system log; if left empty, no logs will be recorded"))
o.datatype    = "string"
o.rmempty = true
o.validate=function(self, value)
if fs.stat(value,"type")=="dir" then
	fs.rmdir(value)
end
if fs.stat(value,"type")=="dir" then
	if m.message then
	m.message =m.message.."\nerror!log file is a dir"
	else
	m.message ="error!log file is a dir"
	end
	return nil
end 
return value
end

-- debug
o = s:taboption("core", Flag, "verbose", translate("Verbose log"))
o.default = 0
o.optional = false

-- downloadpath
o = s:taboption("core", TextValue, "downloadlinks",translate("Download links for update"))
o.optional = false
o.rows = 4
o.wrap = "soft"
o.default = "https://static.adguard.com/adguardhome/release/AdGuardHome_linux_${Arch}.tar.gz\
#https://static.adguard.com/adguardhome/beta/AdGuardHome_linux_${Arch}.tar.gz\
https://github.com/AdguardTeam/AdGuardHome/releases/download/${latest_ver}/AdGuardHome_linux_${Arch}.tar.gz"

---- Crontab Settings ----
s:tab("crontab", translate("Crontab Settings"))

o = s:taboption("crontab", MultiValue, "crontab", translate("Crontab task"),translate("Please change time and args in crontab"))
o:value("autohost",translate("Auto update ipv6 hosts and restart AdGuardHome"))
o:value("autogfw",translate("Auto update gfwlist and restart AdGuardHome"))
o:value("autogfwipset",translate("Auto update ipset list and restart AdGuardHome"))
o.widget = "checkbox"
o.default = nil
o.optional = false

---- GFWList Settings ----
s:tab("gfwlist", translate("GFWList Settings"))

-- gfwlist
local a
if fs.access(configpath) then
a=luci.sys.call("grep -m 1 -q programadd "..configpath)
else
a=1
end
if (a==0) then
a="Added"
else
a="Not added"
end
o=s:taboption("gfwlist", Button,"gfwdel",translate("Del gfwlist"),translate(a))
o.optional = false
o.inputtitle=translate("Del")
o.write=function()
	luci.sys.exec("sh /usr/share/AdGuardHome/gfw2adg.sh del 2>&1")
	luci.http.redirect(luci.dispatcher.build_url("admin","services","AdGuardHome"))
end
o=s:taboption("gfwlist", Button,"gfwadd",translate("Add gfwlist"),translate(a))
o.optional = false
o.inputtitle=translate("Add")
o.write=function()
	luci.sys.exec("sh /usr/share/AdGuardHome/gfw2adg.sh 2>&1")
	luci.http.redirect(luci.dispatcher.build_url("admin","services","AdGuardHome"))
end
if fs.access(configpath) then
a=luci.sys.call("grep -m 1 -q ipset.txt "..configpath)
else
a=1
end
if (a==0) then
a="Added"
else
a="Not added"
end
o=s:taboption("gfwlist", Button,"gfwipsetdel",translate("Del gfwlist")..translate("(ipset only)"),translate(a))
o.optional = false
o.inputtitle=translate("Del")
o.write=function()
	luci.sys.exec("sh /usr/share/AdGuardHome/gfwipset2adg.sh del 2>&1")
	luci.http.redirect(luci.dispatcher.build_url("admin","services","AdGuardHome"))
end
o=s:taboption("gfwlist", Button,"gfwipsetadd",translate("Add gfwlist")..translate("(ipset only)"),translate(a).." "..translate("will set to name gfwlist"))
o.optional = false
o.inputtitle=translate("Add")
o.write=function()
	luci.sys.exec("sh /usr/share/AdGuardHome/gfwipset2adg.sh 2>&1")
	luci.http.redirect(luci.dispatcher.build_url("admin","services","AdGuardHome"))
end
o = s:taboption("gfwlist", Value, "gfwupstream", translate("Gfwlist upstream dns server"), translate("Gfwlist domain upstream dns service")..translate(a))
o.default     = "tcp://208.67.220.220:5353"
o.datatype    = "string"
o.optional = false

fs.writefile("/var/run/AdG_log_pos","0")

return m