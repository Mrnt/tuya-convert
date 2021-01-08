#!/bin/bash

# Source config
. ../config.txt

version_check () {
	echo "System info"
	echo "==========="
	git rev-parse --short HEAD
	uname -a
	openssl version
	dnsmasq --version
	hostapd -v
	/usr/bin/env python3 --version
	echo "==========="
}

setup () {
	nm_service=
	rfkill unblock wifi

	wpa_supplicant_pid=$(pidof wpa_supplicant)
	if [ -n "$wpa_supplicant_pid" ]; then
		echo "Attempting to stop wpa_supplicant"
		sudo kill $wpa_supplicant_pid
	fi

	# get list of services and look for the network manager that normally runs
	if sudo ls -1 /etc/rc$(runlevel | cut -d" " -f2).d/S* | grep network-manager; then
		echo "Stopping NetworkManager..."
		sudo service network-manager stop
		nm_service=network-manager
	elif sudo ls -1 /etc/rc$(runlevel | cut -d" " -f2).d/S* | grep connman; then
		echo "Stopping ConnMan..."
		sudo service connman stop
		nm_service=connman
	fi

	echo "Configuring AP interface..."
	sudo ip link set $WLAN down
	sudo ip addr add $GATEWAY/24 dev $WLAN
	sudo ip link set $WLAN up
	sudo ip route add 10.42.42.0/24 dev $WLAN src $GATEWAY
	sudo ip route add 255.255.255.255 dev $WLAN

	echo "Starting DNSMASQ server..."
	sudo dnsmasq \
		--no-resolv \
		--interface=$WLAN \
		--bind-interfaces \
		--listen-address=$GATEWAY \
		--dhcp-range=10.42.42.10,10.42.42.40,12h \
		--address=/#/$GATEWAY

	echo "Starting AP on $WLAN..."

	# Read hostapd.conf with interface from stdin for
	# backward compatibility (hostapd < v2.6). See #398
	printf "$(cat hostapd.conf)\ninterface=$WLAN" | sudo hostapd /dev/stdin
}

cleanup () {
	sudo pkill hostapd
	echo "AP closed"

	echo "Stopping DNSMASQ server..."
	sudo pkill dnsmasq

	if [ ! -z "$nm_service" ]; then
		echo "Restarting network manager..."
		sudo service $nm_service restart
	fi
}

version_check
trap cleanup EXIT
setup

