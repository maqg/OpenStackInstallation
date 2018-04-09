#!/bin/bash

#
# For OpenStack Neutron Service Installation in Compute node
# Henry.Ma
#

. ./configure.sh
. ./functions.sh

LANG=C
LOGFILE=/var/log/openstack_install_neutron.log

OS_VERSION=$(cat /etc/centos-release | cut -b 22)

# Get platform and version info
get_platform_info
echo "Platform: \"$PLATFORM_TYPE\", Version: \"$PLATFORM_VERSION\"" >> $LOGFILE

if [ "$OS_VERSION" != 7 ]; then
	echo ""
	echo -e "\e[1;31mNow only CentOs 7.X are supported, $PLATFORM_TYPE not supported now.\e[0m"
	echo ""
	exit 1
fi

install_neutron_compute
echo ""
echo -e "\e[1;32mInstall Neutron Compute Node Service OK! \e[0m"
echo ""
