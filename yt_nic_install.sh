#!/bin/bash

# Motorcomm Networks Interface Card driver install

set -u

drv_base=yt6801
drv_file=$drv_base.ko
kernel_release=$(uname -r)
script_dir=$(cd "$(dirname "$0")" && pwd)
module_root=/lib/modules/$kernel_release
preferred_module_dir=$module_root/updates/motorcomm
legacy_module_dir=$module_root/kernel/drivers/net/ethernet/motorcomm
log_file=$script_dir/log.txt

need_update_initramfs=n
support_distrib_list="ubuntu debian"

log_info()
{
	echo -e "\\033[36;1m${*}\\033[0m"
	echo -e "${*}" >> "$log_file"
}

log_ok()
{
	echo -e "\\033[32;1m${*}\\033[0m"
	echo -e "${*}" >> "$log_file"
}

log_debug()
{
	echo -e "\\033[33;1m${*}\\033[0m"
	echo -e "${*}" >> "$log_file"
}

log_err()
{
	echo -e "\\033[31;1m${*}\\033[0m"
	echo -e "${*}" >> "$log_file"
}

separator()
{
	log_info "********************  ${*}  *********************************"
}

die()
{
	log_err "${*}"
	separator "error end"
	exit 1
}

run_cmd()
{
	log_debug "+ $*"
	"$@" >> "$log_file" 2>&1
	local status=$?
	if [ $status -ne 0 ]; then
		die "Command failed($status): $*"
	fi
}

update_initramfs()
{
	if [ "$need_update_initramfs" = "y" ]; then
		if command -v update-initramfs >/dev/null 2>&1; then
			log_info "Updating initramfs. Please wait."
			run_cmd update-initramfs -u -k "$kernel_release"
		else
			die "update-initramfs: command not found"
		fi
	fi
}

find_active_module_file()
{
	if [ -L "/sys/module/$drv_base" ]; then
		readlink -f "/sys/module/$drv_base"
		return 0
	fi

	modinfo -F filename "$drv_base" 2>/dev/null
}

driver_ifaces()
{
	local iface module_link
	for iface in /sys/class/net/*; do
		[ -e "$iface" ] || continue
		module_link=$iface/device/driver/module
		if [ -L "$module_link" ] && [ "$(basename "$(readlink -f "$module_link")")" = "$drv_base" ]; then
			basename "$iface"
		fi
	done
}

bring_down_ifaces()
{
	local iface
	for iface in $(driver_ifaces); do
		log_info "Bring down interface $iface"
		ip link set "$iface" down >> "$log_file" 2>&1 || true
	done
}

remove_loaded_module()
{
	if lsmod | grep -q "^$drv_base\\b"; then
		bring_down_ifaces
		log_info "Unload loaded module $drv_base"
		if ! modprobe -r "$drv_base" >> "$log_file" 2>&1; then
			die "Unable to unload $drv_base. Bring interfaces down and stop services using the NIC first."
		fi
	fi

	if lsmod | grep -q "^$drv_base\\b"; then
		die "$drv_base is still loaded after unload attempt"
	fi
}

backup_module_if_present()
{
	local candidate backup idx
	for candidate in "$preferred_module_dir/$drv_file" "$legacy_module_dir/$drv_file"; do
		if [ -e "$candidate" ]; then
			idx=0
			backup=$candidate.bak$idx
			while [ -e "$backup" ]; do
				idx=$((idx + 1))
				backup=$candidate.bak$idx
			done
			log_info "Backup existing module: $candidate -> $backup"
			run_cmd mv "$candidate" "$backup"
		fi
	done
}

remove_stale_module_copies()
{
	local candidate
	for candidate in \
		"$legacy_module_dir/$drv_file" \
		"$module_root/extra/motorcomm/$drv_file"; do
		if [ -e "$candidate" ]; then
			log_info "Remove stale module copy: $candidate"
			run_cmd rm -f "$candidate"
		fi
	done
}

verify_installed_module()
{
	local file version

	file=$(modinfo -F filename "$drv_base" 2>/dev/null)
	[ -n "$file" ] || die "modinfo did not return a module file for $drv_base"

	log_info "modinfo filename: $file"
	case "$file" in
		"$preferred_module_dir/$drv_file") ;;
		*)
			die "modprobe resolved $drv_base to unexpected path: $file"
			;;
	esac

	version=$(modinfo -F version "$drv_base" 2>/dev/null)
	log_info "modinfo version: $version"
	if [ "$version" != "1.0.30" ]; then
		die "Loaded module version is not 1.0.30"
	fi
}

build_and_install()
{
	log_info "Build and install Motorcomm NIC driver module"
	run_cmd make -C "$script_dir" all
}

load_new_module()
{
	log_info "Load module $drv_base"
	run_cmd depmod "$kernel_release"
	run_cmd modprobe "$drv_base"
	verify_installed_module
}

clean_install()
{
	log_info "Uninstall Motorcomm NIC driver ($drv_file)"
	remove_loaded_module
	run_cmd make -C "$script_dir" uninstall
	run_cmd make -C "$script_dir" clean
	update_initramfs
	separator "normal end"
	exit 0
}

separator "start"
date >> "$log_file"

if [ "$EUID" != "0" ]; then
	die "Please run this file as root"
fi

if [ -r /etc/debian_version ]; then
	need_update_initramfs=y
elif [ -r /etc/lsb-release ]; then
	for distrib in $support_distrib_list; do
		if /bin/grep -qi "$distrib" /etc/lsb-release; then
			need_update_initramfs=y
			break
		fi
	done
fi

if [ $# -gt 0 ]; then
	if [ "$1" = "clean" ]; then
		clean_install
	fi
	die "Unsupported argument: $1"
fi

remove_loaded_module
backup_module_if_present
remove_stale_module_copies
build_and_install
load_new_module
update_initramfs

log_ok "Install ok."
log_ok "Active module path: $(modinfo -F filename "$drv_base" 2>/dev/null)"
log_ok "Active module version: $(modinfo -F version "$drv_base" 2>/dev/null)"
separator "normal end"
exit 0
