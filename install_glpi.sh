#!/bin/bash

set -e

echo "==== INSTALADOR AUTOMATICO GLPI ===="

# Detectar sistema
if [ -f /etc/debian_version ]; then
    OS="debian"
    WEB_USER="www-data"
    PHP="php"
    APACHE="apache2"
elif [ -f /etc/redhat-release ]; then
    OS="redhat"
    WEB_USER="apache"
    PHP="php"
    APACHE="httpd"
else
    echo "Sistema nao suportado."
    exit 1
fi

echo "Sistema detectado: $OS"

# Gerar senha forte
DB_NAME="glpidb"
DB_USER="glpiuser"
DB_PASS=$(openssl rand -base64 16)

echo "Senha gerada para banco: $DB_PASS"

# Atualizar sistema
if [ "$OS" = "debian" ]; then
    apt update -y
    apt install -y apache2 mariadb-server redis-server curl wget unzip \
    php php-{mysql,xml,mbstring,curl,gd,intl,zip,bz2,ldap,apcu,redis,cli}

    systemctl enable apache2 mariadb redis-server
    systemctl start apache2 mariadb redis-server

else
    dnf install -y epel-release
    dnf install -y httpd mariadb-server redis curl wget unzip \
    php php-{mysqlnd,xml,mbstring,curl,gd,intl,zip,bz2,ldap,opcache,redis,cli}

    systemctl enable httpd mariadb redis
    systemctl start httpd mariadb redis
fi

# Criar banco
mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "Banco configurado."

# Baixar última versão GLPI
GLPI_URL=$(curl -s https://api.github.com/repos/glpi-project/glpi/releases/latest \
| grep browser_download_url \
| grep ".tgz" \
| cut -d '"' -f 4)

wget -O /tmp/glpi.tgz $GLPI_URL

rm -rf /var/www/glpi
tar -xzf /tmp/glpi.tgz -C /var/www/
chown -R $WEB_USER:$WEB_USER /var/www/glpi
chmod -R 755 /var/www/glpi

echo "GLPI instalado em /var/www/glpi"

# Instalar banco via CLI como usuário web
sudo -u $WEB_USER $PHP /var/www/glpi/bin/console db:install \
--db-host=localhost \
--db-name=$DB_NAME \
--db-user=$DB_USER \
--db-password=$DB_PASS \
--no-interaction

echo "Banco inicializado no GLPI."

# Configurar Redis no GLPI
sudo -u $WEB_USER $PHP /var/www/glpi/bin/console config:set cache_handler redis
sudo -u $WEB_USER $PHP /var/www/glpi/bin/console config:set redis_host 127.0.0.1

echo "Redis configurado."

# Configurar cron
CRON_CMD="*/5 * * * * $WEB_USER $PHP /var/www/glpi/bin/console glpi:cron >> /var/www/glpi/files/_log/cron.log 2>&1"

if [ "$OS" = "debian" ]; then
    echo "$CRON_CMD" > /etc/cron.d/glpi
else
    echo "$CRON_CMD" > /etc/cron.d/glpi
fi

echo "Cron configurado."

IP=$(hostname -I | awk '{print $1}')

echo ""
echo "========================================"
echo "GLPI INSTALADO COM SUCESSO"
echo "Acesse: http://$IP/glpi"
echo ""
echo "Banco:"
echo "Nome: $DB_NAME"
echo "Usuario: $DB_USER"
echo "Senha: $DB_PASS"
echo "========================================"
