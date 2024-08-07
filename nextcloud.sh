#!/bin/sh
# Instructions on how to use this script:
# chmod +x SCRIPTNAME.sh
# sudo ./SCRIPTNAME.sh
#
# SCRIPT: nextcloud.sh
# AUTHOR: ALBERT VALBUENA
# DATE: 12-09-2020
# SET FOR: Production
# (For Alpha, Beta, Dev, Test and Production)
#
# PLATFORM: FreeBSD 12/13
#
# PURPOSE: This script installs NextCloud assuming a FAMP stack is already installed.
#
# REV LIST:
# DATE: 03-08-2022
# BY: ALBERT VALBUENA
# MODIFICATION: 03-08-2022
#
#
# set -n # Uncomment to check your syntax, without execution.
# # NOTE: Do not forget to put the comment back in or
# # the shell script will not execute!

##########################################################
################ BEGINNING OF MAIN #######################
##########################################################

# This script will install a Nextcloud instance on a FreeBSD box.

################################# WARNING!! ########################################
# This script must be used after having installed Nextcloud dependencies.
# The base ones will be met by installing a FAMP stack server.
# You may use one of the following three scripts for this: 
#
#
# Apache Pre-fork MPM 
# https://github.com/Adminbyaccident/FAMP/blob/master/stdard-famp.sh
#
# Apache Event MPM + PHP-FPM on TCP socket
# https://github.com/Adminbyaccident/FAMP/blob/master/event-php-fpm-tcp-socket.sh
#
# Apache Event MPM + PHP-FPM on UNIX socket
# https://github.com/Adminbyaccident/FAMP/blob/master/event-php-fpm-unix-socket.sh
#
#
# Once the base system, a FAMP stack, has been installed one may use the following 
# security script to enhance the overall security:
#
# https://github.com/Adminbyaccident/FAMP/blob/master/apache-hardening.sh
#
# 
# Apache's HTTP configuration with the Event MPM is more performant than the pre-fork one.
# The DB performance can be improved, which is very useful when file count increases 
# by using Redis or similar cache programs.
#
# Remember to adapt this script to your needs wether you are using a domain or 
# an ip to access your Nextcloud instance.
####################################################################################

# Update packages sources on the system first
pkg upgrade -y

# Install dependencies you may not have
pkg install -y bash pwgen expect

# Configure PHP (already installed by the previous FAMP script) to use 512M instead of the default 128M
sed -i -e '/memory_limit/s/128M/1G/' /usr/local/etc/php.ini

# Configuring Uploads
sed -i -e 's/upload_max_filesize = 2M/upload_max_filesize = 40G/g' /usr/local/etc/php.ini
sed -i -e 's/post_max_size = 2M/post_max_size = 40G/g' /usr/local/etc/php.ini

# Other PHP fine adjusts
sed -i -e 's/;upload_tmp_dir =/upload_tmp_dir = "/temp"' /usr/local/etc/php.ini
sed -i -e 's/max_input_time = 60/max_input_time = 3600/g' /usr/local/etc/php.ini
sed -i -e 's/max_execution_time = 60/max_execution_time = 3600/g' /usr/local/etc/php.ini

# Install specific PHP dependencies for Nextcloud
pkg install -y php83-zip php83-mbstring php83-gd php83-zlib php83-curl php83-pdo_mysql php83-pecl-imagick php83-intl php83-bcmath php83-gmp php83-fileinfo php83-sysvsem php83-exif php83-sodium php83-bz2

# Install Nextcloud
# Fetch Nextcloud
fetch -o /usr/local/www https://download.nextcloud.com/server/releases/nextcloud-29.0.4.zip

# Unzip Nextcloud
unzip -d /usr/local/www/ /usr/local/www/nextcloud-29.0.4.zip

# Change the ownership so the Apache user (www) owns it
chown -R www:www /usr/local/www/nextcloud

# Make a backup copy of the currently working httpd.conf file
cp /usr/local/etc/apache24/httpd.conf /usr/local/etc/apache24/httpd.conf.backup

# Add the configuration needed for Apache to serve Nextcloud
echo "
Alias /nextcloud /usr/local/www/nextcloud
AcceptPathInfo On
<Directory /usr/local/www/nextcloud>
    AllowOverride All
    Require all granted
</Directory>" >> /usr/local/etc/apache24/httpd.conf

# Enable VirtualHost
sed -i -e '/httpd-vhosts.conf/s/#Include/Include/' /usr/local/etc/apache24/httpd.conf

# Make a backup of the current httpd-vhosts (virtual host) configuration file
cp /usr/local/etc/apache24/extra/httpd-vhosts.conf /usr/local/etc/apache24/extra/httpd-vhosts.conf.bckp

# Remove the original virtual host file (we've made a backup to restore from, don't panic)
rm /usr/local/etc/apache24/extra/httpd-vhosts.conf

# Create a new empty virtual host file:

# Set a VirtualHost configuration for Nextcloud

echo "
# Virtual Hosts
#
# Required modules: mod_log_config
# If you want to maintain multiple domains/hostnames on your
# machine you can setup VirtualHost containers for them. Most configurations
# use only name-based virtual hosts so the server doesn't need to worry about
# IP addresses. This is indicated by the asterisks in the directives below.
#
# Please see the documentation at
# <URL:http://httpd.apache.org/docs/2.4/vhosts/>
# for further details before you try to setup virtual hosts.
#
# You may use the command line option '-S' to verify your virtual host
# configuration.
#
# VirtualHost example:
# Almost any Apache directive may go into a VirtualHost container.
# The first VirtualHost section is used for all requests that do not
# match a ServerName or ServerAlias in any <VirtualHost> block.
#
<VirtualHost *:80>
    ServerName Nextcloud
    ServerAlias Nextcloud
    DocumentRoot "/usr/local/www/nextcloud"
    ErrorLog "/var/log/nextcloud-error_log"
    CustomLog "/var/log/nextcloud-access_log" common
    RewriteEngine On
    RewriteCond %{HTTPS}  !=on
    RewriteRule ^/?(.*) https://%{SERVER_NAME}/$1 [R,L]
    Protocols h2 h2c http/1.1
</VirtualHost>
<VirtualHost *:443>
    ServerName Nextcloud
    ServerAlias Nextcloud
    DocumentRoot "/usr/local/www/nextcloud"
    SSLEngine on
    SSLProtocol all -SSLv2 -SSLv3 -TLSv1 -TLSv1.1 -TLSv1.2
    SSLHonorCipherOrder on
    SSLCipherSuite  ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
    Include /usr/local/etc/apache24/Includes/headers.conf
	SSLCertificateFile "/usr/local/etc/apache24/server.crt"
    SSLCertificateKeyFile "/usr/local/etc/apache24/server.key"
    ErrorLog "/var/log/nextcloud-error_log"
    CustomLog "/var/log/nextcloud-access_log" common
    Protocols h2 http/1.1
</VirtualHost>" >> /usr/local/etc/apache24/extra/httpd-vhosts.conf

# Restart Apache service
service apache24 restart

# Create the database for Nextcloud and user. Mind this is MySQL version 8

NEW_DB_NAME=$(pwgen 8 --secure --numerals --capitalize) && export NEW_DB_NAME && echo $NEW_DB_NAME >> /root/new_db_name.txt

NEW_DB_USER_NAME=$(pwgen 10 --secure --numerals --capitalize) && export NEW_DB_USER_NAME && echo $NEW_DB_USER_NAME >> /root/new_db_user_name.txt

NEW_DB_PASSWORD=$(pwgen 32 --secure --numerals --capitalize) && export NEW_DB_PASSWORD && echo $NEW_DB_PASSWORD >> /root/newdb_pwd.txt

DB_ROOT_PASSWORD=$(cat /root/db_root_pwd.txt) && export DB_ROOT_PASSWORD

NEW_DATABASE=$(expect -c "
set timeout 10
spawn mysql -u root -p
expect \"Enter password:\"
send \"$DB_ROOT_PASSWORD\r\"
expect \"root@localhost \[(none)\]>\"
send \"CREATE DATABASE $NEW_DB_NAME;\r\"
expect \"root@localhost \[(none)\]>\"
send \"CREATE USER '$NEW_DB_USER_NAME'@'localhost' IDENTIFIED WITH mysql_native_password BY '$NEW_DB_PASSWORD';\r\"
expect \"root@localhost \[(none)\]>\"
send \"GRANT ALL PRIVILEGES ON $NEW_DB_NAME.* TO '$NEW_DB_USER_NAME'@'localhost';\r\"
expect \"root@localhost \[(none)\]>\"
send \"FLUSH PRIVILEGES;\r\"
expect \"root@localhost \[(none)\]>\"
send \"exit\r\"
expect eof
")

echo "$NEW_DATABASE"

# Now Visit your server ip and finish the GUI install. 
# Be aware of the default SQLite DB install. Select the MySQL option!!
# https://yourserverip/nextcloud

# Automatic NextCloud install using MySQL instead of the default SQLite

NEXTCLOUD_USER=$(pwgen 10 --secure --numerals --capitalize) && export NEXTCLOUD_USER && echo $NEXTCLOUD_USER >> /root/nextcloud_user.txt

NEXTCLOUD_PWD=$(pwgen 32 --secure --numerals --capitalize) && export NEXTCLOUD_PWD && echo $NEXTCLOUD_PWD >> /root/nextcloud_pwd.txt

su -m www -c 'php /usr/local/www/nextcloud/occ maintenance:install --database "mysql" --database-name "$NEW_DB_NAME" --database-user "$NEW_DB_USER_NAME" --database-pass "$NEW_DB_PASSWORD" --admin-user "$NEXTCLOUD_USER" --admin-pass "$NEXTCLOUD_PWD"'

# Add your ip or domain name as a trusted domain for Nextcloud. Remember to adapt this to your needs. Otherwise a warning message will appear in your screen.
# This setup doesn't use a domain name, it's ready to be used with an IP. Adjust the NIC name with 'em0' or similar here if it's convenient.

TRUSTED_DOMAIN=$(ifconfig | grep "inet " | awk '{ print $2; exit }') && export TRUSTED_DOMAIN && echo $TRUSTED_DOMAIN >> /root/trusted_domain.txt

su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set trusted_domains 1 --value="$TRUSTED_DOMAIN"'

# No one but root can read these files. Read only permissions.
chmod 400 /root/db_root_pwd.txt
chmod 400 /root/new_db_name.txt
chmod 400 /root/new_db_user_name.txt
chmod 400 /root/newdb_pwd.txt
chmod 400 /root/nextcloud_user.txt
chmod 400 /root/nextcloud_pwd.txt
chmod 400 /root/trusted_domain.txt

# Display the new database, username and password generated on MySQL
echo "Display DB name, username and password location"
echo "Your NEW_DB_NAME is written on this file /root/new_db_name.txt"
echo "Your NEW_DB_USER_NAME is written on this file /root/new_db_user_name.txt"
echo "Your NEW_DB_PASSWORD is written on this file /root/newdb_pwd.txt"

# Display the automatically generated username and password for Nextcloud
echo "Your Nextcloud username is written on this file /root/nextcloud_user.txt"
echo "Your Nextcloud password is written on this file /root/nextcloud_pwd.txt"

## References:
## https://docs.nextcloud.com/server/stable/admin_manual/installation/source_installation.html
## https://www.adminbyaccident.com/freebsd/how-to-freebsd/how-to-install-nextcloud-on-freebsd-12/
