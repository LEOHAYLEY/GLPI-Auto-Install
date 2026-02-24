# GLPI-Auto-Installer-
GLPI Professional Auto Installer

Este script realiza a instalação automatizada e segura do GLPI, seguindo as recomendações oficiais do projeto.

🔍 O que o script faz

Detecta automaticamente o sistema operacional (Debian/Ubuntu ou RHEL-based)

Baixa sempre a última versão estável do GLPI diretamente do GitHub

Instala automaticamente a versão mais recente do PHP compatível

Instala e configura:

Apache

MariaDB

Redis

Executa hardening básico do MariaDB (equivalente ao mysql_secure_installation)

Gera senhas seguras automaticamente

Configura permissões conforme recomendação oficial do GLPI

Configura Redis como mecanismo de cache

Configura cron oficial do GLPI via systemd (execução a cada 5 minutos)

Cria log completo da instalação

Salva credenciais do banco em arquivo seguro no servidor

⚙️ Tecnologias configuradas automaticamente

GLPI (última versão estável)

PHP 8.2

MariaDB

Redis

Apache

systemd timer para cron

🛡️ Recursos de segurança incluídos

Remoção de banco de teste

Remoção de usuários anônimos do MySQL

Senhas fortes geradas automaticamente

Permissões corretas em diretórios sensíveis

Redis configurado localmente
