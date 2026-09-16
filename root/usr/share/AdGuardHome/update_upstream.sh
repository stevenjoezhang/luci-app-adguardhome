#!/bin/sh
PATH="/usr/sbin:/usr/bin:/sbin:/bin"

BASE_DIR="/usr/bin/AdGuardHome"
DOMAIN_LIST="$BASE_DIR/domain_list.txt"
LOG_FILE="$BASE_DIR/upstream_update.log"
MAX_LOG_SIZE=102400
QUEUE_DIR="/tmp/AdGuardHome-upstream"
QUEUE_FILE="$QUEUE_DIR/pending"
QUEUE_LOCK="$QUEUE_DIR/lock"
QUEUE_STATE="$QUEUE_DIR/state"
QUEUE_LOG="/tmp/AdGuardHome_upstream_update.log"
SCRIPT_PATH="/usr/share/AdGuardHome/update_upstream.sh"

uci_value() { uci -q get "AdGuardHome.AdGuardHome.$1" 2>/dev/null; }

CONFIG_PATH="$(uci_value configpath)"
[ -n "$CONFIG_PATH" ] || CONFIG_PATH="/etc/AdGuardHome.yaml"
UPSTREAM_CONF="$(uci_value upstream_dns_file)"
[ -n "$UPSTREAM_CONF" ] || UPSTREAM_CONF="$BASE_DIR/upstream_dns.conf"

DEFAULT_URLS="https://cdn.jsdelivr.net/gh/gfwlist/gfwlist/gfwlist.txt"
DEFAULT_GLOBAL_UPSTREAMS='https://dns.alidns.com/dns-query
https://doh.pub/dns-query'
DEFAULT_DOMAIN_UPSTREAMS="https://dns.google/dns-query"

write_queue_state() {
	local state="$1" tmp="${QUEUE_STATE}.tmp.$$"
	printf '%s\n' "$state" > "$tmp" && mv "$tmp" "$QUEUE_STATE"
}

run_queue_worker() {
	printf '%s\n' "$$" > "$QUEUE_LOCK/pid"
	while :; do
		[ -f "$QUEUE_FILE" ] || break
		rm -f "$QUEUE_FILE"
		write_queue_state "running"
		"$SCRIPT_PATH" --run
	done
	rm -f "$QUEUE_STATE"
	rm -f "$QUEUE_LOCK/pid"
	rmdir "$QUEUE_LOCK" 2>/dev/null
	# A request can arrive while the worker is finishing.  Recheck the
	# marker after releasing the lock so that request is not stranded.
	if [ -f "$QUEUE_FILE" ] && mkdir "$QUEUE_LOCK" 2>/dev/null; then
		printf '%s\n' "$$" > "$QUEUE_LOCK/pid"
		write_queue_state "queued"
		run_queue_worker
	fi
}

queue_update() {
	local owner
	mkdir -p "$QUEUE_DIR" || return 1
	# A marker represents one pending run, so repeated callers are coalesced.
	: > "$QUEUE_FILE" || return 1
	write_queue_state "queued" || return 1
	if mkdir "$QUEUE_LOCK" 2>/dev/null; then
		# Launch a separate process so its PID can be used to recover a stale
		# lock if the previous worker was killed during an update.
		"$SCRIPT_PATH" --worker >> "$QUEUE_LOG" 2>&1 &
	elif [ -f "$QUEUE_LOCK/pid" ]; then
		owner="$(cat "$QUEUE_LOCK/pid" 2>/dev/null)"
		case "$owner" in
			''|*[!0-9]*) ;;
			*)
				if ! kill -0 "$owner" 2>/dev/null; then
					rm -f "$QUEUE_LOCK/pid"
					rmdir "$QUEUE_LOCK" 2>/dev/null
					if mkdir "$QUEUE_LOCK" 2>/dev/null; then
						"$SCRIPT_PATH" --worker >> "$QUEUE_LOG" 2>&1 &
					fi
				fi
				;;
			esac
	fi
	return 0
}

trim_log() {
	[ -f "$LOG_FILE" ] || return 0
	local size tmp
	size="$(wc -c < "$LOG_FILE" 2>/dev/null)" || return 0
	case "$size" in
		''|*[!0-9]*) return 0 ;;
	esac
	[ "$size" -le "$MAX_LOG_SIZE" ] && return 0
	tmp="${LOG_FILE}.tmp.$$"
	if tail -c "$MAX_LOG_SIZE" "$LOG_FILE" > "$tmp" 2>/dev/null; then
		mv "$tmp" "$LOG_FILE"
	else
		rm -f "$tmp"
	fi
}

append_log_file() {
	local source="$1" tmp
	mkdir -p "${LOG_FILE%/*}" || return 1
	tmp="${LOG_FILE}.tmp.$$"
	# Build the new log in a temporary file and atomically replace the old
	# one with only its last MAX_LOG_SIZE bytes.  The visible log therefore
	# never exceeds the configured limit, even for large reload diagnostics.
	if { [ ! -f "$LOG_FILE" ] || cat "$LOG_FILE"; cat "$source"; } |
		tail -c "$MAX_LOG_SIZE" > "$tmp" 2>/dev/null; then
		mv "$tmp" "$LOG_FILE"
	else
		rm -f "$tmp"
		return 1
	fi
}

log() {
	local tmp result
	tmp="$(mktemp /tmp/adguardhome-log.XXXXXX)" || return 1
	printf '%s\n' "$(date '+%Y-%m-%d %H:%M:%S') - $1" > "$tmp"
	append_log_file "$tmp"
	result=$?
	rm -f "$tmp"
	return "$result"
}

# Capture service output before appending it, so the log never grows beyond
# MAX_LOG_SIZE even when the reload command emits a large diagnostic.
reload_service() {
	local tmp result
	tmp="$(mktemp /tmp/adguardhome-reload.XXXXXX)" || return 1
	/etc/init.d/AdGuardHome reload > "$tmp" 2>&1
	result=$?
	append_log_file "$tmp"
	local append_result=$?
	rm -f "$tmp"
	[ "$append_result" -eq 0 ] || return "$append_result"
	trim_log
	return "$result"
}

# AdGuard Home expects upstream_dns_file below the top-level dns mapping.
set_upstream_file() {
	local target="$1"
	[ -f "$CONFIG_PATH" ] || return 1
	[ -n "$target" ] || return 1
	mkdir -p "${target%/*}" || return 1
	local tmp
	tmp="$(mktemp /tmp/adguardhome-config.XXXXXX)" || return 1
	awk -v target="$target" '
		/^dns:[[:space:]]*$/ { in_dns=1; saw_dns=1; print; next }
		in_dns && /^[^[:space:]]/ {
			if (!done) { print "  upstream_dns_file: " target; done=1 }
			in_dns=0
		}
		in_dns && /^[[:space:]]+upstream_dns_file[[:space:]]*:/ {
			if (!done) print "  upstream_dns_file: " target
			done=1
			next
		}
		{ print }
		END {
			if (saw_dns && !done) print "  upstream_dns_file: " target
			if (!saw_dns) {
				print "dns:"
				print "  upstream_dns_file: " target
			}
		}
	' "$CONFIG_PATH" > "$tmp" && mv "$tmp" "$CONFIG_PATH"
	local result=$?
	rm -f "$tmp"
	return $result
}

remove_upstream_file() {
	[ -f "$CONFIG_PATH" ] || return 0
	local tmp
	tmp="$(mktemp /tmp/adguardhome-config.XXXXXX)" || return 1
	awk '
		/^dns:[[:space:]]*$/ { in_dns=1; print; next }
		in_dns && /^[^[:space:]]/ { in_dns=0 }
		in_dns && /^[[:space:]]+upstream_dns_file[[:space:]]*:/ { next }
		{ print }
	' "$CONFIG_PATH" > "$tmp" && mv "$tmp" "$CONFIG_PATH"
	local result=$?
	rm -f "$tmp"
	return $result
}

apply_config() {
	# Do not point AdGuard Home at a file that has not been generated yet.
	# The core can start with its normal upstreams while the queued worker
	# downloads the subscriptions and applies the pointer afterwards.
	if [ "$(uci_value upstream_enabled)" = "1" ] && [ -s "$UPSTREAM_CONF" ]; then
		set_upstream_file "$UPSTREAM_CONF"
	else
		remove_upstream_file
	fi
}

case "$1" in
	""|--queue)
		queue_update
		exit $?
		;;
	--apply)
		apply_config
		exit $?
		;;
	--run)
		;;
	--worker)
		run_queue_worker
		exit $?
		;;
	*)
		queue_update
		exit $?
		;;
esac

mkdir -p "$BASE_DIR" "${UPSTREAM_CONF%/*}" || exit 1

# When disabled, only remove the pointer and reload the core.  This path is
# used by the LuCI save hook as well as by manual service changes.
if [ "$(uci_value upstream_enabled)" != "1" ]; then
	apply_config || exit 1
	if reload_service; then
		log "Upstream DNS takeover disabled and AdGuardHome reloaded."
	else
		log "AdGuardHome reload failed while disabling upstream DNS takeover."
	fi
	exit 0
fi

URLS="$(uci_value domain_subscription_urls)"
[ -n "$URLS" ] || URLS="$DEFAULT_URLS"
GLOBAL_UPSTREAMS="$(uci_value global_upstreams)"
[ -n "$GLOBAL_UPSTREAMS" ] || GLOBAL_UPSTREAMS="$DEFAULT_GLOBAL_UPSTREAMS"
DOMAIN_UPSTREAMS="$(uci_value domain_upstreams)"
[ -n "$DOMAIN_UPSTREAMS" ] || DOMAIN_UPSTREAMS="$DEFAULT_DOMAIN_UPSTREAMS"

download() {
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL --connect-timeout 30 --max-time 180 --retry 3 -o "$2" "$1"
	elif command -v wget >/dev/null 2>&1; then
		wget -q --no-check-certificate -T 30 -O "$2" "$1"
	else
		return 1
	fi
}

# Return success only if the complete payload looks like Base64 and decodes to
# a non-empty file.  Otherwise callers keep the original text unchanged.
decode_base64() {
	local source="$1" decoded="$2" compact length
	# BusyBox tr on some builds treats the POSIX character-class spelling as
	# literal characters (silently deleting letters such as `s`).  Remove the
	# actual line-whitespace bytes explicitly instead.
	compact="$(tr -d '\r\n\t ' < "$source")"
	[ -n "$compact" ] || return 1
	length=${#compact}
	[ $((length % 4)) -eq 0 ] || return 1
	printf '%s' "$compact" | grep -Eq '^[A-Za-z0-9+/]*={0,2}$' || return 1
	# Reuse the original GFWList updater's pure-Lua decoder.  This keeps
	# Base64 support available on OpenWrt images without the base64 utility.
	local lua_bin=""
	if command -v lua >/dev/null 2>&1; then
		lua_bin="$(command -v lua)"
	elif command -v lua5.1 >/dev/null 2>&1; then
		lua_bin="$(command -v lua5.1)"
	else
		return 1
	fi
	"$lua_bin" /usr/share/AdGuardHome/gfw2adg.lua --decode-base64 "$source" "$decoded" >/dev/null 2>&1 || return 1
	[ -s "$decoded" ]
}

TEMP_RAW="$(mktemp /tmp/adguard_upstream_raw.XXXXXX)" || exit 1
TEMP_DOWNLOAD="$(mktemp /tmp/adguard_upstream_download.XXXXXX)" || exit 1
TEMP_DECODED="$(mktemp /tmp/adguard_upstream_decoded.XXXXXX)" || exit 1
TEMP_DOMAINS="$(mktemp /tmp/adguard_upstream_domains.XXXXXX)" || exit 1
TEMP_CONF="$(mktemp /tmp/adguard_upstream_conf.XXXXXX)" || exit 1
trap 'rm -f "$TEMP_RAW" "$TEMP_DOWNLOAD" "$TEMP_DECODED" "$TEMP_DOMAINS" "$TEMP_CONF" "$DOMAIN_LIST.tmp"' 0 1 2 15

trim_log
log "======== Upstream DNS update started ========"

: > "$TEMP_RAW"
success=0
while IFS= read -r url; do
	url="$(printf '%s' "$url" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
	[ -n "$url" ] || continue
	case "$url" in \#*) continue ;; esac
	log "Downloading subscription $url ..."
	if download "$url" "$TEMP_DOWNLOAD" && [ -s "$TEMP_DOWNLOAD" ]; then
		if decode_base64 "$TEMP_DOWNLOAD" "$TEMP_DECODED"; then
			cat "$TEMP_DECODED" >> "$TEMP_RAW"
			log "Downloaded and Base64-decoded successfully."
		else
			cat "$TEMP_DOWNLOAD" >> "$TEMP_RAW"
			log "Downloaded as plain text."
		fi
		success=1
	else
		log "Download failed. Trying next URL."
	fi
done <<EOF
$URLS
EOF

[ "$success" -eq 1 ] || { log "ERROR: all subscription URLs failed."; exit 1; }

# Extract domains using the same rule shape as the original GFWList Lua
# updater.  The second column records whitelist rules (which bypass domain
# upstreams).  Host-file and plain-domain input remain supported as small
# extensions for user-supplied subscriptions.
awk '
function emit(domain, white, star, dot) {
	# Lua updater: if a wildcard occurs, keep the part after the first
	# wildcard and then drop the first label.  This also handles wildcards
	# that are not at the beginning of a rule.
	gsub(/[\r\t ]/, "", domain)
	star=index(domain, "*")
	if (star) {
		domain=substr(domain, star + 1)
		dot=index(domain, ".")
		if (dot) domain=substr(domain, dot + 1)
		else return
	}
	if (substr(domain, 1, 1) == ".") domain=substr(domain, 2)

	# AdGuard Home does not accept an all-numeric dotted name as a domain
	# (for example 85.17.73.31).  The old GFWList path sent IPv4 values to
	# ipset; the generic upstream path has no ipset output, so drop them.
	if (domain ~ /^[0-9]+([.][0-9]+)+$/) return

	if (domain ~ /^[A-Za-z0-9.-]+$/ && domain ~ /\./ && domain !~ /^[-.]/ && domain !~ /[-.]$/ && domain !~ /%/) {
		domain=tolower(domain)
		if (domain != last_domain) {
			print domain "\t" (white ? "1" : "0")
			last_domain=domain
		}
	}
}
{
	line=$0
	sub(/\r$/, "", line)
	gsub(/^[ \t]+|[ \t]+$/, "", line)
	if (line == "" || line ~ /^[!#]/) next
	white=0
	# The Lua implementation checks only the first character and removes the
	# first two characters (GFWList uses @@ for whitelist rules).
	if (substr(line, 1, 1) == "@") { white=1; line=substr(line, 3) }
	if (line ~ /^domain:[ \t]*/) { sub(/^domain:[ \t]*/, "", line) }
	if (line ~ /^\|\|/) {
		sub(/^\|\|/, "", line)
		# Adblock caret marks the end of a host rule; it is not part of the
		# domain written to AdGuard Home.
		sub(/[\/^].*$/, "", line)
		emit(line, white)
		next
	}
	if (line ~ /^\|/) {
		sub(/^\|+/, "", line)
		sub(/^[[:alnum:]_]+:\/\//, "", line)
		sub(/[\/].*$/, "", line)
		emit(line, white)
		next
	}
	if (line ~ /^[A-Za-z][A-Za-z0-9+.-]*:\/\//) {
		sub(/^[A-Za-z][A-Za-z0-9+.-]*:\/\//, "", line)
		sub(/[\/].*$/, "", line)
		emit(line, white)
		next
	}
	if (line ~ /^[0-9A-Fa-f:.]+[ \t]+[^ \t]+/) {
		host=$2
		emit(host, white)
		next
	}
	sub(/[\/].*$/, "", line)
	sub(/[ \t].*$/, "", line)
	if (line !~ /^\//) emit(line, white)
}
' "$TEMP_RAW" > "$TEMP_DOMAINS"

printf '%s\n' "$GLOBAL_UPSTREAMS" | sed 's/\r$//' | awk 'NF && $0 !~ /^[[:space:]]*#/' > "$TEMP_CONF"
domain_count=0
while IFS="$(printf '\t')" read -r domain white; do
	[ -n "$domain" ] || continue
	printf '[/%s/]' "$domain" >> "$TEMP_CONF"
	if [ "$white" = "1" ]; then
		printf '#\n' >> "$TEMP_CONF"
	else
		first_upstream=1
		while IFS= read -r upstream; do
			upstream="$(printf '%s' "$upstream" | sed 's/\r$//')"
			[ -n "$upstream" ] || continue
			if [ "$first_upstream" -eq 1 ]; then
				first_upstream=0
			else
				printf ' ' >> "$TEMP_CONF"
			fi
			printf '%s' "$upstream" >> "$TEMP_CONF"
		done <<EOF
$DOMAIN_UPSTREAMS
EOF
		printf '\n' >> "$TEMP_CONF"
	fi
	domain_count=$((domain_count + 1))
done < "$TEMP_DOMAINS"

[ "$domain_count" -gt 0 ] || { log "ERROR: no valid domains found in subscriptions."; exit 1; }
mv "$TEMP_DOMAINS" "$DOMAIN_LIST"
mv "$TEMP_CONF" "$UPSTREAM_CONF" || { log "ERROR: failed to replace upstream DNS file."; exit 1; }
apply_config || { log "ERROR: failed to set upstream_dns_file in core config."; exit 1; }

if reload_service; then
	log "Upstream DNS file replaced ($domain_count domains) and AdGuardHome reloaded."
else
	log "ERROR: AdGuardHome reload failed."
fi
log "======== Upstream DNS update finished ========"
exit 0
