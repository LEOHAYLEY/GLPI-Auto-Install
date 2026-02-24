#!/bin/bash

echo "=============================================="
echo "        GLPI Automatic Installer"
echo "=============================================="

if [ "$EUID" -ne 0 ]; then
  echo "Execute como root."
  exit 1
fi

### Detect OS
if [ -f /etc/debian_version ]; then
    OS="debian"
    APACHE="apache2"
    APACHE_USER="www-data"
    PKG_UPDATE="apt update -y"
    PKG_INSTALL="apt install -y"
elif [ -f /etc/redhat-release ]; then
    OS="rhel"
    APACHE="httpd"
    APACHE_USER="apache"
    PKG_UPDATE="dnf update -y"
    PKG_INSTALL="dnf install -y"
else
    echo "Sistema não suportado."
    exit 1
fi

echo "Sistema detectado: $OS"
sleep 2

### Update system
eval $PKG_UPDATE

### Install dependencies
if [ "$OS" = "debian" ]; then
    eval $PKG_INSTALL curl wget unzip tar apache2 mariadb-server redis-server \
    php php-cli php-common php-mysql php-gd php-intl php-mbstring php-bcmath php-xml php-curl php-zip php-ldap
else
    eval $PKG_INSTALL curl wget unzip tar httpd mariadb-server redis \
    php php-cli php-common php-mysqlnd php-gd php-intl php-mbstring php-bcmath php-xml php-curl php-zip php-ldap
fi

systemctl enable mariadb --now
systemctl enable $APACHE --now

if [ "$OS" = "debian" ]; then
    systemctl enable redis-server --now
else
    systemctl enable redis --now
fi

### Generate DB credentials
DB_NAME="glpidb"
DB_USER="glpiuser"
DB_PASS=$(openssl rand -base64 16 | tr -dc A-Za-z0-9 | head -c16)

echo "Criando banco de dados..."

mysql -u root <<EOF
CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

### Get latest GLPI
echo "Obtendo última versão do GLPI..."
GLPI_URL=$(curl -s https://api.github.com/repos/glpi-project/glpi/releases/latest \
| grep browser_download_url \
| grep ".tgz" \
| cut -d '"' -f 4)

if [ -z "$GLPI_URL" ]; then
    echo "Erro ao obter URL do GLPI"
    exit 1
fi

wget -O /tmp/glpi.tgz $GLPI_URL
tar -xzf /tmp/glpi.tgz -C /var/www/

chown -R $APACHE_USER:$APACHE_USER /var/www/glpi
chmod -R 755 /var/www/glpi

### Apache Config
if [ "$OS" = "debian" ]; then
cat > /etc/apache2/sites-available/glpi.conf <<EOF
<VirtualHost *:80>
    DocumentRoot /var/www/glpi/public
    <Directory /var/www/glpi/public>
        Require all granted
        AllowOverride All
    </Directory>
</VirtualHost>
EOF

a2enmod rewrite
a2ensite glpi.conf
systemctl reload apache2
else
cat > /etc/httpd/conf.d/glpi.conf <<EOF
<VirtualHost *:80>
    DocumentRoot /var/www/glpi/public
    <Directory /var/www/glpi/public>
        Require all granted
        AllowOverride All
    </Directory>
</VirtualHost>
EOF

systemctl reload httpd
fi

### Configure Redis in GLPI
echo "Configurando Redis..."

cat > /var/www/glpi/config/local_define.php <<EOF
<?php
define('GLPI_CACHE_REDIS_SERVER', '127.0.0.1');
define('GLPI_CACHE_REDIS_PORT', 6379);
define('GLPI_CACHE_REDIS_DATABASE', 0);
EOF

chown $APACHE_USER:$APACHE_USER /var/www/glpi/config/local_define.php

### Setup GLPI CLI install
echo "Instalando GLPI via CLI..."

php /var/www/glpi/bin/console db:install \
--db-host=localhost \
--db-name=$DB_NAME \
--db-user=$DB_USER \
--db-password=$DB_PASS \
--no-interaction

### Setup Cron
echo "Configurando cron..."

cat > /etc/systemd/system/glpi-cron.service <<EOF
[Unit]
Description=GLPI Cron
After=network.target

[Service]
User=$APACHE_USER
ExecStart=/usr/bin/php /var/www/glpi/bin/console glpi:cron

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable glpi-cron --now

echo "=============================================="
echo "Instalação concluída com sucesso!"
echo ""
echo "URL: http://SEU_IP"
echo "Banco: $DB_NAME"
echo "Usuário DB: $DB_USER"
echo "Senha DB: $DB_PASS"
echo "=============================================="
