#!/bin/bash

yum_install rsync epel-release lsyncd

systemctl enable lsyncd
systemctl enable rsyncd

createdir $COM_DATA_CONF_DIR $COM_DATA_LOG_DIR $COM_DATA_DB_DIR

mkdir -p $COM_DATA_DB_DIR/src_local 
mkdir -p $COM_DATA_DB_DIR/to_local

mkdir -p $COM_DATA_DB_DIR/src
mkdir -p $COM_DATA_DB_DIR/to

_SOURCE_RSYNCD_FILE=/etc/rsyncd.conf
_SOURCE_LSYNCD_FILE=/etc/lsyncd.conf

_RSYNCD_FILE=${COM_DATA_CONF_DIR}rsyncd.conf
_LSYNCD_FILE=${COM_DATA_CONF_DIR}lsyncd.conf
_RSYNC_PASSWD_FILE=${COM_DATA_CONF_DIR}rsyncd.passwd
_RSYNC_CLIENT_PASSWD_FILE=${COM_DATA_CONF_DIR}rsyncd_cli.passwd
_RSYNC_EXCLUDE_FILE=${COM_DATA_CONF_DIR}rsyncd_cli.exclude

_CONFIG_RSYNCD_FILE=$COM_CONF_DIR"rsyncd.conf"
_CONFIG_LSYNCD_FILE=$COM_CONF_DIR"lsyncd.conf"


cat > $_RSYNC_EXCLUDE_FILE <<EOT
.svn
.git
.project
.settings
EOT

echo "rsync:123456" >$_RSYNC_PASSWD_FILE
echo "123456" >$_RSYNC_CLIENT_PASSWD_FILE
chmod 600 $_RSYNC_PASSWD_FILE
chmod 600 $_RSYNC_CLIENT_PASSWD_FILE

touch $_RSYNC_EXCLUDE_FILE

if [ ! -f "${_SOURCE_RSYNCD_FILE}" ];then
	\cp -f $_CONFIG_RSYNCD_FILE $_SOURCE_RSYNCD_FILE
fi

grep "^#add by zeroai-utils$" $_SOURCE_RSYNCD_FILE
if [ $? != 0 ]; then
	cat $_CONFIG_RSYNCD_FILE > $_SOURCE_RSYNCD_FILE
	com_replace $_SOURCE_RSYNCD_FILE
fi

echo $_SOURCE_RSYNCD_FILE
if [ ! -f "${_SOURCE_LSYNCD_FILE}" ];then
	\cp -f $_CONFIG_LSYNCD_FILE $_SOURCE_LSYNCD_FILE
fi

grep "^#add by zeroai-utils$" $_SOURCE_LSYNCD_FILE >/dev/null
if [ $? != 0 ]; then
	cat $_CONFIG_LSYNCD_FILE > $_SOURCE_LSYNCD_FILE
	com_replace $_SOURCE_LSYNCD_FILE
fi

ln -sf $_SOURCE_LSYNCD_FILE $_LSYNCD_FILE
ln -sf $_SOURCE_RSYNCD_FILE $_RSYNCD_FILE


systemctl stop rsyncd
systemctl start rsyncd
systemctl stop lsyncd
systemctl start lsyncd

