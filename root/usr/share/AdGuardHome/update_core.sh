#!/bin/bash
PATH="/usr/sbin:/usr/bin:/sbin:/bin"
binpath=$(uci get AdGuardHome.AdGuardHome.binpath)
if [ -z "$binpath" ]; then
uci set AdGuardHome.AdGuardHome.binpath="/tmp/AdGuardHome/AdGuardHome"
binpath="/tmp/AdGuardHome/AdGuardHome"
fi
mkdir -p ${binpath%/*}
upxflag=$(uci get AdGuardHome.AdGuardHome.upxflag 2>/dev/null)

check_wgetcurl(){
	echo "Checking for wget or curl..."
	# Set User-Agent as curl 8.0.0, otherwise GitHub may return JSON with no line-breaks
	which wget && downloader="wget -U 'curl/8.0.0' --no-check-certificate -T 20 -O" && return
	which curl && downloader="curl -L -k --retry 2 --connect-timeout 20 -o" && return
	[ -z "$1" ] && opkg update || (echo "Failed to run opkg update" && EXIT 1)
	[ -z "$1" ] && (opkg remove wget wget-nossl --force-depends ; opkg install wget ; check_wgetcurl 1 ;return)
	[ "$1" == "1" ] && (opkg install curl ; check_wgetcurl 2 ; return)
	echo "Error: curl and wget not found" && EXIT 1
}

check_latest_version(){
	check_wgetcurl
	echo "Check for update..."
	latest_ver="$($downloader - https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest 2>/dev/null|grep -E 'tag_name'|head -n1|cut -d '"' -f4 2>/dev/null)"

	if [ -z "${latest_ver}" ]; then
		echo "Failed to check latest version, please try again later." && EXIT 1
	fi
	local_ver="$($binpath --version 2>/dev/null | grep -m 1 -oE '[v]{0,1}[0-9]+[.][Bbeta0-9\.\-]+')"
	echo "Local version: ${local_ver}. Latest version: ${latest_ver}."
	if [ "${latest_ver}"x != "${local_ver}"x ] || [ "$1" == "force" ]; then
		doupdate_core
	else
		echo "You're already using the latest version."
		if [ ! -z "$upxflag" ]; then
			filesize=$(ls -l $binpath | awk '{ print $5 }')
			if [ $filesize -gt 8000000 ]; then
				doupx
				mkdir -p "/tmp/AdGuardHomeupdate/AdGuardHome" >/dev/null 2>&1
				rm -fr /tmp/AdGuardHomeupdate/AdGuardHome/${binpath##*/}
				/tmp/upx-${upx_latest_ver}-${Arch}_linux/upx $upxflag $binpath -o /tmp/AdGuardHomeupdate/AdGuardHome/${binpath##*/}
				rm -rf /tmp/upx-${upx_latest_ver}-${Arch}_linux
				/etc/init.d/AdGuardHome stop nobackup
				rm $binpath
				mv -f /tmp/AdGuardHomeupdate/AdGuardHome/${binpath##*/} $binpath
				/etc/init.d/AdGuardHome start
				echo "Finished"
			fi
		fi
		EXIT 0
	fi
}

doupx(){
	echo "Start running upx. It may take some time..."

	um="$(uname -m)"
	OPENWRT_ARCH="$(awk -F'=' '/^OPENWRT_ARCH=/{gsub(/"/,"",$2); split($2,a,"_"); print a[1]}' /etc/os-release)"
	case "$um" in
		i386)    Arch="i386" ;;
		i686)    Arch="i386"; echo "i686 use $Arch may have bug" ;;
		x86_64)  Arch="amd64" ;;
		aarch64) Arch="arm64" ;;
		arm*)    Arch="arm" ;;
		mips*)
			case "$OPENWRT_ARCH" in
				mips64el) Arch="mipsel"; echo "mips64el use $Arch may have bug" ;;   # 64‑bit little‑endian
				mips64)   Arch="mips"; echo "mips64 use $Arch may have bug"   ;;   # 64‑bit big‑endian
				mipsel)   Arch="mipsel"   ;;   # 32‑bit little‑endian
				mips)     Arch="mips"     ;;   # 32‑bit big‑endian
				*) echo "Error: unknown OpenWrt MIPS flavour '$OPENWRT_ARCH'"; exit 1 ;;
			esac
			;;
		ppc*) Arch="powerpc64le" ;;
		*) echo "Error: $um is not supported"; exit 1 ;;
	esac
	upx_latest_ver="$($downloader - https://api.github.com/repos/upx/upx/releases/latest 2>/dev/null|grep -E 'tag_name' |grep -E '[0-9.]+' -o 2>/dev/null)"
	$downloader /tmp/upx-${upx_latest_ver}-${Arch}_linux.tar.xz "https://github.com/upx/upx/releases/download/v${upx_latest_ver}/upx-${upx_latest_ver}-${Arch}_linux.tar.xz" 2>&1
	#tar xvJf
	which xz || (opkg list | grep ^xz || opkg update && opkg install xz) || (echo "Failed to install xz, it's required for installing upx." && EXIT 1)
	mkdir -p /tmp/upx-${upx_latest_ver}-${Arch}_linux
	xz -d -c /tmp/upx-${upx_latest_ver}-${Arch}_linux.tar.xz| tar -x -C "/tmp" >/dev/null 2>&1
	if [ ! -e "/tmp/upx-${upx_latest_ver}-${Arch}_linux/upx" ]; then
		echo "Failed to download upx."
		EXIT 1
	fi
	rm /tmp/upx-${upx_latest_ver}-${Arch}_linux.tar.xz
}

doupdate_core(){
	echo "Updating core..."
	mkdir -p "/tmp/AdGuardHomeupdate"
	rm -rf /tmp/AdGuardHomeupdate/* >/dev/null 2>&1
	Arch=$(uci -q get AdGuardHome.AdGuardHome.arch)
	if [ -z "$Arch" ]; then
	um="$(uname -m)"
	OPENWRT_ARCH="$(awk -F'=' '/^OPENWRT_ARCH=/{gsub(/"/,"",$2); split($2,a,"_"); print a[1]}' /etc/os-release)"
	case "$um" in
		i386|i686)     Arch="386" ;;
		x86_64)        Arch="amd64" ;;
		aarch64)       Arch="arm64" ;;
		armv5*)        Arch="armv5" ;;
		armv6*)        Arch="armv6" ;;
		armv7*|armv8l) Arch="armv7" ;;
		mips*)
			case "$OPENWRT_ARCH" in
				mips64el) Arch="mips64le_softfloat" ;;   # 64‑bit little‑endian
				mips64)   Arch="mips64_softfloat"   ;;   # 64‑bit big‑endian
				mipsel)   Arch="mipsle_softfloat"   ;;   # 32‑bit little‑endian
				mips)     Arch="mips_softfloat"     ;;   # 32‑bit big‑endian
				*) echo "Error: unknown OpenWrt MIPS flavour '$OPENWRT_ARCH'"; exit 1 ;;
			esac
			;;
		ppc*)          Arch="ppc64le" ;;
		riscv|riscv64) Arch="riscv64" ;;
		*) echo "Error: $um is not supported"; exit 1 ;;
	esac
	fi
	echo "Start download..."
	downloadlinks=$(uci get AdGuardHome.AdGuardHome.downloadlinks 2>/dev/null)
	if [ -z "$downloadlinks" ]; then
		echo "No download links configured in UCI"
		EXIT 1
	fi
	echo "$downloadlinks" | grep -v "^#" >/tmp/AdG_links.txt
	while read link
	do
		[ -n "$link" ] || continue
		link="${link//\$\{latest_ver\}/$latest_ver}"
		link="${link//\$\{Arch\}/$Arch}"

		echo "Trying to download from: $link"
		$downloader /tmp/AdGuardHomeupdate/${link##*/} "$link" 2>&1
		if [ "$?" != "0" ]; then
			echo "Download failed. Trying next link..."
			rm -f /tmp/AdGuardHomeupdate/${link##*/}
		else
			local success="1"
			break
		fi
	done < "/tmp/AdG_links.txt"
	rm /tmp/AdG_links.txt
	[ -z "$success" ] && echo "All downloads failed." && EXIT 1
	if [ "${link##*.}" == "gz" ]; then
		tar -zxf "/tmp/AdGuardHomeupdate/${link##*/}" -C "/tmp/AdGuardHomeupdate/"
		if [ ! -e "/tmp/AdGuardHomeupdate/AdGuardHome" ]; then
			echo "Failed to download core."
			rm -rf "/tmp/AdGuardHomeupdate" >/dev/null 2>&1
			EXIT 1
		fi
		downloadbin="/tmp/AdGuardHomeupdate/AdGuardHome/AdGuardHome"
	else
		downloadbin="/tmp/AdGuardHomeupdate/${link##*/}"
	fi
	chmod 755 $downloadbin
	echo "Download successful."
	if [ -n "$upxflag" ]; then
		doupx
		/tmp/upx-${upx_latest_ver}-${Arch}_linux/upx $upxflag $downloadbin
		rm -rf /tmp/upx-${upx_latest_ver}-${Arch}_linux
	fi
	echo "Start copy to ${binpath}"
	/etc/init.d/AdGuardHome stop nobackup
	rm -f "$binpath"
	mv -f "$downloadbin" "$binpath"
	if [ "$?" == "1" ]; then
		echo "Error: mv failed. Maybe not enough space. Please use upx or change bin path to /tmp/AdGuardHome."
		EXIT 1
	fi
	/etc/init.d/AdGuardHome start
	rm -rf "/tmp/AdGuardHomeupdate" >/dev/null 2>&1
	echo "Core updated successfully. New version: ${latest_ver}."
	EXIT 0
}

EXIT(){
	[ "$1" != "0" ] && touch /var/run/AdG_update_error
	exit $1
}

main(){
	# Check if already running
	if pgrep -f "/usr/share/AdGuardHome/update_core.sh" | grep -v "^$$$" > /dev/null; then
		echo "A task is already running."
		exit 2
	fi

	trap "EXIT 1" SIGTERM SIGINT
	rm /var/run/AdG_update_error 2>/dev/null

	check_latest_version $1
}

main $1
