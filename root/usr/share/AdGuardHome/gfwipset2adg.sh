#!/bin/sh
LUA=/usr/bin/lua
LUA_SCRIPT=/usr/share/AdGuardHome/gfw2adg.lua

configpath=$(uci get AdGuardHome.AdGuardHome.configpath 2>/dev/null)
if [ -z "$configpath" ] || [ ! -f "$configpath" ]; then
    echo "please make a config first"
    exit 1
fi

exec "$LUA" "$LUA_SCRIPT" --mode=ipset "$@"
