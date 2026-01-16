#!/usr/bin/lua

-- Standard libraries only, compatible with OpenWRT (Lua 5.1+)
local io = io
local os = os
local string = string
local table = table

-- --- Helper Functions ---

-- Execute system command and return output
local function exec(cmd)
    local f = io.popen(cmd)
    local s = f:read("*a")
    f:close()
    return s:gsub("%s+$", "")
end

-- Get UCI configuration
local function uci_get(key)
    local val = exec("uci get AdGuardHome.AdGuardHome." .. key .. " 2>/dev/null")
    return (val ~= "" and val) or nil
end

-- Check if file exists
local function file_exists(name)
    local f = io.open(name, "r")
    if f then f:close() return true end
    return false
end

-- Read file into a table of lines
local function read_lines(path)
    local lines = {}
    local f = io.open(path, "r")
    if not f then return lines end
    for line in f:lines() do
        table.insert(lines, line)
    end
    f:close()
    return lines
end

-- Write a table of lines or a string to a file
local function write_to_file(path, data)
    local f = io.open(path, "w")
    if f then
        if type(data) == "table" then
            f:write(table.concat(data, "\n") .. "\n")
        else
            f:write(data)
        end
        f:close()
    else
        print("Error: unable to write to file " .. path)
    end
end

-- --- Initialization ---

local mode = ""
local noreload = false
local action = ""

-- Parse command line arguments
for _, v in ipairs(arg) do
    if v == "--mode=ipset" then mode = "ipset"
    elseif v == "--mode=upstream" then mode = "upstream"
    elseif v == "noreload" then noreload = true
    elseif v == "del" then action = "del" end
end

local configpath = uci_get("configpath")
local gfwupstream = uci_get("gfwupstream") or "tcp://208.67.220.220:5353"

if not configpath or not file_exists(configpath) then
    print("Error: Configuration path not found.")
    os.exit(1)
end

-- MD5 check and AdGuardHome reload
local function checkmd5(key, is_noreload)
    local md5_out = exec("md5sum /tmp/adguard.list 2>/dev/null")
    local nowmd5 = md5_out:match("^(%w+)")
    local lastmd5 = uci_get(key)

    if nowmd5 and nowmd5 ~= lastmd5 then
        os.execute(string.format("uci set AdGuardHome.AdGuardHome.%s='%s'", key, nowmd5))
        os.execute("uci commit AdGuardHome")
        if not is_noreload then
            os.execute("/etc/init.d/AdGuardHome reload")
        end
    end
end

-- --- Delete Action ---

if action == "del" then
    local lines = read_lines(configpath)
    local new_lines = {}

    if mode == "ipset" then
        -- Lua equivalent of sed ipset_file replace
        for _, line in ipairs(lines) do
            local replaced = line:gsub("ipset_file:%s*['\"]?.*['\"]?", 'ipset_file: ""')
            table.insert(new_lines, replaced)
        end
        write_to_file(configpath, new_lines)
        checkmd5("ipsetlistmd5", noreload)
    else
        -- Lua equivalent of sed /start/,/end/d
        local skip = false
        for _, line in ipairs(lines) do
            if line:find("programaddstart") then skip = true end
            if not skip then table.insert(new_lines, line) end
            if line:find("programaddend") then skip = false end
        end
        write_to_file(configpath, new_lines)
        checkmd5("gfwlistmd5", noreload)
    end
    os.exit(0)
end

-- --- Download and Process GFWList ---

print("Downloading gfwlist...")
-- Fetch base64 content and decode in pure Lua (avoid external `base64` on OpenWRT)
local raw_b64 = exec("wget --no-check-certificate https://cdn.jsdelivr.net/gh/gfwlist/gfwlist/gfwlist.txt -O- 2>/dev/null")
if not raw_b64 or raw_b64 == "" then
    print("Error: failed to download gfwlist or empty response")
    os.exit(1)
end

local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local b64map = {}

for i = 1, 64 do
    b64map[string.byte(b64chars, i)] = i - 1
end
b64map[string.byte('=')] = 0

local function b64decode(data)
    if not data then return nil end

    data = string.gsub(data, '[^'..b64chars..'=]', '')

    local result = {}
    local len = #data
    local padding = 0

    if string.sub(data, -1) == '=' then
        padding = padding + 1
        if string.sub(data, -2, -2) == '=' then
            padding = padding + 1
        end
    end

    for i = 1, len, 4 do
        local c1, c2, c3, c4 = string.byte(data, i, i+3)

        local v1 = b64map[c1]
        local v2 = b64map[c2]
        local v3 = b64map[c3]
        local v4 = b64map[c4]

        -- (v1 << 18) | (v2 << 12) | (v3 << 6) | v4
        local packed = (v1 * 0x40000) + (v2 * 0x1000) + (v3 * 0x40) + v4

        local b1 = math.floor(packed / 0x10000)
        local b2 = math.floor((packed % 0x10000) / 0x100)
        local b3 = packed % 0x100

        table.insert(result, string.char(b1))

        if i < len - 3 or padding < 2 then
            table.insert(result, string.char(b2))
        end
        if i < len - 3 or padding < 1 then
            table.insert(result, string.char(b3))
        end
    end

    return table.concat(result)
end

local decoded = b64decode(raw_b64)
if not decoded or decoded == "" then
    print("Error: base64 decode failed")
    os.exit(1)
end
write_to_file("/tmp/gfwlist.txt", decoded)

local gfw_file = io.open("/tmp/gfwlist.txt", "r")
local ad_list_results = {}
local ipset_sh_results = {}

if gfw_file then
    gfw_file:read("*l") -- Skip the first line
    local last_domain = ""

    for line in gfw_file:lines() do
        local domain = ""
        local white = false

        -- Parse logic (Lua version of the original awk script)
        if line ~= "" and line:sub(1,1) ~= "!" then
            if line:sub(1,1) == "@" then
                line = line:sub(3)
                white = true
            end

            if line:sub(1,1) == "|" then
                if line:sub(2,2) == "|" then
                    domain = line:sub(3):match("([^/]+)")
                else
                    domain = line:match("|%w+://([^/]+)") or line:match("|([^/]+)")
                end
            else
                domain = line:match("([^/]+)")
            end

            -- Handle wildcards *
            if domain then
                local star = domain:find("*")
                if star then
                    domain = domain:sub(star + 1)
                    local dot = domain:find("%.")
                    if dot then domain = domain:sub(dot + 1) else domain = nil end
                end
            end

            if domain and domain:sub(1,1) == "." then domain = domain:sub(2) end

            -- Validate domain format
            if domain and domain ~= "" and domain:find("%.") and not domain:find("[%%:]") then
                -- If pure IP
                if domain:match("^%d+%.%d+%.%d+%.%d+$") then
                    table.insert(ipset_sh_results, "ipset add gfwlist " .. domain)
                elseif domain ~= last_domain then
                    if white then
                        table.insert(ad_list_results, "    - '[/" .. domain .. "/]#'")
                    else
                        table.insert(ad_list_results, "    - '[/" .. domain .. "/]" .. gfwupstream .. "'")
                    end
                    last_domain = domain
                end
            end
        end
    end
    gfw_file:close()
end

table.insert(ad_list_results, "    - '[/programaddend/]#'")
write_to_file("/tmp/adguard.list", ad_list_results)
write_to_file("/tmp/doipset.sh", ipset_sh_results)

-- --- Mode Selection and Config Application ---

if mode == "ipset" then
    -- Generate ipset.txt from processed list
    local ipset_list = {}
    for _, line in ipairs(ad_list_results) do
        -- Pure Lua clean: remove YAML prefix and upstream suffix
        local d = line:match("%[/(.-)/%]")
        if d and not line:find("/]#") and d ~= "programaddend" then
            table.insert(ipset_list, d .. "/gfwlist")
        end
    end
    -- Sort and Unique
    table.sort(ipset_list)
    local unique_ipset = {}
    for i, v in ipairs(ipset_list) do
        if v ~= ipset_list[i-1] then table.insert(unique_ipset, v) end
    end
    write_to_file("/usr/bin/AdGuardHome/ipset.txt", unique_ipset)

    -- Update configpath for ipset_file
    local has_ipset = os.execute("which ipset >/dev/null 2>&1") == 0
    if #unique_ipset > 0 and has_ipset then
        os.execute("ipset list gfwlist >/dev/null 2>&1 || ipset create gfwlist hash:ip")
        local lines = read_lines(configpath)
        for i, line in ipairs(lines) do
            lines[i] = line:gsub('ipset_file:%s*["\']?.*["\']?', 'ipset_file: /usr/bin/AdGuardHome/ipset.txt')
        end
        write_to_file(configpath, lines)
    end
    checkmd5("ipsetlistmd5", noreload)

else
    -- Upstream mode logic
    local lines = read_lines(configpath)
    local has_marker = false
    for _, line in ipairs(lines) do
        if line:find("programaddstart") then has_marker = true; break end
    end

    local final_lines = {}
    if has_marker then
        -- Replace existing block
        local skip = false
        for _, line in ipairs(lines) do
            if line:find("programaddstart") then
                table.insert(final_lines, "    - '[/programaddstart/]#'")
                for _, nl in ipairs(ad_list_results) do table.insert(final_lines, nl) end
                skip = true
            end
            if not skip then table.insert(final_lines, line) end
            if line:find("programaddend") then skip = false end
        end
    else
        -- Insert after upstream_dns:
        for _, line in ipairs(lines) do
            table.insert(final_lines, line)
            if line:find("upstream_dns:") then
                table.insert(final_lines, "    - '[/programaddstart/]#'")
                for _, nl in ipairs(ad_list_results) do table.insert(final_lines, nl) end
            end
        end
    end
    write_to_file(configpath, final_lines)
    checkmd5("gfwlistmd5", noreload)
end

-- --- Cleanup ---
os.execute("rm -f /tmp/gfwlist.txt /tmp/adguard.list /tmp/doipset.sh")
