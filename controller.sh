#!/bin/bash

#
# For OpenStack Compute Node installation for Version OCATA CentOS Version 7
# Henry.Ma
# 03162018
#

. ./configure.sh
. ./functions.sh

LANG=C
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

config_controller_hosts
if [ "$?" != 0 ]; then
	echo ""
	echo -e "\e[1;31mConfigure Controller host Error!\e[0m"
	echo ""
	exit 1
fi
echo -e "\e[1;32mConfig Hosts OK! \e[0m"

install_controller_source
echo -e "\e[1;32mInstall $OPENSTACK_VERSION Source OK! \e[0m"

install_chrony
config_chrony_server
echo -e "\e[1;32mInstall and Config chrony OK! \e[0m"

install_database
echo -e "\e[1;32mInstall and Config MariaDB OK! \e[0m"

install_rabbitmq
echo -e "\e[1;32mInstall and Config RabbitMQ OK! \e[0m"

install_memcached
echo -e "\e[1;32mInstall and Config MemCached OK! \e[0m"

install_controller_nova
echo -e "\e[1;32mInstall Controller nova OK! \e[0m"

echo ""
echo -e "\e[1;32mInstall OpenStack Controller of \"$OPENSTACK_VERSION\" OK! \e[0m"
echo ""
