#!/bin/bash

set -e

LOGFILE="/var/log/glpi_install.log"
exec > >(tee -i $LOGFILE)
exec 2>&1

echo "=============================================="
echo "        GLPI Professional Installer"
echo "=============================================="

if [ "$EUID" -ne 0 ]; then
  echo "Execute como root."
  exit 1
fi

# -----------------------------
# Detect OS
# -----------------------------

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

$PKG_UPDATE

# -----------------------------
# Get latest GLPI release
# -----------------------------

echo "Obtendo última versão do GLPI..."

GLPI_URL=$(curl -s https://api.github.com/repos/glpi-project/glpi/releases/latest \
| grep browser_download_url \
| grep ".tgz" \
| cut -d '"' -f 4)

GLPI_VERSION=$(echo $GLPI_URL | grep -oP '[0-9]+\.[0-9]+\.[0-9]+')

echo "Versão detectada: $GLPI_VERSION"

# -----------------------------
# Define PHP version (GLPI 10 requires PHP >= 8.1)
# -----------------------------

PHP_VERSION="8.2"

echo "Instalando PHP $PHP_VERSION"

if [ "$OS" = "debian" ]; then

    $PKG_INSTALL software-properties-common
    add-apt-repository ppa:ondrej/php -y
    apt update -y

    $PKG_INSTALL $APACHE mariadb-server \
    php$PHP_VERSION php$PHP_VERSION-{mysql,curl,gd,intl,xml,mbstring,bz2,zip,ldap,apcu,imap,opcache,cli} \
    unzip wget curl tar

elif [ "$OS" = "rhel" ]; then

    $PKG_INSTALL epel-release
    $PKG_INSTALL https://rpms.remirepo.net/enterprise/remi-release-$(rpm -E %rhel).rpm
    dnf module enable php:remi-$PHP_VERSION -y

    $PKG_INSTALL $APACHE mariadb-server \
    php php-mysqlnd php-curl php-gd php-intl php-xml \
    php-mbstring php-bz2 php-zip php-ldap php-opcache \
    php-cli unzip wget curl tar
fi

systemctl enable mariadb
systemctl start mariadb

systemctl enable $APACHE
systemctl start $APACHE

# -----------------------------
# MariaDB Secure Installation
# -----------------------------

echo "Configurando MariaDB seguro..."

MYSQL_ROOT_PASS=$(openssl rand -base64 16)
GLPI_DB_PASS=$(openssl rand -base64 16)

mysql --user=root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASS';
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

echo "Senha root MariaDB: $MYSQL_ROOT_PASS" >> /root/glpi_db_credentials.txt

# -----------------------------
# Create GLPI Database
# -----------------------------

mysql -uroot -p$MYSQL_ROOT_PASS <<EOF
CREATE DATABASE glpi CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'glpi'@'localhost' IDENTIFIED BY '$GLPI_DB_PASS';
GRANT ALL PRIVILEGES ON glpi.* TO 'glpi'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "Usuário GLPI: glpi" >> /root/glpi_db_credentials.txt
echo "Senha GLPI: $GLPI_DB_PASS" >> /root/glpi_db_credentials.txt

# -----------------------------
# Download GLPI
# -----------------------------

echo "Baixando GLPI..."

wget -O /tmp/glpi.tgz $GLPI_URL
tar -xzf /tmp/glpi.tgz -C /var/www/
mv /var/www/glpi* /var/www/glpi

# -----------------------------
# Permissions
# -----------------------------

chown -R $APACHE_USER:$APACHE_USER /var/www/glpi

find /var/www/glpi -type d -exec chmod 755 {} \;
find /var/www/glpi -type f -exec chmod 644 {} \;

chmod -R 775 /var/www/glpi/files
chmod -R 775 /var/www/glpi/config

# -----------------------------
# Apache Config
# -----------------------------

if [ "$OS" = "debian" ]; then

cat <<EOF > /etc/apache2/sites-available/glpi.conf
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

cat <<EOF > /etc/httpd/conf.d/glpi.conf
<VirtualHost *:80>
    DocumentRoot /var/www/glpi/public

    <Directory /var/www/glpi/public>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

systemctl restart httpd
fi

echo ""
echo "=============================================="
echo "GLPI instalado com sucesso!"
echo "Credenciais salvas em:"
echo "/root/glpi_db_credentials.txt"
echo ""
echo "Acesse: http://IP_DO_SERVIDOR"
echo "=============================================="
