echo "##########################################################
####################### FAMP #############################
##########################################################"

sed -ip 's/quarterly/latest/g' /etc/pkg/FreeBSD.conf

# Update packages list
pkg update

# Update actually installed packages
pkg upgrade -y

# Install Apache
echo "####################### APACHE #######################"
pkg install -y apache24

# Add service to be fired up at boot time
sysrc apache24_enable="YES"

# Install MySQL
echo "####################### MYSQL #######################"
pkg install -y mysql80-server

# Add service to be fired up at boot time
sysrc mysql_enable="YES"

# Install PHP 8.2 and its 'funny' dependencies
echo "####################### PHP 8.3 #######################"
pkg install -y php83 php83-mysqli mod_php83 php83-extensions

# Install the 'old fashioned' Expect to automate the mysql_secure_installation part
pkg install -y expect

# Create configuration file for Apache HTTP to 'speak' PHP
touch /usr/local/etc/apache24/modules.d/001_mod-php.conf

# Add the configuration into the file
echo "
<IfModule dir_module>
   DirectoryIndex index.php index.html
   <FilesMatch \"\.php$\"> 
        SetHandler application/x-httpd-php
    </FilesMatch>
    <FilesMatch \"\.phps$\">
        SetHandler application/x-httpd-php-source
    </FilesMatch>
</IfModule>" >> /usr/local/etc/apache24/modules.d/001_mod-php.conf

sed -i -e 's/##ServerName www.example.com:80/ServerName drive.infogr.com.br/g' /usr/local/etc/apache24/httpd.conf

# Set the PHP's default configuration
cp /usr/local/etc/php.ini-production /usr/local/etc/php.ini

# Fire up the services
echo "####################### APACHE PHP START #######################"
service apache24 start
service mysql-server start

# Configure MySQL with the mysql_secure_installation script.
pkg install -y pwgen

DB_ROOT_PASSWORD=$(pwgen 32 --secure --numerals --capitalize) && export DB_ROOT_PASSWORD && echo $DB_ROOT_PASSWORD >> /root/db_root_pwd.txt

echo "####################### MYSQL USER #######################"
SECURE_MYSQL=$(expect -c "
set timeout 10
set DB_ROOT_PASSWORD "$DB_ROOT_PASSWORD"
spawn mysql_secure_installation
expect \"Press y|Y for Yes, any other key for No:\"
send \"y\r\"
expect \"Please enter 0 = LOW, 1 = MEDIUM and 2 = STRONG:\"
send \"0\r\"
expect \"New password:\"
send \"$DB_ROOT_PASSWORD\r\"
expect \"Re-enter new password:\"
send \"$DB_ROOT_PASSWORD\r\"
expect \"Do you wish to continue with the password provided?(Press y|Y for Yes, any other key for No) :\"
send \"Y\r\"
expect \"Remove anonymous users?\"
send \"y\r\"
expect \"Disallow root login remotely?\"
send \"y\r\"
expect \"Remove test database and access to it?\"
send \"y\r\"
expect \"Reload privilege tables now?\"
send \"y\r\"
expect eof
")

echo "$SECURE_MYSQL"

# Display the location of the generated root password for MySQL
echo "Your DB_ROOT_PASSWORD is written on this file /root/db_root_pwd.txt"

# No one but root can read this file. Read only permission.
chmod 400 /root/db_root_pwd.txt

echo "####################### APACHE SECURITY #######################"
# 1.- Removing the OS type and modifying version banner 
echo 'ServerTokens Prod' >> /usr/local/etc/apache24/httpd.conf
echo 'ServerSignature Off' >> /usr/local/etc/apache24/httpd.conf

# 2.- Avoid PHP's information (version, etc) being disclosed
sed -i -e '/expose_php/s/expose_php = On/expose_php = Off/' /usr/local/etc/php.ini

# 3.- Fine tunning access to the DocumentRoot directory structure
sed -i '' -e 's/Options Indexes FollowSymLinks/Options -Indexes +FollowSymLinks -Includes/' /usr/local/etc/apache24/httpd.conf

echo "####################### APACHE TLS #######################"
# 4.- Enabling TLS connections with a self signed certificate. 
# 4.1- Key and certificate generation
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /usr/local/etc/apache24/server.key -out /usr/local/etc/apache24/server.crt -subj "/C=BR/ST=MG/L=Conceicao/O=GRInfo/CN=infogr.com.br/emailAddress=contato@gilvandev.com"

# Because we have generated a certificate + key we will enable SSL/TLS in the server.
# 4.3- Enabling TLS connections in the server.
sed -i -e '/mod_ssl.so/s/#LoadModule/LoadModule/' /usr/local/etc/apache24/httpd.conf

# 4.4- Enable the server's default TLS configuration to be applied.
sed -i -e '/httpd-ssl.conf/s/#Include/Include/' /usr/local/etc/apache24/httpd.conf

# 4.5- Enable TLS session cache.
sed -i -e '/mod_socache_shmcb.so/s/#LoadModule/LoadModule/' /usr/local/etc/apache24/httpd.conf

# 4.6- Redirect HTTP connections to HTTPS (port 80 and 443 respectively)
# 4.6.1- Enabling the rewrite module
sed -i -e '/mod_rewrite.so/s/#LoadModule/LoadModule/' /usr/local/etc/apache24/httpd.conf

# 4.6.2- Adding the redirection rules from HTTP to HTTPS.
echo 'RewriteEngine On' >> /usr/local/etc/apache24/httpd.conf
echo 'RewriteCond %{HTTPS}  !=on' >> /usr/local/etc/apache24/httpd.conf
echo 'RewriteRule ^/?(.*) https://%{SERVER_NAME}/$1 [R,L]' >> /usr/local/etc/apache24/httpd.conf

echo "####################### APACHE HEADERS #######################"
# 5.- Secure headers
echo "
<IfModule mod_headers.c>
        # Add security and privacy related headers
        Header set Content-Security-Policy \"upgrade-insecure-requests;\"
        Header always edit Set-Cookie (.*) \"\$1; HttpOnly; Secure\"
        Header set Strict-Transport-Security \"max-age=31536000; includeSubDomains\"
        Header set X-Content-Type-Options \"nosniff\"
        Header set X-XSS-Protection \"1; mode=block\"
        Header set X-Robots-Tag \"all\"
        Header set X-Download-Options \"noopen\"
        Header set X-Permitted-Cross-Domain-Policies \"none\"
        Header always set Referrer-Policy: \"strict-origin\"
        Header set X-Frame-Options: \"deny\"
        Header set Permissions-Policy: \"accelerometer=(none); ambient-light-sensor=(none); autoplay=(none); battery=(none); display-capture=(none); document-domain=(none); encrypted-media=(self); execution-while-not-rendered=(none); execution-while-out-of-viewport=(none); geolocation=(none); gyroscope=(none); layout-animations=(none); legacy-image-formats=(self); magnometer=(none); midi=(none); camera=(none); notifications=(none); microphone=(none); speaker=(none); oversized-images=(self); payment=(none); picture-in-picture=(none); publickey-credentials-get=(none); sync-xhr=(none); usb=(none); vr=(none); wake-lock=(none); screen-wake-lock=(none); web-share=(none); xr-partial-tracking=(none)\"
        SetEnv modHeadersAvailable true
</IfModule>" >>  /usr/local/etc/apache24/Includes/headers.conf

echo " 
Include /usr/local/etc/apache24/Includes/headers.conf
" >> /usr/local/etc/apache24/httpd.conf

# 6.- Disable the TRACE method.
echo 'TraceEnable off' >> /usr/local/etc/apache24/httpd.conf

# 7.- Allow specific HTTP methods.
sed -i '' -e '272i\
<LimitExcept GET POST HEAD>' /usr/local/etc/apache24/httpd.conf
sed -i '' -e '273i\
deny from all' /usr/local/etc/apache24/httpd.conf
sed -i '' -e '274i\
</LimitExcept>' /usr/local/etc/apache24/httpd.conf

# Restart Apache HTTP so changes take effect.
service apache24 restart

# 8.- Install mod_evasive
pkg install -y ap24-mod_evasive

# 8.1- Enable the mod_evasive module in Apache HTTP
sed -i -e '/mod_evasive20.so/s/#LoadModule/LoadModule/' /usr/local/etc/apache24/httpd.conf

# 8.2- Configure the mod_evasive module
touch /usr/local/etc/apache24/modules.d/020-mod_evasive.conf

echo "<IfModule mod_evasive20.c>
	DOSHashTableSize 3097
	DOSPageCount 20
	DOSSiteCount 50
	DOSPageInterval 1
	DOSSiteInterval 1
	DOSBlockingPeriod 360
	DOSEmailNotify contato@gilvandev.com.br
	DOSSystemCommand \"su – root -c /sbin/ipfw add 50000 deny %s to any in\"
	DOSLogDir \"/var/log/mod_evasive\"
</IfModule>" >> /usr/local/etc/apache24/modules.d/020-mod_evasive.conf

# 8.4- Restart Apache for the configuration to take effect
apachectl graceful

# 9.- WAF-like rules enablement for any generic FAMP stack. Applicable to WPress, Drupal, Joomla, Nextcloud and the likes of those.
# Create an empty httpd-security.conf file
touch /usr/local/etc/apache24/extra/httpd-security.conf

# 9.1- Enabling the rewrite module
sed -i -e '/mod_rewrite.so/s/#LoadModule/LoadModule/' /usr/local/etc/apache24/httpd.conf

echo "
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteCond %{HTTP_USER_AGENT} (havij|libwww-perl|wget|python|nikto|curl|scan|java|winhttp|clshttp|loader) [NC,OR]
RewriteCond %{HTTP_USER_AGENT} (%0A|%0D|%27|%3C|%3E|%00) [NC,OR]
RewriteCond %{HTTP_USER_AGENT} (;|<|>|'|\"|\)|\(|%0A|%0D|%22|%27|%28|%3C|%3E|%00).*(libwww-perl|wget|python|nikto|curl|scan|java|winhttp|HTTrack|clshttp|archiver|loader|email|harvest|extract|grab|miner|fetch) [NC,OR]
RewriteCond %{THE_REQUEST} (\?|\*|%2a)+(%20+|\\\s+|%20+\\\s+|\\\s+%20+|\\\s+%20+\\\s+)(http|https)(:/|/) [NC,OR]
RewriteCond %{THE_REQUEST} etc/passwd [NC,OR]
RewriteCond %{THE_REQUEST} cgi-bin [NC,OR]
RewriteCond %{THE_REQUEST} (%0A|%0D|\\r|\\n) [NC,OR]
RewriteCond %{REQUEST_URI} owssvr\.dll [NC,OR]
RewriteCond %{HTTP_REFERER} (%0A|%0D|%27|%3C|%3E|%00) [NC,OR]
RewriteCond %{HTTP_REFERER} \.opendirviewer\. [NC,OR]
RewriteCond %{HTTP_REFERER} users\.skynet\.be.* [NC,OR]
RewriteCond %{QUERY_STRING} [a-zA-Z0-9_]=(http|https):// [NC,OR]
RewriteCond %{QUERY_STRING} [a-zA-Z0-9_]=(\.\.//?)+ [NC,OR]
RewriteCond %{QUERY_STRING} [a-zA-Z0-9_]=/([a-z0-9_.]//?)+ [NC,OR]
RewriteCond %{QUERY_STRING} \=PHP[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12} [NC,OR]
RewriteCond %{QUERY_STRING} (\.\./|%2e%2e%2f|%2e%2e/|\.\.%2f|%2e\.%2f|%2e\./|\.%2e%2f|\.%2e/) [NC,OR]
RewriteCond %{QUERY_STRING} ftp\: [NC,OR]
RewriteCond %{QUERY_STRING} (http|https)\: [NC,OR]
RewriteCond %{QUERY_STRING} \=\|w\| [NC,OR]
RewriteCond %{QUERY_STRING} ^(.*)/self/(.*)$ [NC,OR]
RewriteCond %{QUERY_STRING} ^(.*)cPath=(http|https)://(.*)$ [NC,OR]
RewriteCond %{QUERY_STRING} (\<|%3C).*script.*(\>|%3E) [NC,OR]
RewriteCond %{QUERY_STRING} (<|%3C)([^s]*s)+cript.*(>|%3E) [NC,OR]
RewriteCond %{QUERY_STRING} (\<|%3C).*embed.*(\>|%3E) [NC,OR]
RewriteCond %{QUERY_STRING} (<|%3C)([^e]*e)+mbed.*(>|%3E) [NC,OR]
RewriteCond %{QUERY_STRING} (\<|%3C).*object.*(\>|%3E) [NC,OR]
RewriteCond %{QUERY_STRING} (<|%3C)([^o]*o)+bject.*(>|%3E) [NC,OR]
RewriteCond %{QUERY_STRING} (\<|%3C).*iframe.*(\>|%3E) [NC,OR]
RewriteCond %{QUERY_STRING} (<|%3C)([^i]*i)+frame.*(>|%3E) [NC,OR]
RewriteCond %{QUERY_STRING} base64_encode.*\(.*\) [NC,OR]
RewriteCond %{QUERY_STRING} base64_(en|de)code[^(]*\([^)]*\) [NC,OR]
RewriteCond %{QUERY_STRING} GLOBALS(=|\[|\%[0-9A-Z]{0,2}) [OR]
RewriteCond %{QUERY_STRING} _REQUEST(=|\[|\%[0-9A-Z]{0,2}) [OR]
RewriteCond %{QUERY_STRING} ^.*(\(|\)|<|>|%3c|%3e).* [NC,OR]
RewriteCond %{QUERY_STRING} ^.*(\x00|\x04|\x08|\x0d|\x1b|\x20|\x3c|\x3e|\x7f).* [NC,OR]
RewriteCond %{QUERY_STRING} (NULL|OUTFILE|LOAD_FILE) [OR]
RewriteCond %{QUERY_STRING} (\.{1,}/)+(motd|etc|bin) [NC,OR]
RewriteCond %{QUERY_STRING} (localhost|loopback|127\.0\.0\.1) [NC,OR]
RewriteCond %{QUERY_STRING} (<|>|''|%0A|%0D|%27|%3C|%3E|%00) [NC,OR]
RewriteCond %{QUERY_STRING} concat[^\(]*\( [NC,OR]
RewriteCond %{QUERY_STRING} union([^s]*s)+elect [NC,OR]
RewriteCond %{QUERY_STRING} union([^a]*a)+ll([^s]*s)+elect [NC,OR]
RewriteCond %{QUERY_STRING} \-[sdcr].*(allow_url_include|allow_url_fopen|safe_mode|disable_functions|auto_prepend_file) [NC,OR]
RewriteCond %{QUERY_STRING} (;|<|>|'|\"|\)|%0A|%0D|%22|%27|%3C|%3E|%00).*(/\*|union|select|insert|drop|delete|update|cast|create|char|convert|alter|declare|order|script|set|md5|benchmark|encode) [NC,OR]
# Condition to block Proxy/LoadBalancer/WAF bypass
RewriteCond %{HTTP:X-Client-IP} (localhost|loopback|127\.0\.0\.1) [NC,OR]
RewriteCond %{HTTP:X-Forwarded-For} (localhost|loopback|127\.0\.0\.1) [NC,OR]
RewriteCond %{HTTP:X-Forwarded-Scheme} (localhost|loopback|127\.0\.0\.1) [NC,OR]
RewriteCond %{HTTP:X-Real-IP} (localhost|loopback|127\.0\.0\.1) [NC,OR]
RewriteCond %{HTTP:X-Forwarded-By} (localhost|loopback|127\.0\.0\.1) [NC,OR]
RewriteCond %{HTTP:X-Originating-IP} (localhost|loopback|127\.0\.0\.1) [NC,OR]
RewriteCond %{HTTP:X-Forwarded-From} (localhost|loopback|127\.0\.0\.1) [NC,OR]
RewriteCond %{HTTP:X-Forwarded-Host} (localhost|loopback|127\.0\.0\.1) [NC,OR]
RewriteCond %{HTTP:X-Remote-Addr} (localhost|loopback|127\.0\.0\.1) [NC,OR]
RewriteCond %{QUERY_STRING} (sp_executesql) [NC]
RewriteRule ^(.*)$ - [F]
</IfModule>
" >> /usr/local/etc/apache24/extra/httpd-security.conf

echo "
Include /usr/local/etc/apache24/extra/httpd-security.conf
" >> /usr/local/etc/apache24/httpd.conf

# Restart Apache HTTP to load the WAF-like configuration.
service apache24 restart

# Install ModSecurity
echo "####################### APACHE MOD_SECURITY #######################"
pkg install -y ap24-mod_security

# Install CRS ruleset for ModSecurity
pkg install wget 
wget -O /usr/local/etc/modsecurity/crs-ruleset-3.3.7.zip https://github.com/coreruleset/coreruleset/archive/refs/tags/v3.3.7.zip
pkg install -y unzip
unzip /usr/local/etc/modsecurity/crs-ruleset-3.3.7.zip -d /usr/local/etc/modsecurity/
cp /usr/local/etc/modsecurity/coreruleset-3.3.7/crs-setup.conf.example /usr/local/etc/modsecurity/coreruleset-3.3.7/crs-setup.conf
cp /usr/local/etc/modsecurity/coreruleset-3.3.7/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf.example /usr/local/etc/modsecurity/coreruleset-3.3.7/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf
cp /usr/local/etc/modsecurity/coreruleset-3.3.7/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf.example /usr/local/etc/modsecurity/coreruleset-3.3.7/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf
echo '
LoadModule security2_module libexec/apache24/mod_security2.so
Include /usr/local/etc/modsecurity/*.conf
Include /usr/local/etc/modsecurity/coreruleset-3.3.7/crs-setup.conf
Include /usr/local/etc/modsecurity/coreruleset-3.3.7/rules/*.conf
' >> /usr/local/etc/apache24/modules.d/280_mod_security.conf
sed -i -e '/mod_unique_id.so/s/#LoadModule/LoadModule/g' /usr/local/etc/apache24/httpd.conf
sed -i -e 'SecRuleEngine DetectionOnly/s/SecRuleEngine DetectionOnly/SecRuleEngine On/g' /usr/local/etc/modsecurity/modsecurity.conf

service apache24 restart

echo "####################### NEXTCLOUD #######################"

# Install dependencies you may not have
pkg install -y bash pwgen expect

# Configure PHP (already installed by the previous FAMP script) to use 512M instead of the default 128M
sed -i -e '/memory_limit/s/128M/1G/' /usr/local/etc/php.ini

# Configuring Uploads
sed -i -e 's/upload_max_filesize = 2M/upload_max_filesize = 40G/g' /usr/local/etc/php.ini
sed -i -e 's/post_max_size = 8M/post_max_size = 40G/g' /usr/local/etc/php.ini

# Other PHP fine adjusts
sed -i -e 's/;upload_tmp_dir =/upload_tmp_dir = "/temp"' /usr/local/etc/php.ini
sed -i -e 's/max_input_time = 60/max_input_time = 3600/g' /usr/local/etc/php.ini
sed -i -e 's/max_execution_time = 60/max_execution_time = 3600/g' /usr/local/etc/php.ini
sed -i -e 's/max_input_vars = 1000/max_input_vars = 10000/g' /usr/local/etc/php.ini

# Install specific PHP dependencies for Nextcloud
echo "####################### PHP DEPENDENCIES #######################"
pkg install -y php83-zip php83-mbstring php83-gd php83-zlib php83-curl php83-pdo_mysql php83-pecl-imagick php83-intl php83-bcmath php83-gmp php83-fileinfo php83-sysvsem php83-exif php83-sodium php83-bz2

# Configure OPCache for PHP
sed -i -e '/opcache.enable/s/;opcache.enable=1/opcache.enable=1/' /usr/local/etc/php.ini
sed -i -e '/opcache.memory_consumption/s/;opcache.memory_consumption=128/opcache.memory_consumption=256/' /usr/local/etc/php.ini
sed -i -e '/opcache.interned_strings_buffer/s/;opcache.interned_strings_buffer=8/opcache.interned_strings_buffer=12/' /usr/local/etc/php.ini
sed -i -e '/opcache.max_accelerated_files/s/;opcache.max_accelerated_files=4000/opcache.max_accelerated_files=8000/' /usr/local/etc/php.ini
sed -i -e '/opcache.revalidate_freq/s/;opcache.revalidate_freq=60/opcache.revalidate_freq=60/' /usr/local/etc/php.ini
sed -i -e '/opcache.fast_shutdown/s/;opcache.fast_shutdown=1/opcache.fast_shutdown=1/' /usr/local/etc/php.ini
sed -i -e '/opcache.enable_cli/s/;opcache.enable_cli=1/opcache.enable_cli=1/' /usr/local/etc/php.ini

# Install Nextcloud
# Fetch Nextcloud
fetch -o /usr/local/www https://download.nextcloud.com/server/releases/nextcloud-30.0.4.zip

# Unzip Nextcloud
unzip -d /usr/local/www/ /usr/local/www/nextcloud-30.0.4.zip

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
echo "####################### VHOST #######################"
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
    <Directory "/usr/local/www/nextcloud">
    	LimitRequestBody 0
    </Directory>
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
    <Directory "/usr/local/www/nextcloud">
    	LimitRequestBody 0
    </Directory>
</VirtualHost>" >> /usr/local/etc/apache24/extra/httpd-vhosts.conf

# Restart Apache service
service apache24 restart

# Create the database for Nextcloud and user. Mind this is MySQL version 8

NEW_DB_NAME=$(pwgen 8 --secure --numerals --capitalize) && export NEW_DB_NAME && echo $NEW_DB_NAME >> /root/new_db_name.txt

NEW_DB_USER_NAME=$(pwgen 10 --secure --numerals --capitalize) && export NEW_DB_USER_NAME && echo $NEW_DB_USER_NAME >> /root/new_db_user_name.txt

NEW_DB_PASSWORD=$(pwgen 32 --secure --numerals --capitalize) && export NEW_DB_PASSWORD && echo $NEW_DB_PASSWORD >> /root/newdb_pwd.txt

DB_ROOT_PASSWORD=$(cat /root/db_root_pwd.txt) && export DB_ROOT_PASSWORD

echo "####################### NEXTCLOUD DATABASE #######################"
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

TRUSTED_DOMAIN=$(ifconfig | grep "vnet0 " | awk '{ print $2; exit }') && export TRUSTED_DOMAIN && echo $TRUSTED_DOMAIN >> /root/trusted_domain.txt

su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set trusted_domains 1 --value="$TRUSTED_DOMAIN"'
su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set trusted_domains 2 --value="cloud.postosnetinho.com.br"'
su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set htaccess.RewriteBase --value="/"'
su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set logtimezone --value="America/Sao_Paulo"'
su -m www -c 'php /usr/local/www/nextcloud/occ maintenance:update:htaccess'


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
