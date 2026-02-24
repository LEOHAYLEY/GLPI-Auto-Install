#!/bin/bash

set -e

echo "=========================================="
echo "     INSTALADOR AUTOMATICO GLPI v4"
echo "=========================================="

# Detectar sistema
if [ -f /etc/debian_version ]; then
    OS="debian"
    WEB_USER="www-data"
    APACHE="apache2"
    PHP="php"
elif [ -f /etc/redhat-release ]; then
    OS="redhat"
    WEB_USER="apache"
    APACHE="httpd"
    PHP="php"
else
    echo "Sistema nao suportado."
    exit 1
fi

echo "Sistema detectado: $OS"

# Variáveis banco
DB_NAME="glpidb"
DB_USER="glpiuser"
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 16)

echo "Senha gerada para banco: $DB_PASS"

echo "Atualizando sistema..."

if [ "$OS" = "debian" ]; then
    apt update -y
    apt install -y apache2 mariadb-server redis-server curl wget unzip \
    php php-{mysql,xml,mbstring,curl,gd,intl,zip,bz2,ldap,apcu,redis,cli}

    systemctl enable apache2 mariadb redis-server
    systemctl restart apache2 mariadb redis-server
else
    dnf install -y epel-release
    dnf install -y httpd mariadb-server redis curl wget unzip \
    php php-{mysqlnd,xml,mbstring,curl,gd,intl,zip,bz2,ldap,opcache,redis,cli}

    systemctl enable httpd mariadb redis
    systemctl restart httpd mariadb redis
fi

echo "Configurando banco..."

mysql -u root <<EOF
DROP DATABASE IF EXISTS $DB_NAME;
DROP USER IF EXISTS '$DB_USER'@'localhost';
CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '$DB_USER'@'localhost' IDENTIFIED WITH mysql_native_password BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "Banco criado com sucesso."

echo "Baixando ultima versao do GLPI..."

GLPI_URL=$(curl -s https://api.github.com/repos/glpi-project/glpi/releases/latest \
| grep browser_download_url \
| grep ".tgz" \
| cut -d '"' -f 4)

wget -O /tmp/glpi.tgz $GLPI_URL

rm -rf /var/www/glpi
tar -xzf /tmp/glpi.tgz -C /var/www/

chown -R $WEB_USER:$WEB_USER /var/www/glpi
chmod -R 755 /var/www/glpi

echo "GLPI extraido."

echo "Instalando banco no GLPI..."

sudo -u $WEB_USER $PHP /var/www/glpi/bin/console db:install \
--db-host=localhost \
--db-name=$DB_NAME \
--db-user=$DB_USER \
--db-password=$DB_PASS \
--no-interaction

echo "Banco inicializado no GLPI."

echo "Configurando Redis..."

sudo -u $WEB_USER $PHP /var/www/glpi/bin/console config:set cache_handler redis
sudo -u $WEB_USER $PHP /var/www/glpi/bin/console config:set redis_host 127.0.0.1

echo "Redis configurado."

echo "Configurando cron..."

echo "*/5 * * * * $WEB_USER $PHP /var/www/glpi/bin/console glpi:cron >> /var/www/glpi/files/_log/cron.log 2>&1" > /etc/cron.d/glpi

chmod 644 /etc/cron.d/glpi

IP=$(hostname -I | awk '{print $1}')

echo ""
echo "=========================================="
echo "        GLPI INSTALADO COM SUCESSO"
echo "=========================================="
echo "Acesse: http://$IP/glpi"
echo ""
echo "Banco:"
echo "Nome: $DB_NAME"
echo "Usuario: $DB_USER"
echo "Senha: $DB_PASS"
echo "=========================================="
