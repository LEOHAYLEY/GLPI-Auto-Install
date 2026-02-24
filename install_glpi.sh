#!/bin/bash

LOGFILE="/var/log/glpi_install.log"

echo "=============================================="
echo "        GLPI Professional Installer"
echo "=============================================="
echo "Log: $LOGFILE"
echo "=============================================="

# Verifica root
if [ "$EUID" -ne 0 ]; then
  echo "Execute como root."
  exit 1
fi

# Detecta sistema operacional
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

# Atualiza pacotes
echo "Atualizando sistema..."
eval $PKG_UPDATE || { echo "Erro ao atualizar pacotes"; exit 1; }

# Instala dependências básicas
echo "Instalando dependências..."
if [ "$OS" = "debian" ]; then
    eval $PKG_INSTALL curl wget unzip apache2 mariadb-server php php-cli php-common php-mysql php-gd php-intl php-mbstring php-bcmath php-xml php-curl php-zip php-ldap redis-server
else
    eval $PKG_INSTALL curl wget unzip httpd mariadb-server php php-cli php-common php-mysqlnd php-gd php-intl php-mbstring php-bcmath php-xml php-curl php-zip php-ldap redis
fi

if [ $? -ne 0 ]; then
    echo "Erro ao instalar dependências."
    exit 1
fi

# Inicia serviços
echo "Iniciando serviços..."
systemctl enable $APACHE --now
systemctl enable mariadb --now

if [ "$OS" = "debian" ]; then
    systemctl enable redis-server --now
else
    systemctl enable redis --now
fi

# Obtém última versão do GLPI
echo "Obtendo última versão do GLPI..."
GLPI_URL=$(curl -s https://api.github.com/repos/glpi-project/glpi/releases/latest \
| grep browser_download_url \
| grep ".tgz" \
| cut -d '"' -f 4)

if [ -z "$GLPI_URL" ]; then
    echo "Erro ao obter URL do GLPI."
    exit 1
fi

echo "Baixando GLPI: $GLPI_URL"
wget -O /tmp/glpi.tgz $GLPI_URL || { echo "Erro no download do GLPI"; exit 1; }

# Instala GLPI
echo "Extraindo arquivos..."
tar -xzf /tmp/glpi.tgz -C /var/www/ || { echo "Erro ao extrair"; exit 1; }

chown -R $APACHE_USER:$APACHE_USER /var/www/glpi
chmod -R 755 /var/www/glpi

# Configura Apache
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

echo "=============================================="
echo "Instalação concluída."
echo "Acesse: http://SEU_IP"
echo "=============================================="
