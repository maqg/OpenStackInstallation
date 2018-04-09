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
		yum upgrade
		yum install python-openstackclient -y
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

install_etcd()
{
	RESULT=$(rpm -qa etcd)
	if [ "$RESULT" = "" ]; then

		yum install etcd -y

		FILE_RAW=./etcd_raw.conf
		FILE_TMP=./etcd.conf
		FILE_DST=/etc/etcd/etcd.conf
		FILE_BAK=/etc/etcd/etcd.conf.bak

		cp $FILE_RAW $FILE_TMP

		sed "s/CONTROLLER_ADDR/$CONTROLLER_ADDR/g" -i $FILE_TMP

		if [ ! -f $FILE_BAK ]; then
			cp $FILE_DST $FILE_BAK
		fi

		mv $FILE_TMP $FILE_DST

		systemctl enable etcd.service
		systemctl start etcd.service

		echo "Install ETCD OK"
	else
		echo "ETCD already installed"
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
	sed "s/NEUTRON_PASS/$NEUTRON_PASS/g" -i $FILE
	sed "s/PLACEMENT_PASS/$PLACEMENT_PASS/g" -i $FILE
	sed "s/CONTROLLER_HOSTNAME/$CONTROLLER_HOSTNAME/g" -i $FILE
	sed "s/MANAGEMENT_INTERFACE_IP_ADDRESS/$COMPUTE_MANAGE_ADDR/g" -i $FILE

	cp $FILE /etc/nova/nova.conf

	systemctl enable libvirtd.service openstack-nova-compute.service
	systemctl start libvirtd.service openstack-nova-compute.service

	rm $FILE

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
	openstack user show nova > /dev/null 2>&1
	if [ "$?" = 0 ]; then
		echo "Nova Service Already Configured"
		return
	fi

	# Create Nova User
	echo "To create 'nova' User OK"
	openstack user create --domain default --password $NOVA_PASS nova
	echo "Create 'nova' User OK"

	echo "To add 'admin' role to 'nova' user"
	openstack role add --project service --user nova admin
	echo "add 'admin' role to 'nova' user OK"

	echo "To create 'nova' service"
	openstack service create --name nova --description "OpenStack Compute" compute
	echo "Create 'nova' service OK"

	echo "To Create Compute API Service"
	openstack endpoint create --region RegionOne compute public http://$CONTROLLER_HOSTNAME:8774/v2.1
	openstack endpoint create --region RegionOne compute internal http://$CONTROLLER_HOSTNAME:8774/v2.1
	openstack endpoint create --region RegionOne compute admin http://$CONTROLLER_HOSTNAME:8774/v2.1
	echo "Create Compute API Service OK"

	echo "To Create placement Service"
	openstack user create --domain default --password $PLACEMENT_PASS placement
	openstack role add --project service --user placement admin
	openstack service create --name placement --description "Placement API" placement
	openstack endpoint create --region RegionOne placement public http://$CONTROLLER_HOSTNAME:8778
	openstack endpoint create --region RegionOne placement internal http://$CONTROLLER_HOSTNAME:8778
	openstack endpoint create --region RegionOne placement admin http://$CONTROLLER_HOSTNAME:8778
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
	sed "s/NEUTRON_PASS/$NEUTRON_PASS/g" -i $FILE_TMP
	sed "s/METADATA_SECRET/$METADATA_SECRET/g" -i $FILE_TMP
	sed "s/CONTROLLER_ADDR/$CONTROLLER_ADDR/g" -i $FILE_TMP
	sed "s/CONTROLLER_HOSTNAME/$CONTROLLER_HOSTNAME/g" -i $FILE_TMP

	if [ ! -f $FILE_BAK ]; then
		cp $FILE_DST $FILE_BAK
	fi

	mv $FILE_TMP $FILE_DST

	echo "Config Nova Service OK"
}

config_placement_http()
{
	FILE_RAW=./00-nova-placement-api.conf
	FILE_DST=/etc/httpd/conf.d/00-nova-placement-api.conf
	FILE_BAK=/etc/httpd/conf.d/00-nova-placement-api.conf.bak

	if [ ! -f $FILE_BAK ]; then
		cp $FILE_DST $FILE_BAK
	fi

	cp $FILE_RAW $FILE_DST

	systemctl restart httpd

	echo "Config Placement HTTP Service OK"
}

install_nova_controller()
{
	nova-manage cell_v2 list_cells
	if [ "$?" = 0 ]; then
		echo "Nova Service already installed"
		return 0
	fi

	# Step1, Config Nova Database
	config_nova_database
	echo "Config Nova Database OK"

	# Step2, Install Nova Serviec
	install_nova_service
	echo "Install Nova Service OK"

	# Step3, Config Nova
	config_nova_service
	echo "Config Nova Service OK"

	# Step4, Config Placement Http Service
	config_placement_http
	echo "Config Placement Service OK"

	# Step 5, To sync DB Config
	/bin/sh -c "nova-manage api_db sync" nova
	/bin/sh -c "nova-manage cell_v2 map_cell0" nova
	/bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova
	/bin/sh -c "nova-manage db sync" nova
	echo "Sync Nova Database OK"

	# Step6, Finalize installation
	finalize_nova_installation
	echo "Finalize Nova Installation OK"

	# Step7, To Verify Installation
	nova-manage cell_v2 list_cells
	echo "Test Nova Installation OK"

	echo "Install Nova Service OK"
}


config_keystone_database()
{
	mysql -uroot -p$DBROOT_PASS -e "use keystone;" > /dev/null 2>&1
	if [ "$?" != 0 ]; then
		mysql -uroot -p$DBROOT_PASS -e "CREATE DATABASE keystone;"
		mysql -uroot -p$DBROOT_PASS -e "GRANT ALL PRIVILEGES ON keystone.* TO 'nova'@'localhost' IDENTIFIED BY '$KEYSTONE_PASS';"
		mysql -uroot -p$DBROOT_PASS -e "GRANT ALL PRIVILEGES ON keystone.* TO 'nova'@'%' IDENTIFIED BY '$KEYSTONE_PASS';"
	fi
}


install_keystone_service()
{
	echo "To Install KeyStone Service"
	yum install openstack-keystone httpd mod_wsgi -y
	echo "Install KeyStone Service OK"
}


config_keystone()
{
	FILE_RAW=./keystone_raw.conf
	FILE_TMP=./keystone.conf
	FILE_DST=/etc/keystone/keystone.conf
	FILE_BAK=/etc/keystone/keystone.conf.bak

	if [ -f $FILE_BAK ]; then
		echo "KeyStone Already Configured"
		return 1
	fi

	cp $FILE_RAW $FILE_TMP

	sed "s/KEYSTONE_PASS/$KEYSTONE_PASS/g" -i $FILE_TMP

	if [ ! -f $FILE_BAK ]; then
		cp $FILE_DST $FILE_BAK
	fi

	mv $FILE_TMP $FILE_DST

	# Sync keystone database
	/bin/sh -c "keystone-manage db_sync" keystone

	echo "To Initialize fetnet respositories"
	keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
	keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

	keystone-manage bootstrap --bootstrap-password $ADMIN_PASS \
		--bootstrap-admin-url http://$CONTROLLER_HOSTNAME:35357/v3/ \
		--bootstrap-internal-url http://$CONTROLLER_HOSTNAME:5000/v3/ \
		--bootstrap-public-url http://$CONTROLLER_HOSTNAME:5000/v3/ \
		--bootstrap-region-id RegionOne

	echo "Config KeyStone Service OK"
}


config_keystone_apache()
{
	if [ -f /etc/httpd/conf.d/wsgi-keystone.conf ]; then
		echo "KeyStone Apache Already Configured"
		return 1
	fi

	ln -s /usr/share/keystone/wsgi-keystone.conf /etc/httpd/conf.d/

	sed -i '/^ServerName*/d' /etc/httpd/conf/httpd.conf
	sed -i "N;1aServerName $CONTROLLER_HOSTNAME" /etc/httpd/conf/httpd.conf

	systemctl enable httpd.service
	systemctl restart httpd.service

	echo "Config KeyStone Apache OK"
}


initialize_keystone()
{
	# create service project
	openstack project create --domain default --description "Service Project" service

	# Create Demo Project:
	openstack project create --domain default --description "Demo Project" demo

	# Create Demo User, with password demo123
	openstack user create --domain default --password $DEMO_PASS demo

	# Create User Role
	openstack role create user
	 
	# Add the user role to the demo user of the demo project:
	openstack role add --project demo --user demo user

	echo "Initialize KeyStone OK"
}

install_keystone()
{
	echo "Start to run KeyStone installation"

	source ./admin-openrc
	openstack token issue > /dev/null 2>&1
	if [ "$?" = 0 ]; then
		echo "KeyStone Already Installed"
		return 1
	fi

	# Step1, Config Database
	config_keystone_database
	echo "Config KeyStone Database OK"

	# Step2, Install KeyStone Service
	install_keystone_service
	echo "Install KeyStone Service OK"

	# Step3, Config KeyStone
	config_keystone
	echo "Config KeyStone OK"

	# Step4, Config Apache
	config_keystone_apache
	echo "Config KeyStone Apache OK"

	# Step5, Initialize KeyStone
	initialize_keystone
	echo "Initialize KeyStone OK"

	# Verify KeyStone
	source ./admin-openrc
	unset OS_AUTH_URL OS_PASSWORD

	openstack --os-auth-url http://$CONTROLLER_HOSTNAME:35357/v3 --os-project-domain-name default \
		--os-user-domain-name default --os-project-name admin --os-username admin token issue

	echo "Install KeyStone Service OK"
}


config_glance_database()
{
	mysql -uroot -p$DBROOT_PASS -e "use glance;" > /dev/null 2>&1
	if [ "$?" != 0 ]; then
		mysql -uroot -p$DBROOT_PASS -e "CREATE DATABASE glance;"
		mysql -uroot -p$DBROOT_PASS -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$GLANCE_PASS';"
		mysql -uroot -p$DBROOT_PASS -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$GLANCE_PASS';"
	fi
	
}


create_glance_credentials()
{
	openstack user show glance
	if [ "$?" = 0 ]; then
		echo "glance USER already exist"
		return 0
	fi

	openstack user create --domain default --password $GLANCE_PASS glance

	openstack role add --project service --user glance admin

	openstack service create --name glance --description "OpenStack Image" image

	openstack endpoint create --region RegionOne image public http://$CONTROLLER_HOSTNAME:9292

	openstack endpoint create --region RegionOne image internal http://$CONTROLLER_HOSTNAME:9292

	openstack endpoint create --region RegionOne image admin http://$CONTROLLER_HOSTNAME:9292

	echo "Create Glance Credentials OK"
}

config_glance_registry()
{
	FILE_RAW=./glance-registry_raw.conf
	FILE_TMP=./glance-registry.conf
	FILE_DST=/etc/glance/glance-registry.conf
	FILE_BAK=/etc/glance/glance-registry.conf.bak

	if [ -f $FILE_BAK ]; then
		echo "Glance API Service already configured"
		return 0
	fi

	cp $FILE_RAW $FILE_TMP

	sed "s/GLANCE_PASS/$GLANCE_PASS/g" -i $FILE_TMP

	if [ ! -f $FILE_BAK ]; then
		cp $FILE_DST $FILE_BAK
	fi

	mv $FILE_TMP $FILE_DST

	echo "Config Glance Registry Service OK"
}


config_glance_api()
{
	FILE_RAW=./glance-api_raw.conf
	FILE_TMP=./glance-api.conf
	FILE_DST=/etc/glance/glance-api.conf
	FILE_BAK=/etc/glance/glance-api.conf.bak

	if [ -f $FILE_BAK ]; then
		echo "Glance Service already configured"
		return 0
	fi

	cp $FILE_RAW $FILE_TMP

	sed "s/GLANCE_PASS/$GLANCE_PASS/g" -i $FILE_TMP

	if [ ! -f $FILE_BAK ]; then
		cp $FILE_DST $FILE_BAK
	fi

	mv $FILE_TMP $FILE_DST

	echo "Config Glance Service OK"
}

verify_glance_installation()
{
	openstack image show cirrus
	if [ "$?" = 0 ]; then
		echo "Image already installed"
		return 0
	fi

	. admin-openrc

	wget http://download.cirros-cloud.net/0.3.5/cirros-0.3.5-x86_64-disk.img -o ../cirros-0.3.5-x86_64-disk.img

	openstack image create "cirros" \
		--file ../cirros-0.3.5-x86_64-disk.img \
	    --disk-format qcow2 --container-format bare \
	    --public

	openstack image list

	if [ "$?" = 0 ]; then
		echo "Verify Glance Installation OK"
	else
		echo "Verify Glance Installation Failed"
	fi
}

install_glance()
{
	echo "To install Glance Servce Now"

	source ./admin-openrc

	echo "To install glance service"
	config_glance_database
	echo "Install glance service OK"

	echo "To create glance credentials"
	create_glance_credentials
	echo "Create glance credentials OK"

	yum install openstack-glance -y

	echo "To Config Glance Service"
	config_glance_api
	echo "Config Glance Service OK"

	echo "To Config Glance Registry Service"
	config_glance_registry
	echo "Config Glance Registry Service OK"

	/bin/sh -c "glance-manage db_sync" glance 
	chmod 777 /var/log/glance/* -R
	
	systemctl enable openstack-glance-api.service openstack-glance-registry.service
	systemctl restart openstack-glance-api.service openstack-glance-registry.service

	echo "To Verify Glance installation"
	verify_glance_installation
	echo "Verified Glance Service"
}


config_neutron_database()
{
	mysql -uroot -p$DBROOT_PASS -e "use neutron;" > /dev/null 2>&1
	if [ "$?" != 0 ]; then
		mysql -uroot -p$DBROOT_PASS -e "CREATE DATABASE neutron;"
		mysql -uroot -p$DBROOT_PASS -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$NEUTRON_PASS';"
		mysql -uroot -p$DBROOT_PASS -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$NEUTRON_PASS';"
	fi
}


create_neutron_credentials()
{
	openstack user show neutron
	if [ "$?" = 0 ]; then
		echo "neutron USER already exist"
		return 0
	fi

	. admin-openrc

	openstack user create --domain default --password $NEUTRON_PASS neutron

	openstack role add --project service --user neutron admin

	openstack service create --name neutron --description "OpenStack Networking" network

	openstack endpoint create --region RegionOne network public http://$CONTROLLER_HOSTNAME:9696

	openstack endpoint create --region RegionOne network internal http://$CONTROLLER_HOSTNAME:9696

	openstack endpoint create --region RegionOne network admin http://$CONTROLLER_HOSTNAME:9696
}

config_controller_neutron()
{
	FILE_RAW=./neutron_raw.conf
	FILE_TMP=./neutron.conf
	FILE_DST=/etc/neutron/neutron.conf
	FILE_BAK=/etc/neutron/neutron.conf.bak

	cp $FILE_RAW $FILE_TMP

	sed "s/RABBIT_PASS/$RABBIT_PASS/g" -i $FILE_TMP
	sed "s/NOVA_PASS/$NOVA_PASS/g" -i $FILE_TMP
	sed "s/NEUTRON_PASS/$PLACEMENT_PASS/g" -i $FILE_TMP
	sed "s/CONTROLLER_HOSTNAME/$CONTROLLER_HOSTNAME/g" -i $FILE_TMP

	if [ ! -f $FILE_BAK ]; then
		cp $FILE_DST $FILE_BAK
	fi

	mv $FILE_TMP $FILE_DST

	echo "Config Neutron Controller Service OK"

}

config_controller_ml2()
{
	DST_FILE=/etc/neutron/plugins/ml2/ml2_conf.ini
	DST_FILE_BAK=/etc/neutron/plugins/ml2/ml2_conf.ini.bak
	if [ ! -f $DST_FILE_BAK ]; then
		cp $DST_FILE $DST_FILE_BAK
	fi

echo "[DEFAULT]
[ml2]
type_drivers = flat,vlan
tenant_network_types =
mechanism_drivers = linuxbridge
extension_drivers = port_security
[ml2_type_flat]
flat_networks = provider
[ml2_type_geneve]
[ml2_type_gre]
[ml2_type_vlan]
[ml2_type_vxlan]
[securitygroup]
enable_ipset = true" > $DST_FILE
}

config_controller_linuxbridge()
{
	DST_FILE=/etc/neutron/plugins/ml2/linuxbridge_agent.ini
	DST_FILE_BAK=/etc/neutron/plugins/ml2/linuxbridge_agent.ini.bak
	if [ ! -f $DST_FILE_BAK ]; then
		cp $DST_FILE $DST_FILE_BAK
	fi

echo "[linux_bridge]
physical_interface_mappings = provider:$PROVIDER_INTERFACE_NAME
[vxlan]
enable_vxlan = false
[securitygroup]
enable_security_group = true
firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver" > $DST_FILE
}

config_controller_dhcp()
{
	DST_FILE=/etc/neutron/dhcp_agent.ini
	DST_FILE_BAK=/etc/neutron/dhcp_agent.ini.bak
	if [ ! -f $DST_FILE_BAK ]; then
		cp $DST_FILE $DST_FILE_BAK
	fi

echo "[DEFAULT]
interface_driver = linuxbridge
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq
enable_isolated_metadata = true" > $DST_FILE
}


# FOR CONTROLLER NODE
install_provider_networks()
{
	echo "To install Provider Networks"
	yum install openstack-neutron openstack-neutron-ml2 openstack-neutron-linuxbridge ebtables -y
	echo "Install Provider Networks OK"

	echo "To Config Neutron"
	config_controller_neutron
	echo "Config Neutron OK"

	# Modular Layer 2
	echo "To Config Modular Layer 2"
	config_controller_ml2
	echo "Config Modular Layer 2 OK"

	echo "To Config Controller Linux Bridge"
	config_controller_linuxbridge
	echo "Config Controller Linux Bridge OK"

	echo "To Config Controller DHCP"
	config_controller_dhcp
	echo "Config Controller DHCP OK"
}

config_metadata_agent()
{
	DST_FILE=/etc/neutron/metadata_agent.ini
	DST_FILE_BAK=/etc/neutron/metadata_agent.ini.bak
	if [ ! -f $DST_FILE_BAK ]; then
		cp $DST_FILE $DST_FILE_BAK
	fi

echo "[DEFAULT]
nova_metadata_host = $CONTROLLER_HOSTNAME
metadata_proxy_shared_secret = $METADATA_SECRET" > $DST_FILE
}

install_neutron()
{

	echo "To Config neutron database"
	config_neutron_database
	echo "Config neutron database OK"

	echo "To create neutron credentials"
	create_neutron_credentials
	echo "Create neutron credentials OK"

	echo "To Install Provider Networks"
	install_provider_networks
	echo "Install Provider Networks OK"

	echo "To Config Metadata Agent"
	config_metadata_agent
	echo "Config Metadata Agent OK"

	ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini

	# sync database
	/bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf \
	--config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron

	systemctl restart openstack-nova-api.service

	systemctl enable neutron-server.service \
		neutron-linuxbridge-agent.service neutron-dhcp-agent.service \
		neutron-metadata-agent.service
	systemctl start neutron-server.service \
		neutron-linuxbridge-agent.service neutron-dhcp-agent.service \
		neutron-metadata-agent.service

	systemctl enable neutron-l3-agent.service
	systemctl start neutron-l3-agent.service

	echo "Install Controller Node Neutron OK"
}


config_compute_provider_networks()
{
	DST_FILE=/etc/neutron/plugins/ml2/linuxbridge_agent.ini
	DST_FILE_BAK=/etc/neutron/plugins/ml2/linuxbridge_agent.ini.bak
	if [ ! -f $DST_FILE_BAK ]; then
		cp $DST_FILE $DST_FILE_BAK
	fi

echo "[DEFAULT]
[linux_bridge]
physical_interface_mappings = provider:$PROVIDER_INTERFACE_NAME
[vxlan]
enable_vxlan = false
[securitygroup]
enable_security_group = true
firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver" > $DST_FILE
	return 0
}

config_neutron_compute()
{
	DST_FILE=/etc/neutron/neutron.conf
	DST_FILE_BAK=/etc/neutron/neutron.conf.bak
	if [ ! -f $DST_FILE_BAK ]; then
		cp $DST_FILE $DST_FILE_BAK
	fi

echo "[DEFAULT]
[DEFAULT]
transport_url = rabbit://openstack:$RABBIT_PASS@$CONTROLLER_HOSTNAME
auth_strategy = keystone
[keystone_authtoken]
auth_uri = http://$CONTROLLER_HOSTNAME:5000
auth_url = http://$CONTROLLER_HOSTNAME:35357
memcached_servers = $CONTROLLER_HOSTNAME:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = neutron
password = $NEUTRON_PASS
[oslo_concurrency]
lock_path = /var/lib/neutron/tmp" > $DST_FILE
	return 0
}

install_neutron_compute()
{
	yum install openstack-neutron-linuxbridge ebtables ipset -y

	config_neutron_compute
	if [ "$?" != 0 ]; then
		echo "config neutron in compute node error"
		return 1
	fi
	echo "Config neutron in compute node OK"

	config_compute_provider_networks
	if [ "$?" != 0 ]; then
		echo "config provider networks in compute node error"
		return 1
	fi
	echo "Config Compute Provider Networks OK"

	echo "WARNING: Must config neutron setting to nova in compute..."
	
	systemctl restart openstack-nova-compute.service
	systemctl enable neutron-linuxbridge-agent.service
	systemctl start neutron-linuxbridge-agent.service

	echo "Install Neutron Service in Compute node OK"

	echo "In Controller node to verify: . admin-openrc\nopenstack network agent list"

	return 0
}
