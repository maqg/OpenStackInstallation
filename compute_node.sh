#!/bin/bash

#
# For OpenStack Compute Node installation for Version PIKE CentOS Version 7
# Henry.Ma
# 03162018
#

. ./configure.sh
. ./functions.sh

LANG=C
DBPASSWD=123456
LOGFILE=/var/log/openstack_install_compute.log

OS_VERSION=$(cat /etc/centos-release | cut -b 22)

# like NAME#VERSION#MUST, for eg: python3#3.2#yes
PACKAGES="nginx:1.6.3:yes \
		  lrzsz::yes \
		  rabbitmq-server::yes \
		  chrony::yes \
		  zip::yes"

# Get platform and version info
get_platform_info
echo "Platform: \"$PLATFORM_TYPE\", Version: \"$PLATFORM_VERSION\"" >> $LOGFILE

if [ "$OS_VERSION" != 7 ]; then
	echo ""
	echo -e "\e[1;31mNow only CentOs 7.X are supported,$PLATFORM_TYPE not supported now.\e[0m"
	echo ""
	exit 1
fi

egrep -c '(vmx|svm)' /proc/cpuinfo > /dev/null 2>&1
if [ "$?" != 0 ]; then
	echo ""
	echo -e "\e[1;33mWARNING: No vmx or svm features found in CPU info, Hypervisor may not ready\e[0m"
	echo ""
fi

disable_selinux

config_compute_hosts
if [ "$?" != 0 ]; then
	echo ""
	echo -e "\e[1;31mConfigure Compute hosts Error!\e[0m"
	echo ""
	exit 1
fi
echo -e "\e[1;32mConfig Hosts OK! \e[0m"

install_compute_source
echo -e "\e[1;32mInstall $OPENSTACK_VERSION Source OK! \e[0m"

install_chrony
config_chrony_client
echo -e "\e[1;32mInstall and Config chrony OK! \e[0m"

install_compute_components
config_compute_service

echo ""
echo -e "\e[1;32mInstall OpenStack Compute Node of \"$OPENSTACK_VERSION\" OK! \e[0m"
echo -e "\e[1;32m EXEC CMD in controller: /bin/sh -c \"nova-manage cell_v2 discover_hosts --verbose\" nova \e[0m"
echo ""
