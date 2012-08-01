#!/bin/bash
set -e

# ENV SETUP
HOME="/home"
INSTALLER_PATH="/home/javi/stratus5/dev/projects/entando"
MYSQL_USER="root"
MYSQL_PWD="q1w2e3r4"

DIR=$(pwd)


############## FUNCTIONS ###########################################

function installEntando {
	echo "Installing User $USER"
	## GET SEQUENTIAL NUMBER
	set +e
	ls -d /home/entando*
	AUX=$?
	set -e
	# Sequential number with number of installs to calculate ports
	if [ $? != 0 ]; then
		SEQ=0
	else
		SEQ=$(ls -d /home/entando* | wc -l)
	fi
	echo "Got Sequence number $SEQ"

	## CREATE OS-USER and FOLDERS

	if [ "z`getent group $USER`" = "z" ]; then
			groupadd $USER >> /dev/null 2>&1
			echo "Group $USER created"	
  fi

  if [ "z`getent passwd $USER`" = "z" ]; then
			#ENCRYPTED_PASSWORD=$(mkpasswd -H md5 "$PWD")
			useradd -m -d $INSTALL_PATH -s /bin/bash --password $PWD -g $USER $USER >> /dev/null 2>&1 
			echo "User $USER created"	
	fi

	echo "Creating folders in $INSTALL_PATH"
	mkdir $INSTALL_PATH/postgresql
	mkdir $INSTALL_PATH/tomcat
	mkdir $INSTALL_PATH/logs
	mkdir $INSTALL_PATH/apache

	## COPY SOURCES
	echo "Copying sources from $INSTALLER_PATH/Tomcat_6/ to $INSTALL_PATH/tomcat"
	cp $INSTALLER_PATH/Tomcat_6/*	$INSTALL_PATH/tomcat -r
	
	## CREATE CONFIG FILES
	echo "Creating config files"	
	sed -i "s/5432/$POSTGRES_PORT/g" $INSTALL_PATH/tomcat/webapps/entandobi/META-INF/context.xml
	sed -i "s/5432/$POSTGRES_PORT/g" $INSTALL_PATH/tomcat/webapps/entando-demo/META-INF/context.xml
	sed -i "s/5432/$POSTGRES_PORT/g" $INSTALL_PATH/tomcat/webapps/pentaho/META-INF/context.xml

	chown $USER $INSTALL_PATH -R

	### CREATE DB-CLUSTER ###
	echo "Creating DataBase clusters"
	POSTGRES_PORT=$(( 6001 + $SEQ ))
	PGDATA=$INSTALL_PATH/postgresql
	PGLOG=$INSTALL_PATH/logs/postgresql.log
	echo "DataBasePort $POSTGRES_PORT Data folder $PGDATA"
	# get uid of ob_user to be used as postgres superuser
	PGUID=$(getent passwd $USER | cut -d ':' -f3)
	/usr/bin/pg_createcluster -e UTF-8 -u $PGUID -d $PGDATA -s $PGDATA -l $PGLOG -p $POSTGRES_PORT --start-conf manual 8.4 $USER || { log_end_msg 1; exit 1; }
	sed -i "s/md5/trust/g" /etc/postgresql/8.4/$USER/pg_hba.conf || { log_end_msg 1; exit 1; }

	echo "Starting postgresql cluster $USER"
	sudo -u $USER /usr/bin/pg_ctlcluster 8.4 $USER start

	echo "Creating DBs "
	sudo -u $USER psql --cluster 8.4/$USER -d postgres -h localhost -p $POSTGRES_PORT -c "create user agile password '$PWD';
create user entandobiuser password '$PWD';"
	sudo -u $USER psql --cluster 8.4/$USER -d postgres -h localhost -p $POSTGRES_PORT -c "drop database \"entando-demoPort\";" || true
	sudo -u $USER psql --cluster 8.4/$USER -d postgres -h localhost -p $POSTGRES_PORT -c "create database \"entando-demoPort\" WITH OWNER agile ENCODING 'UTF8';"
	sudo -u $USER psql --cluster 8.4/$USER -d postgres -h localhost -p $POSTGRES_PORT -c "drop database \"entando-demoServ\";" || true
	sudo -u $USER psql --cluster 8.4/$USER -d postgres -h localhost -p $POSTGRES_PORT -c "create database \"entando-demoServ\" WITH OWNER agile ENCODING 'UTF8';"
	sudo -u $USER psql --cluster 8.4/$USER -d postgres -h localhost -p $POSTGRES_PORT -c "drop database \"crm_demo_data\";" || true
	sudo -u $USER psql --cluster 8.4/$USER -d postgres -h localhost -p $POSTGRES_PORT -c "create database \"crm_demo_data\" WITH OWNER agile ENCODING 'UTF8';"
	sudo -u $USER psql --cluster 8.4/$USER -d postgres -h localhost -p $POSTGRES_PORT -c "drop database \"entandobi_quartz\";" || true
	sudo -u $USER psql --cluster 8.4/$USER -d postgres -h localhost -p $POSTGRES_PORT -c "create database \"entandobi_quartz\" WITH OWNER entandobiuser ENCODING 'UTF8';"
	sudo -u $USER psql --cluster 8.4/$USER -d postgres -h localhost -p $POSTGRES_PORT -c "drop database \"entandobi_repository\";" || true
	sudo -u $USER psql --cluster 8.4/$USER -d postgres -h localhost -p $POSTGRES_PORT -c "create database \"entandobi_repository\" WITH OWNER entandobiuser ENCODING 'UTF8';"
	echo "Restore DBs "
	sudo -u $USER pg_restore --cluster 8.4/$USER -d entando-demoPort -x -h localhost -p $POSTGRES_PORT -O $INSTALLER_PATH/DbBackup/Postgresql/entando-demoPort.backup >> /dev/null
	sudo -u $USER pg_restore --cluster 8.4/$USER -d entando-demoServ -x -h localhost -p $POSTGRES_PORT -O $INSTALLER_PATH/DbBackup/Postgresql/entando-demoServ.backup >> /dev/null
	sudo -u $USER pg_restore --cluster 8.4/$USER -d crm_demo_data -x -h localhost -p $POSTGRES_PORT -O $INSTALLER_PATH/DbBackup/Postgresql/crm_demo_data.backup >> /dev/null
	sudo -u $USER pg_restore --cluster 8.4/$USER -d entandobi_quartz -x -h localhost -p $POSTGRES_PORT -O $INSTALLER_PATH/DbBackup/Postgresql/entandobi_quartz.backup >> /dev/null
	sudo -u $USER pg_restore --cluster 8.4/$USER -d entandobi_repository -x -h localhost -p $POSTGRES_PORT -O $INSTALLER_PATH/DbBackup/Postgresql/entandobi_repository.backup >> /dev/null

# MYSQL DB
#mysql -u$MYSQL_USER -p$MYSQL_PWD -e "create user agile identified by 'agile';create schema crm;grant all on crm.* to 'agile'	;"
#mysql -u$MYSQL_USER -p$MYSQL_PWD crm < DbBackup/mysql/crm.sql
	echo "Done installing $USER"
}

function deleteEntando {
	echo "Delete entando install $USER"
	$($INSTALL_PATH/tomcat/bin/shutdown.sh)
	wait
	echo "Stopping postgresql cluster $USER"
	/usr/bin/pg_ctlcluster 8.4 $USER stop	|| true
	echo "Drop postgresql cluster $USER"
	pg_dropcluster --stop 8.4 $USER || echo -n ""
	echo "removing user $USER"
	userdel $USER -fr
	groupdel $USER 
	echo "Done delete"
}


##########################################################################################################

# The script should be run by root
if [ $(id -u) -ne 0 ]; then
	echo "You need root privileges to run this script"
	exit 1
fi


# Check that sh uses bash and not dash
ls -l /bin/sh | grep -q bash || {
	cd /bin
	ln -sf bash sh
	echo "sh is not configured to run with bash."
	echo "Fixed sh to use bash. Please run again."
	exit 1
}


####### MAIN CONTROL ###################
case "$1" in
	create)
		EXPECTED_ARGS=3
    if [ $# -lt $EXPECTED_ARGS ]
	    then
      echo "Usage: $(basename $0) $1 user pwd" >&2
      exit 1
    fi
		USER=$2
		PWD=$3
		INSTALL_PATH="$HOME/entando-$USER"
		installEntando $@
	;;
	delete)
		EXPECTED_ARGS=2
    if [ $# -lt $EXPECTED_ARGS ]
	    then
      echo "Usage: $(basename $0) $1 user" >&2
      exit 1
    fi
		USER=$2
		INSTALL_PATH="$HOME/entando-$USER"
		deleteEntando $@
	;;

esac
#########################################


