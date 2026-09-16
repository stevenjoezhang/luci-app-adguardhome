require("luci.sys")
require("luci.util")
require("io")
local m,s,o,o1
local fs=require"nixio.fs"
local uci=require"luci.model.uci".cursor()
local configpath=uci:get("AdGuardHome","AdGuardHome","configpath") or "/etc/AdGuardHome.yaml"
local binpath=uci:get("AdGuardHome","AdGuardHome","binpath") or "/usr/bin/AdGuardHome/AdGuardHome"
local upstream_changed = false
local upstream_queue_dir = "/tmp/AdGuardHome-upstream"

local function upstream_update_pending()
	return fs.access(upstream_queue_dir.."/state") or
	       fs.access(upstream_queue_dir.."/pending") or
	       fs.access(upstream_queue_dir.."/lock")
end
httpport=uci:get("AdGuardHome","AdGuardHome","httpport") or "3000"
m = Map("AdGuardHome", "AdGuard Home")
m.description = translate("A powerful LuCI interface for managing AdGuard Home - a DNS-based ad and tracker blocker that protects all devices on your network").."<br/>"..translate("<a href=\"https://github.com/stevenjoezhang/luci-app-adguardhome\" target=\"_blank\">⭐ Star on GitHub</a>")
m:section(SimpleSection).template  = "AdGuardHome/status"

-- Apply an upstream update once after a successful save of any takeover setting.
m.on_after_commit = function()
	if upstream_changed then
		luci.sys.exec("/usr/share/AdGuardHome/update_upstream.sh --queue >>/tmp/AdGuardHome_upstream_update.log 2>&1 &")
		upstream_changed = false
	end
end

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
o.description = translate("<input type=\"button\" class=\"cbi-button cbi-button-apply\" value=\"AdGuardHome Web: "..httpport.."\" onclick=\"window.open('http://'+window.location.hostname+':"..httpport.."/')\"/>")

-- username
o = s:taboption("basic", Value, "username", translate("Browser management username"), translate("If no change is needed, leave it empty"))
o.default     = ""
o.datatype    = "string"
o.optional = false

-- chpass
o = s:taboption("basic", Value, "hashpass", translate("Browser management password"), translate("Press calculate and then save/apply").."<br/>"..translate("If no change is needed, leave it empty"))
o.default     = ""
o.datatype    = "string"
o.template = "AdGuardHome/chpass"
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
o.template = "AdGuardHome/update"
o.showfastconfig = (not fs.access(configpath))
o.description = string.format(translate("Core version:").." <strong><font color=green>%s</font></strong><br/>"..translate("If you've modified any related core settings, please save/apply the changes before clicking Update"), e)

-- Redirect
o = s:taboption("basic", ListValue, "redirect", translate("DNS redirect mode"))
o:value("none", translate("None"))
o:value("redirect", translate("Redirect 53 port to AdGuardHome"))
o:value("dnsmasq-upstream", translate("Run as dnsmasq upstream server"))
o:value("exchange", translate("Use port 53 to replace dnsmasq"))
o.default     = "none"
o.optional = false

-- wait net on boot
o = s:taboption("basic", Flag, "waitonboot", translate("Restart when the network is ready after boot"))
o.default = 1
o.optional = false

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
o:value("386", "i386")
o:value("amd64", "x86_64")
o:value("armv5", "armv5")
o:value("armv6", "armv6")
o:value("armv7", "armv7")
o:value("arm64", "aarch64")
o:value("mips_softfloat", "mips")
o:value("mips64_softfloat", "mips64")
o:value("mipsle_softfloat", "mipsel")
o:value("mips64le_softfloat", "mips64el")
o:value("ppc64le", "powerpc64")
o:value("riscv64", "riscv64")
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
o.default = [[https://static.adguard.com/adguardhome/release/AdGuardHome_linux_${Arch}.tar.gz
#https://static.adguard.com/adguardhome/beta/AdGuardHome_linux_${Arch}.tar.gz
https://github.com/AdguardTeam/AdGuardHome/releases/download/${latest_ver}/AdGuardHome_linux_${Arch}.tar.gz]]

---- Upstream DNS takeover ----
local upstream_default_file = "/usr/bin/AdGuardHome/upstream_dns.conf"
local domain_list_default = "https://cdn.jsdelivr.net/gh/gfwlist/gfwlist/gfwlist.txt"
local global_upstreams_default = [[https://dns.alidns.com/dns-query
https://doh.pub/dns-query]]
local domain_upstreams_default = "https://dns.google/dns-query"

local global_upstream_examples = {
	{"94.140.14.140, 2a10:50c0::1:ff", "Plain DNS (UDP)"},
	{"94.140.14.140:53, [2a10:50c0::1:ff]:53", "Plain DNS (UDP with port)"},
	{"udp://unfiltered.adguard-dns.com", "Plain DNS (UDP, hostname)"},
	{"tcp://94.140.14.140, tcp://[2a10:50c0::1:ff]", "Plain DNS over TCP"},
	{"tcp://94.140.14.140:53, tcp://[2a10:50c0::1:ff]:53", "Plain DNS over TCP with port"},
	{"tcp://unfiltered.adguard-dns.com", "Plain DNS over TCP, hostname"},
	{"tls://unfiltered.adguard-dns.com", "Encrypted DNS-over-TLS"},
	{"https://unfiltered.adguard-dns.com/dns-query", "Encrypted DNS-over-HTTPS"},
	{"h3://unfiltered.adguard-dns.com/dns-query", "Encrypted DNS-over-HTTPS with forced HTTP/3, without fallback to HTTP/2 or lower"},
	{"quic://unfiltered.adguard-dns.com", "Encrypted DNS-over-QUIC"},
	{"sdns://...", "DNSCrypt stamp or DNS-over-HTTPS resolver"},
	{"[/example.local/]94.140.14.140", "Upstream server for a specific domain"},
	{"[/example.local/]94.140.14.140 2a10:50c0::1:ff", "Multiple upstream servers for a specific domain"},
	{"# comment", "Comment"}
}
local global_upstream_rows = {}
for _, example in ipairs(global_upstream_examples) do
	table.insert(global_upstream_rows, "<tr><td><code style=\"white-space:pre\">"..example[1].."</code></td><td>"..translate(example[2]).."</td></tr>")
end
local global_upstream_help = [[<details><summary>]]..translate("Show AdGuard Home upstream_dns format examples")..[[</summary><div style="overflow-x:auto"><table style="border-collapse:collapse;width:100%"><thead><tr><th style="text-align:left;padding:0.25em 0.5em">]]..translate("Format")..[[</th><th style="text-align:left;padding:0.25em 0.5em">]]..translate("Description")..[[</th></tr></thead><tbody>]]..table.concat(global_upstream_rows)..[[</tbody></table></div></details>]]

local function trim_value(value)
	local result = (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
	return result
end

-- Read a value from the existing AdGuard Home dns mapping.  This allows the
-- page to reflect changes made in the native AdGuard Home editor as well.
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
			if value ~= nil then
				value = trim_value(value)
				if (value:sub(1, 1) == "'" and value:sub(-1) == "'") or
				   (value:sub(1, 1) == '"' and value:sub(-1) == '"') then
					value = value:sub(2, -2)
				end
				return value
			end
		end
	end
	return nil
end

local function bootstrap_is_empty(path)
	if not path or not fs.access(path) then return true end
	local data = fs.readfile(path) or ""
	local in_dns, waiting_for_list = false, false
	for line in data:gmatch("[^\n]+") do
		line = line:gsub("\r$", "")
		if line:match("^dns:%s*$") then
			in_dns = true
		elseif in_dns and line:match("^%S") then
			in_dns, waiting_for_list = false, false
		end
		if in_dns then
			local value = line:match("^%s+bootstrap_dns:%s*(.*)$")
			if value then
				value = trim_value(value)
				if value ~= "" and value:gsub("%s", "") ~= "[]" then return false end
				waiting_for_list = (value == "")
			elseif waiting_for_list and line:match("^%s+%-[%s%S]*") then
				return false
			elseif waiting_for_list and line:match("^%s+%S") then
				waiting_for_list = false
			end
		end
	end
	return true
end

local function mark_upstream_write(self, section, value)
	upstream_changed = true
	return self.map:set(section, self.option, value)
end

local function mark_upstream_remove(self, section)
	upstream_changed = true
	return self.map:del(section, self.option)
end

local bootstrap_empty = bootstrap_is_empty(configpath)

s:tab("upstream", translate("Upstream DNS takeover"))

o = s:taboption("upstream", Flag, "upstream_enabled", translate("Enable upstream DNS takeover"))
o.default = 0
o.optional = false
o.cfgvalue = function(self, section)
	-- While an update request is queued or running, show the user's desired
	-- value.  Once the queue is empty, reflect the actual core YAML pointer.
	if upstream_update_pending() then
		return self.map:get(section, self.option) == "1" and "1" or "0"
	end
		if fs.access(configpath) then
			local configured = read_dns_option(configpath, "upstream_dns_file")
			return (configured and configured ~= "") and "1" or "0"
		end
		return "0"
end
o.validate = function(self, value)
	if value == "1" and bootstrap_empty then
		m.message = translate("Bootstrap DNS is empty, add at least one Bootstrap DNS server before enabling upstream DNS takeover")
		return nil
	end
	return value
end
o.write = mark_upstream_write
o.remove = mark_upstream_remove
o.description = translate("Bootstrap DNS must be configured before enabling this feature")

o = s:taboption("upstream", Value, "upstream_dns_file", translate("upstream_dns_file path"))
o.default = upstream_default_file
o.datatype = "string"
o.optional = false
o.rmempty = false
o.cfgvalue = function(self, section)
	local configured = read_dns_option(configpath, "upstream_dns_file")
	return (configured and configured ~= "") and configured or self.default
end
o.write = mark_upstream_write
o.remove = mark_upstream_remove

o = s:taboption("upstream", TextValue, "global_upstreams", translate("Global upstream DNS"), translate("One AdGuard Home upstream_dns entry per line, these servers are used as the global upstreams").."<br/>"..translate("Global upstreams are written at the beginning of upstream_dns_file")..global_upstream_help)
o.template = "AdGuardHome/linevalue"
o.rows = 5
o.wrap = "off"
o.default = global_upstreams_default
o.optional = false
o.cfgvalue = function(self, section)
	return self.map:get(section, self.option) or self.default
end
o.write = mark_upstream_write
o.remove = mark_upstream_remove

o = s:taboption("upstream", TextValue, "domain_subscription_urls", translate("Domain subscription URLs"), translate("One subscription URL per line, all successfully downloaded lists are merged; Base64 encoded lists are decoded automatically"))
	o.template = "AdGuardHome/linevalue"
	o.rows = 5
	o.wrap = "off"
	o.default = domain_list_default
	o.optional = false
	o.cfgvalue = function(self, section)
	return self.map:get(section, self.option) or self.default
	end
	o.write = mark_upstream_write
	o.remove = mark_upstream_remove

o = s:taboption("upstream", TextValue, "domain_upstreams", translate("Domain list upstream DNS"), translate("One AdGuard Home upstream_dns entry per line, these servers are used for domains from the merged subscription lists"))
o.template = "AdGuardHome/linevalue"
o.rows = 5
o.wrap = "off"
o.default = domain_upstreams_default
o.optional = false
o.cfgvalue = function(self, section)
	return self.map:get(section, self.option) or self.default
end
o.write = mark_upstream_write
o.remove = mark_upstream_remove

o = s:taboption("upstream", Value, "upstream_cron", translate("Automatic update schedule"), translate("Five-field crontab expression, the default is 30 4 * * *"))
o.default = "30 4 * * *"
o.optional = false
o.rmempty = false
o.validate = function(self, value)
	if not value or value:find("[;&|`$()<>]") or
	   not value:match("^%S+%s+%S+%s+%S+%s+%S+%s+%S+$") then
		return nil
	end
	return value
end
o.cfgvalue = function(self, section)
	return self.map:get(section, self.option) or self.default
end
o.write = mark_upstream_write
o.remove = mark_upstream_remove

o = s:taboption("upstream", DummyValue, "bootstrap_status", translate("Bootstrap DNS status"))
o.rawhtml = true
o.cfgvalue = function()
	if bootstrap_empty then
		return '<font color="red"><strong>'..translate("Bootstrap DNS is empty, add at least one Bootstrap DNS server in the AdGuard Home configuration")..'</strong></font>'
	end
	return '<font color="green">'..translate("Bootstrap DNS is configured")..'</font>'
end

o = s:taboption("upstream", DummyValue, "upstream_file_view", translate("Generated upstream DNS file"))
o.template = "AdGuardHome/upstreamfile"
o.cfgvalue = function()
	local configured = read_dns_option(configpath, "upstream_dns_file")
	return (configured and configured ~= "") and configured or upstream_default_file
end

o = s:taboption("upstream", Button, "upstream_update", translate("Update upstream DNS list"), translate("Download and merge all subscription lists, generate upstream_dns_file and reload AdGuard Home"))
o.inputtitle = translate("Update now")
o.optional = false
o.write = function()
	luci.sys.exec("/usr/share/AdGuardHome/update_upstream.sh --queue >>/tmp/AdGuardHome_upstream_update.log 2>&1 &")
	luci.http.redirect(luci.dispatcher.build_url("admin", "services", "AdGuardHome"))
end

---- Backup Settings ----
s:tab("backup", translate("Backup Settings"))

-- upgrade protect
o = s:taboption("backup", DynamicList, "upprotect", translate("Keep files when system upgrade"))
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
o = s:taboption("backup", MultiValue, "backupfile", translate("Backup workdir files when shutdown"))
o1 = s:taboption("backup", Value, "backupwdpath", translate("Backup workdir path"))
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
o=s:taboption("gfwlist", Button,"gfwadd",translate("Add gfwlist"),translate(a))
o.optional = false
o.inputtitle=translate("Add")
o.write=function()
	luci.sys.exec("sh /usr/share/AdGuardHome/gfw2adg.sh 2>&1")
	luci.http.redirect(luci.dispatcher.build_url("admin","services","AdGuardHome"))
end
o=s:taboption("gfwlist", Button,"gfwdel",translate("Del gfwlist"),translate(a))
o.optional = false
o.inputtitle=translate("Del")
o.write=function()
	luci.sys.exec("sh /usr/share/AdGuardHome/gfw2adg.sh del 2>&1")
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
o=s:taboption("gfwlist", Button,"gfwipsetadd",translate("Add gfwlist").." "..translate("(ipset only)"),translate(a).." "..translate("will set to name gfwlist"))
o.optional = false
o.inputtitle=translate("Add")
o.write=function()
	luci.sys.exec("sh /usr/share/AdGuardHome/gfwipset2adg.sh 2>&1")
	luci.http.redirect(luci.dispatcher.build_url("admin","services","AdGuardHome"))
end
o=s:taboption("gfwlist", Button,"gfwipsetdel",translate("Del gfwlist").." "..translate("(ipset only)"),translate(a))
o.optional = false
o.inputtitle=translate("Del")
o.write=function()
	luci.sys.exec("sh /usr/share/AdGuardHome/gfwipset2adg.sh del 2>&1")
	luci.http.redirect(luci.dispatcher.build_url("admin","services","AdGuardHome"))
end
o = s:taboption("gfwlist", Value, "gfwupstream", translate("Gfwlist upstream dns server"), translate("Gfwlist domain upstream dns service")..translate(a))
o.default     = "tcp://208.67.220.220:5353"
o.datatype    = "string"
o.optional = false

return m
