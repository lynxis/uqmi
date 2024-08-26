#!/bin/sh

[ -n "$INCLUDE_ONLY" ] || {
	. /lib/functions.sh
	. ../netifd-proto.sh
	init_proto "$@"
}

PROTO_OPTIONS="apn username password pin roaming"
proto_qmid_init_config() {
	available=1
	no_device=1
	proto_config_add_string "device:device"
	proto_config_add_string apn
	proto_config_add_string username
	proto_config_add_string password
	proto_config_add_string pin
	proto_config_add_string roaming
	proto_config_add_defaults
}

# convert /dev/cdc-wdm0 -> modem0
_qmid_convert_devtoname() {
	local device="$1"

	if echo "${device}" | grep -q "/dev/cdc-wdm"; then
		echo "${device/\/dev\/cdc-wdm/modem}"
	else
		false
	fi
}

# check if uqmid already knows the device
_qmi_device_present() {
	ubus list "uqmid.modem.$1" 2>/dev/null >/dev/null
}

_qmi_ensure_device_present() {
	local name="$1"
	local device="$2"

	if _qmi_device_present "$name"; then
		return 0
	fi

	ubus call uqmid add_modem "{'name':'$name','device':'$device'}"
	_qmi_device_present "$name"
}

proto_qmid_setup() {
	local interface="$1"
	local device apn 
	local  $PROTO_DEFAULT_OPTIONS
	local ip4table ip6table
	local ip_6 ip_prefix_length gateway_6 dns1_6 dns2_6

	json_get_vars device $PROTO_OPTIONS
	json_get_vars ip4table ip6table $PROTO_DEFAULT_OPTIONS

	[ "$timeout" = "" ] && timeout="10"

	[ "$metric" = "" ] && metric="0"

	[ -n "$ctl_device" ] && device=$ctl_device

	[ -n "$device" ] || {
		echo "No control device specified"
		proto_notify_error "$interface" NO_DEVICE
		proto_set_available "$interface" 0
		return 1
	}

	[ -n "$delay" ] && sleep "$delay"

	device="$(readlink -f "$device")"
	[ -c "$device" ] || {
		echo "The specified control device does not exist"
		proto_notify_error "$interface" NO_DEVICE
		proto_set_available "$interface" 0
		return 1
	}

	devname="$(basename "$device")"
	devpath="$(readlink -f "/sys/class/usbmisc/$devname/device/")"
	ifname="$( ls "$devpath"/net )"
	[ -n "$ifname" ] || {
		echo "The interface could not be found."
		proto_notify_error "$interface" NO_IFACE
		proto_set_available "$interface" 0
		return 1
	}

	# check if uqmi already knows the device
	[ -z "$name" ] && name=$(_qmid_convert_devtoname "$device")

	if [ -z "$name" ]; then
		echo "Name not set and can't derived from device $device."
		proto_notify_error "$interface" NO_NAME
		proto_set_available "$interface" 0
		return 1
	fi

	if ! _qmi_ensure_device_present "$name" "$device"; then
		# can't create a device
		proto_notify_error "$interface" NO_IFACE_CREATABLE
		proto_set_available "$interface" 0
		return 1
	fi

	# pass configuration to it
	ubus call "uqmid.modem.$name" configure "{'apn':'$apn', 'username': '$username', 'password': '$password', 'pin': '$pin', 'roaming':'$roaming'}"

	# TODO: poll every second until sim is ready for max 10 seconds
	# fail with no modem availabil
	sleep 10

	# check if simcard is fine
	json_load "$(ubus call "uqmid.modem.$name" dump)"
	json_get_var state
	json_get_var simstate
	# use simstate as human readable to have more stable "api"

	case "$simstate" in
		1)
			# TODO add support for pincode/unlock
			proto_notify_error "$interface" SIM_PIN_REQUIRED
			proto_set_available "$interface" 0
			return 1
			;;
		2)
			proto_notify_error "$interface" SIM_PUK_REQUIRED
			proto_set_available "$interface" 0
			return 1
			;;
		3)
			# ready state
			;;
		4)
			# blocked state
			proto_notify_error "$interface" SIM_BLOCKED
			proto_set_available "$interface" 0
			return 1
			;;
		*)
			# unknown sim state
			proto_notify_error "$interface" SIM_STATE_UNKNOWN
			proto_set_available "$interface" 0
			return 1
			;;
	esac

	# poll here again for a state
	# TODO: until it reaches LIVE or the FSM terminates in a failure mode

	# 12 => LIVE state
	if [ "$state" != "12" ] ; then
		proto_notify_error "$interface" NOT_READY_YET
		proto_set_available "$interface" 0
		return 1
	fi

	json_get_var ipv4_addr
	json_get_var ipv4_netmask
	json_get_var ipv4_gateway
	json_get_var dns1
	json_get_var dns2

	proto_init_update "$ifname" 1
	proto_set_keep 1

	proto_add_ipv4_address "$ipv4_addr" "$ipv4_netmask"
	proto_add_ipv4_route "$ipv4_gateway" "32"
	[ "$defaultroute" = 0 ] || proto_add_ipv4_route "0.0.0.0" 0 "$gateway_4"

	[ "$peerdns" = 0 ] || {
		[ -n "$dns1" ] && proto_add_dns_server "$dns1"
		[ -n "$dns2" ] && proto_add_dns_server "$dns2"
	}
	[ -n "$zone" ] && {
		proto_add_data
		json_add_string zone "$zone"
		proto_close_data
	}
	proto_send_update "$interface"

	## state:
	## - last signal strength <- last, dump from internal state, not query it
	## - last network state
	## - 

	# TODO: check if SIM is initialized
	#		echo "SIM not initialized"
	#		proto_notify_error "$interface" SIM_NOT_INITIALIZED
	#		proto_block_restart "$interface"
	#		return 1

	# Check if UIM application is stuck in illegal state
	# TODO: proto_notify_error "$interface" NETWORK_REGISTRATION_FAILED
	## proto_init_update "$ifname" 1
	## proto_set_keep 1
	## proto_add_data
	## [ -n "$pdh_4" ] && {
	## 	json_add_string "cid_4" "$cid_4"
	## 	json_add_string "pdh_4" "$pdh_4"
	## }
	## [ -n "$pdh_6" ] && {
	## 	json_add_string "cid_6" "$cid_6"
	## 	json_add_string "pdh_6" "$pdh_6"
	## }
	## proto_close_data
	## proto_send_update "$interface"

	#	if [ -z "$dhcpv6" -o "$dhcpv6" = 0 ]; then
	#		json_load "$(uqmi -s -d $device -t 1000 --set-client-id wds,$cid_6 --get-current-settings)"
	#		json_select ipv6
	#		json_get_var ip_6 ip
	#		json_get_var gateway_6 gateway
	#		json_get_var dns1_6 dns1
	#		json_get_var dns2_6 dns2
	#		json_get_var ip_prefix_length ip-prefix-length
	#
	#		proto_init_update "$ifname" 1
	#		proto_set_keep 1
	#		proto_add_ipv6_address "$ip_6" "128"
	#		proto_add_ipv6_prefix "${ip_6}/${ip_prefix_length}"
	#		proto_add_ipv6_route "$gateway_6" "128"
	#		[ "$defaultroute" = 0 ] || proto_add_ipv6_route "::0" 0 "$gateway_6" "" "" "${ip_6}/${ip_prefix_length}"
	#		[ "$peerdns" = 0 ] || {
	#			proto_add_dns_server "$dns1_6"
	#			proto_add_dns_server "$dns2_6"
	#		}
	#		[ -n "$zone" ] && {
	#			proto_add_data
	#			json_add_string zone "$zone"
	#			proto_close_data
	#		}
	#		proto_send_update "$interface"
	#	else
	#		json_init
	#		json_add_string name "${interface}_6"
	#		json_add_string ifname "@$interface"
	#		[ "$pdptype" = "ipv4v6" ] && json_add_string iface_464xlat "0"
	#		json_add_string proto "dhcpv6"
	#		[ -n "$ip6table" ] && json_add_string ip6table "$ip6table"
	#		proto_add_dynamic_defaults
	#		# RFC 7278: Extend an IPv6 /64 Prefix to LAN
	#		json_add_string extendprefix 1
	#		[ -n "$zone" ] && json_add_string zone "$zone"
	#		json_close_object
	#		ubus call network add_dynamic "$(json_dump)"
	#	fi
}

proto_qmid_teardown() {
	local interface="$1"
	local device

	json_get_vars device

	[ -n "$ctl_device" ] && device=$ctl_device
	[ -z "$name" ] && name=$(_qmid_convert_devtoname "$device")

	echo "Stopping network $interface"

	# TODO: use stop instead of remove
	ubus call uqmid remove_modem "{ 'name': '$name' }"

	proto_init_update "*" 0
	proto_send_update "$interface"
}

[ -n "$INCLUDE_ONLY" ] || {
	add_protocol qmid
}
