local m, s, o
local fs = require "nixio.fs"
local uci=require"luci.model.uci".cursor()
local sys=require"luci.sys"
require("string")
require("io")
require("table")

m = Map("AdGuardHome")
local configpath = uci:get("AdGuardHome","AdGuardHome","configpath")
local binpath = uci:get("AdGuardHome","AdGuardHome","binpath")
s = m:section(TypedSection, "AdGuardHome")
s.anonymous=true
s.addremove=false
--- config
o = s:option(TextValue, "escconf")
o.rows = 66
o.wrap = "off"
o.rmempty = true
o.cfgvalue = function(self, section)
	return fs.readfile("/tmp/AdGuardHometmpconfig.yaml") or fs.readfile(configpath) or fs.readfile("/usr/share/AdGuardHome/AdGuardHome_template.yaml") or ""
end
o.validate=function(self, value)
	fs.writefile("/tmp/AdGuardHometmpconfig.yaml", value:gsub("\r\n", "\n"))
	if fs.access(binpath) then
		if (sys.call(binpath.." -c /tmp/AdGuardHometmpconfig.yaml --check-config 2> /tmp/AdGuardHometest.log")==0) then
			return value
		end
	else
		return value
	end
	luci.http.redirect(luci.dispatcher.build_url("admin","services","AdGuardHome","manual"))
	return nil
end
o.write = function(self, section, value)
	fs.move("/tmp/AdGuardHometmpconfig.yaml",configpath)
end
o.remove = function(self, section, value)
	fs.writefile(configpath, "")
end
--- js and reload button
o = s:option(DummyValue, "")
o.anonymous=true
o.template = "AdGuardHome/yamleditor"
if not fs.access(binpath) then
	o.description=translate("WARNING!!! No executable found, config will not be tested")
end
--- log 
if (fs.access("/tmp/AdGuardHometmpconfig.yaml")) then
local c=fs.readfile("/tmp/AdGuardHometest.log")
if (c~="") then
o = s:option(TextValue, "")
o.readonly=true
o.rows = 5
o.rmempty = true
o.name=""
o.cfgvalue = function(self, section)
	return fs.readfile("/tmp/AdGuardHometest.log")
end
end
end
function m.on_commit(map)
	local ucitracktest=uci:get("AdGuardHome","AdGuardHome","ucitracktest")
	if ucitracktest=="1" then
		return
	elseif ucitracktest=="0" then
		io.popen("/etc/init.d/AdGuardHome reload &")
	else
		fs.writefile("/var/run/AdG_luci_test","")
	end
end
return m