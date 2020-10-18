#!/bin/bash

# Insert variables
echo "Instance URL:"
read url
if [ url == "" ]; then
    echo "URL is empty. Script aborted."
    exit 1
fi
echo "Instance name:"
read short
if [ short == "" ]; then
    echo "Short name is empty. Script aborted."
    exit 1
fi

echo "Admin email:"
read email
if [ email == "" ]; then
    echo "Admin e-mail is empty. Script aborted."
    exit 1
fi

echo "Nextcloud admin user:"
read user
if [ user == "" ]; then
    echo "Nextcloud admin user is empty. Script aborted."
    exit 1
fi

# Updates
sudo apt-get -y update
sudo apt-get -y dist-upgrade

# Install Zip & Wget
sudo apt-get -y install zip unzip wget

# MariaDB & Apache & Certbot & PHP
sudo apt-get install -y mariadb-server mariadb-client apache2 apache2-doc apache2-utils python3-certbot-apache libapache2-mod-php7.4 php7.4 php7.4-bcmath php7.4-curl php7.4-fpm php7.4-gd php7.4-gmp php7.4-imagick php7.4-intl php7.4-mbstring php7.4-mysql php7.4-opcache php7.4-xml php7.4-xmlrpc php7.4-zip php-apcu
sudo a2enmod headers rewrite ssl

# Nextcloud: Download
sudo wget -P /tmp/ https://download.nextcloud.com/server/releases/latest.zip
sudo unzip /tmp/latest.zip -d /tmp/
sudo mkdir /var/www/${short}
sudo rsync -a --info=progress2 /tmp/nextcloud/. /var/www/${short}/
sudo rm -r /tmp/nextcloud/
sudo rm -r /tmp/latest.zip
sudo chown -R www-data:www-data /var/www/${short}/

# Apache: Configuration
sudo cat > /etc/apache2/sites-available/${url}.conf << EOF
<VirtualHost *:80>
	ServerName ${url}
	ServerAdmin ${email}
	Redirect 301 / https://${url}/
</VirtualHost>

<VirtualHost *:443>
	Servername ${url}
	ServerAdmin ${email}

	DocumentRoot /var/www/${short}
	<Directory /var/www/${short}>
		Options Indexes FollowSymLinks
		AllowOverride All
		Require all granted
	</Directory>

	ErrorLog ${APACHE_LOG_DIR}/error.${url}.log
	CustomLog ${APACHE_LOG_DIR}/access.${url}.log combined
	
	#SSLEngine on
	#SSLCertificateFile /etc/letsencrypt/live/${url}/fullchain.pem
	#SSLCertificateKeyFile /etc/letsencrypt/live/${url}/privkey.pem
	#Include /etc/letsencrypt/options-ssl-apache.conf
	#Header always set Strict-Transport-Security "max-age=15552000"
</VirtualHost>
EOF
sudo a2ensite ${url}.conf
sudo service apache2 reload

# Certbot: Configuration
sudo certbot certonly --apache --email ${email} --agree-tos -n -d ${url}
sudo sed -i 's/#/ /g' /etc/apache2/sites-available/${url}.conf
sudo service apache2 reload

# Nextlcoud: Create data directory & set permission rights
sudo mkdir /data/${short}/data/
sudo chown -R www-data:www-data /data/${short}/data/

# Nextcloud: Create database
pwddb=$(openssl rand -base64 12)
sudo mysql -u root -e "CREATE USER '${short}_u'@'localhost' IDENTIFIED BY '${pwddb}'; CREATE DATABASE ${short}; GRANT ALL PRIVILEGES ON ${short}.* TO '${short}_u'@'localhost'; FLUSH PRIVILEGES;"

# Nextcloud: Installation
pwduser=$(openssl rand -base64 12)
sudo -u www-data php /var/www/${short}/occ maintenance:install --database "mysql" --database-name "${short}" --database-user "${short}_u" --database-pass "${pwddb}" --data-dir "/home/${short}/data" --admin-user "${user}" --admin-pass "${pwduser}"

# Nextcloud: Configuration
## Change the trusted_domain
sudo -u www-data php /var/www/${short}/occ config:system:set trusted_domains 0 --value=${url}
## Set the CLI-URL
sudo -u www-data php /var/www/${short}/occ config:system:set overwrite.cli.url --value=https://${url}
## Configure Mem Cache
sudo -u www-data php /var/www/${short}/occ config:system:set memcache.local --value=\\OC\\Memcache\\APCu
sudo sed -i "s/memory_limit = .*/memory_limit = 512M/" /etc/php/7.4/apache2/php.ini
sudo sed -i '$aopcache.enable=1' /etc/php/7.4/apache2/php.ini
sudo sed -i '$aopcache.enable_cli=1' /etc/php/7.4/apache2/php.ini
sudo sed -i '$aopcache.interned_strings_buffer=8' /etc/php/7.4/apache2/php.ini
sudo sed -i '$aopcache.max_accelerated_files=10000' /etc/php/7.4/apache2/php.ini
sudo sed -i '$aopcache.memory_consumption=128' /etc/php/7.4/apache2/php.ini
sudo sed -i '$aopcache.save_comments=1' /etc/php/7.4/apache2/php.ini
sudo sed -i '$aopcache.revalidate_freq=1' /etc/php/7.4/apache2/php.ini
sudo service apache2 reload
## Timeout
sudo -u www-data sed -i "s/RequestOptions::TIMEOUT => 30/RequestOptions::TIMEOUT => 600/" /var/www/${short}/lib/private/Http/Client/Client.php
## URL without index.php
sudo -u www-data php /var/www/${short}/occ config:system:set htaccess.RewriteBase --value=/
sudo -u www-data php /var/www/${short}/occ maintenance:update:htaccess

#Nextcloud: Install apps
## Calendar
sudo -u www-data php /var/www/${short}/occ app:install calendar
## Contacts
sudo -u www-data php /var/www/${short}/occ app:install contacts
## Groupfolders
sudo -u www-data php /var/www/${short}/occ app:install groupfolders

## Password output 
echo "Database password: ${pwddb}"
echo "Admin password:    ${pwduser}"
