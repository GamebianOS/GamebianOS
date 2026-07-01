# shellcheck shell=sh
# True when a usable laptop/handheld battery is present (not desktop ACPI quirks).

gamebian_sysfs_has_usable_battery() {
	_found=0
	for _ps in /sys/class/power_supply/*; do
		[ -d "${_ps}" ] || continue
		case "$(cat "${_ps}/type" 2>/dev/null)" in
			Battery) ;;
			*) continue ;;
		esac
		if [ -f "${_ps}/present" ]; then
			case "$(cat "${_ps}/present" 2>/dev/null)" in
				0|no|false|No) continue ;;
			esac
		fi
		_cap=""
		if [ -f "${_ps}/capacity" ]; then
			_cap="$(cat "${_ps}/capacity" 2>/dev/null | sed 's/[^0-9.]//g')"
		fi
		_status="$(cat "${_ps}/status" 2>/dev/null)"
		_ac_online=0
		for _ac in /sys/class/power_supply/AC* /sys/class/power_supply/Mains* \
			/sys/class/power_supply/ADP*; do
			[ -f "${_ac}/online" ] || continue
			case "$(cat "${_ac}/online" 2>/dev/null)" in
				1|yes|true) _ac_online=1; break ;;
			esac
		done
		# Plugged-in desktop: fake BAT at 0% / Unknown (common on ATX boards).
		if [ "${_ac_online}" -eq 1 ]; then
			case "${_cap}" in
				""|0|0.0)
					case "${_status}" in
						Unknown|Not*charging|Idle|Full|""|Discharging) continue ;;
					esac
					;;
			esac
			# lxpanel treats small numbers as % — amp-hour misreports trigger "low battery".
			if [ -n "${_cap}" ] && [ "${_cap%.*}" -lt 15 ] 2>/dev/null; then
				case "${_status}" in
					Unknown|Not*charging|Idle|Full|"") continue ;;
				esac
			fi
		fi
		if [ -f "${_ps}/energy_full" ]; then
			_ef="$(cat "${_ps}/energy_full" 2>/dev/null | sed 's/[^0-9]//g')"
			[ -n "${_ef}" ] && [ "${_ef}" -gt 0 ] 2>/dev/null && _found=1 && break
		fi
		if [ -f "${_ps}/charge_full" ]; then
			_cf="$(cat "${_ps}/charge_full" 2>/dev/null | sed 's/[^0-9]//g')"
			[ -n "${_cf}" ] && [ "${_cf}" -gt 0 ] 2>/dev/null && _found=1 && break
		fi
		if [ -n "${_cap}" ] && [ "${_cap%.*}" -ge 15 ] 2>/dev/null; then
			_found=1
			break
		fi
		case "${_status}" in
			Charging|Discharging|Full) _found=1; break ;;
		esac
	done
	[ "${_found}" -eq 1 ]
}
