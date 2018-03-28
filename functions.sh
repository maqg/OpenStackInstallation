#!/bin/bash

#
# Base functions for common use
#
# Henry.Ma
#

PLATFORM_DEBIAN="debian"
PLATFORM_CENTOS="centos"

get_platform_info()
{
	if [ -f /etc/debian_version ]; then
		PLATFORM_TYPE="debian"
		PLATFORM_VERSION=$(cat /etc/debian_version | awk -F'.' '{print$1}')
	elif [ -f /etc/centos-release ]; then
		PLATFORM_TYPE="centos"
		PLATFORM_VERSION=$(cat /etc/centos-release | awk -F '.' '{print $1}' | awk -F' ' '{print $4}')
	else
		PLATFORM_TYPE=$PLATFORM_UNKNOWN
		PLATFORM_VERSION="0"
	fi
}


config_controller_hosts()
{
	HOST_FILE="/etc/hosts"
	echo "127.0.0.1 localhost localhost.localdomain localhost4 localhost4.localdomain4" > $HOST_FILE
	echo "$CONTROLLER_ADDR $CONTROLLER_HOSTNAME" >> $HOST_FILE
	echo "$COMPUTE_ADDR $COMPUTE_HOSTNAME" >> $HOST_FILE
	echo "Config compute host $COMPUTE_ADDR with hostname $COMPUTE_HOSTNAME OK!"
	return 0
}


config_compute_hosts()
{
	HOST_FILE="/etc/hosts"
	echo "127.0.0.1 localhost localhost.localdomain localhost4 localhost4.localdomain4" > $HOST_FILE
	echo "$CONTROLLER_ADDR $CONTROLLER_HOSTNAME" >> $HOST_FILE
	echo "$COMPUTE_ADDR $COMPUTE_HOSTNAME" >> $HOST_FILE
	echo "Config compute host $COMPUTE_ADDR with hostname $COMPUTE_HOSTNAME OK!"
	return 0
}


install_chrony()
{
	yum install chrony -y
	echo "Install chrony OK"
	return 0
}

config_chrony_client()
{
	CHRONY_CONFIG_FILE=/etc/chrony.conf
	sed -i '/^server*/d' $CHRONY_CONFIG_FILE
	sed -i "N;2aserver $CONTROLLER_HOSTNAME" $CHRONY_CONFIG_FILE
	systemctl enable chronyd.service
	systemctl start chronyd.service
	echo "Config chronyd Service OK"
	return 0
}

config_chrony_server()
{
	FILE_RAW=./chrony_server_raw.conf
	FILE_TMP=./chrony_server.conf
	FILE_DST=/etc/chrony.conf
	FILE_BAK=/etc/chrony.conf.bak

	cp $FILE_RAW $FILE_TMP

	sed "s/allow/allow $COMPUTE_NETWORK/g" -i $FILE_TMP

	if [ ! -f $FILE_BAK ]; then
		cp $FILE_DST $FILE_BAK
	fi

	mv $FILE_TMP $FILE_DST

	systemctl enable chronyd.service
	systemctl start chronyd.service

	echo "Config chronyd Service OK"
}


install_controller_source()
{
	RESULT=$(rpm -qa centos-release-openstack-$OPENSTACK_VERSION)
	if [ "$RESULT" = "" ]; then
		yum install centos-release-openstack-$OPENSTACK_VERSION -y
		yum install https://rdoproject.org/repos/rdo-release.rpm -y
		yum upgrade
		yum install python-openstackclient -y
		yum install openstack-selinux -y
	fi
	echo "Install $OPENSTACK_VERSION OpenStack Source OK"
}

install_compute_source()
{
	RESULT=$(rpm -qa centos-release-openstack-$OPENSTACK_VERSION)
	if [ "$RESULT" = "" ]; then
		yum install centos-release-openstack-$OPENSTACK_VERSION -y
		yum upgrade
	fi
	echo "Install $OPENSTACK_VERSION OpenStack Source OK"
}

install_rabbitmq()
{
	RESULT=$(rpm -qa rabbitmq-server)
	if [ "$RESULT" = "" ]; then
		yum install rabbitmq-server -y

		systemctl enable rabbitmq-server.service
		systemctl start rabbitmq-server.service

		rabbitmqctl add_user openstack $RABBIT_PASS

		rabbitmqctl set_permissions openstack ".*" ".*" ".*"

		echo "Install RabbitMQ OK"
	else
		echo "RabbitMQ already installed"
	fi
}

install_memcached()
{
	RESULT=$(rpm -qa python-memcached)
	if [ "$RESULT" = "" ]; then

		yum install memcached python-memcached -y

		CONFIG_FILE=/etc/sysconfig/memcached

		echo "PORT=\"11211\"
		USER=\"memcached\"
		MAXCONN=\"1024\"
		CACHESIZE=\"64\"
		OPTIONS=\"-l 127.0.0.1,::1,$CONTROLLER_HOSTNAME\"" > $CONFIG_FILE
		
		systemctl enable memcached.service
		systemctl start memcached.service

		echo "Install MemCached OK"
	else
		echo "MemCached already installed"
	fi
}

install_database()
{
	RESULT=$(rpm -qa python2-PyMySQL)
	if [ "$RESULT" = "" ]; then
		yum install mariadb mariadb-server python2-PyMySQL -y

		DBFILE=/etc/my.cnf.d/openstack.cnf
		touch $DBFILE

		echo "[mysqld]" >> $DBFILE
		echo "bind-address = $CONTROLLER_ADDR" >> $DBFILE
		echo "default-storage-engine = innodb" >> $DBFILE
		echo "innodb_file_per_table = on" >> $DBFILE
		echo "max_connections = 4096" >> $DBFILE
		echo "collation-server = utf8_general_ci" >> $DBFILE
		echo "character-set-server = utf8" >> $DBFILE

		systemctl enable mariadb.service
		systemctl start mariadb.service

		mysql_secure_installation

		echo "Install MariaDB OK"
	else
		echo "MariaDB already installed"
	fi
}

install_compute_components()
{
	yum install openstack-nova-compute -y
	echo "Install Compute Components OK"
}

#
# sed '/^\s*$/d' -i nova.conf
# sed '/^#/d' -i nova.conf
#
config_compute_service()
{
	FILE=./nova_compute.conf
	cp ./nova_compute_raw.conf $FILE
	sed "s/RABBIT_PASS/$RABBIT_PASS/g" -i $FILE
	sed "s/NOVA_PASS/$NOVA_PASS/g" -i $FILE
	sed "s/PLACEMENT_PASS/$PLACEMENT_PASS/g" -i $FILE
	sed "s/MANAGEMENT_INTERFACE_IP_ADDRESS/$COMPUTE_MANAGE_ADDR/g" -i $FILE

	cp $FILE /etc/nova/nova.conf

	systemctl enable libvirtd.service openstack-nova-compute.service
	systemctl start libvirtd.service openstack-nova-compute.service

	echo "Config Compute Service OK"
}

config_nova_database()
{
	mysql -uroot -p$DBROOT_PASS -e "use nova;" > /dev/null 2>&1
	if [ "$?" != 0 ]; then
		mysql -uroot -p$DBROOT_PASS -e "CREATE DATABASE nova_api;"
		mysql -uroot -p$DBROOT_PASS -e "CREATE DATABASE nova;"
		mysql -uroot -p$DBROOT_PASS -e "CREATE DATABASE nova_cell0;"
		mysql -uroot -p$DBROOT_PASS -e "GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_PASS';"
		mysql -uroot -p$DBROOT_PASS -e "GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_PASS';"
		mysql -uroot -p$DBROOT_PASS -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_PASS';"
		mysql -uroot -p$DBROOT_PASS -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_PASS';"
		mysql -uroot -p$DBROOT_PASS -e "GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_PASS';"
		mysql -uroot -p$DBROOT_PASS -e "GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_PASS';"
	fi
	
}

install_nova_service()
{
	# Create Nova User
	echo "To create 'nova' User OK"
	openstack user create --domain default --password-prompt nova
	echo "Create 'nova' User OK"

	echo "To add 'admin' role to 'nova' user"
	openstack role add --project service --user nova admin
	echo "add 'admin' role to 'nova' user OK"

	echo "To create 'nova' service"
	openstack service create --name nova --description "OpenStack Compute" compute
	echo "Create 'nova' service OK"

	echo "To Create Compute API Service"
	openstack endpoint create --region RegionOne compute public http://controller:8774/v2.1
	openstack endpoint create --region RegionOne compute internal http://controller:8774/v2.1
	openstack endpoint create --region RegionOne compute admin http://controller:8774/v2.1
	echo "Create Compute API Service OK"

	echo "To Create placement Service"
	openstack user create --domain default --password-prompt placement
	openstack role add --project service --user placement admin
	openstack service create --name placement --description "Placement API" placement
	openstack endpoint create --region RegionOne placement public http://controller:8778
	openstack endpoint create --region RegionOne placement internal http://controller:8778
	openstack endpoint create --region RegionOne placement admin http://controller:8778
	echo "Create placement Service OK"

	echo "To Install Nova Service"
	yum install openstack-nova-api openstack-nova-conductor openstack-nova-console openstack-nova-novncproxy openstack-nova-scheduler openstack-nova-placement-api -y
	echo "Install Nova Service OK"
}

finalize_nova_installation()
{
	systemctl enable openstack-nova-api.service openstack-nova-consoleauth.service \
		openstack-nova-scheduler.service openstack-nova-conductor.service openstack-nova-novncproxy.service
	systemctl start openstack-nova-api.service openstack-nova-consoleauth.service \
		openstack-nova-scheduler.service openstack-nova-conductor.service openstack-nova-novncproxy.service

	echo "Finalize nova installation OK"
}

config_nova_service()
{
	FILE_RAW=./nova_raw.conf
	FILE_TMP=./nova.conf
	FILE_DST=/etc/nova/nova.conf
	FILE_BAK=/etc/nova/nova.conf.bak

	cp $FILE_RAW $FILE_TMP

	sed "s/RABBIT_PASS/$RABBIT_PASS/g" -i $FILE_TMP
	sed "s/NOVA_PASS/$NOVA_PASS/g" -i $FILE_TMP
	sed "s/PLACEMENT_PASS/$PLACEMENT_PASS/g" -i $FILE_TMP
	sed "s/CONTROLLER_ADDR/$CONTROLLER_ADDR/g" -i $FILE_TMP
	sed "s/CONTROLLER_HOSTNAME/$CONTROLLER_HOSTNAME/g" -i $FILE_TMP

	if [ ! -f $FILE_BAK ]; then
		cp $FILE_DST $FILE_BAK
	fi

	mv $FILE_TMP $FILE_DST

	echo "Config Nova Service OK"
}

install_nova()
{
	# Step1, Config Nova Database
	config_nova_database

	# Step2, Install Nova Serviec
	install_nova_service

	# Step3, Config Nova
	config_nova_service

	# Step6, Finalize installation
	finalize_nova_installation

	echo "Install No Service OK"
}
