#!/bin/bash

# Script de instalação automática do Zabbix com suporte a PT-BR e Inglês
# Versão atualizada: 05/06/2026

# --------------------------
# 1. CONFIGURAR IDIOMAS DO SISTEMA
# --------------------------
echo "=== Configurando idiomas do sistema: PT-BR e Inglês ==="
apt update -y
apt install -y locales

# Habilitar pt_BR.UTF-8 e en_US.UTF-8
sed -i 's/^# *pt_BR.UTF-8 UTF-8/pt_BR.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen

# Gerar os idiomas
locale-gen

# Definir en_US.UTF-8 como padrão do sistema (original)
# e deixar pt_BR disponível para uso no Zabbix
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

echo "✅ Idiomas configurados: en_US.UTF-8 (padrão) e pt_BR.UTF-8 (disponível)"

# --------------------------
# 2. ADICIONAR REPOSITÓRIOS DO ZABBIX
# --------------------------
echo "=== Adicionando repositórios Zabbix ==="
wget -q https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_7.0-2+ubuntu22.04_all.deb
dpkg -i zabbix-release_7.0-2+ubuntu22.04_all.deb
apt update -y

# --------------------------
# 3. INSTALAR PACOTES DO ZABBIX, BANCO E APACHE
# --------------------------
echo "=== Instalando Zabbix, MySQL e Apache ==="
apt install -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-agent mysql-server

# --------------------------
# 4. CONFIGURAR BANCO DE DADOS
# --------------------------
echo "=== Configurando banco de dados MySQL ==="
mysql -e "CREATE DATABASE IF NOT EXISTS zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;"
mysql -e "CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY '0fd8UqPoJwiWfamZ';"
mysql -e "GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Importar esquema inicial
zabbix_server --create-db -c /etc/zabbix/zabbix_server.conf

# --------------------------
# 5. CONFIGURAR ACESSO DO ZABBIX AO BANCO
# --------------------------
sed -i "s/^# DBPassword=/DBPassword=0fd8UqPoJwiWfamZ/" /etc/zabbix/zabbix_server.conf

# --------------------------
# 6. CONFIGURAR IDIOMA PADRÃO NO ZABBIX (PT-BR)
# --------------------------
echo "=== Definindo idioma PT-BR para todos os usuários ==="
# Para versões 6.0+, 7.0+ usa coluna 'username'
mysql -u zabbix -p0fd8UqPoJwiWfamZ zabbix -e "UPDATE users SET lang='pt_BR' WHERE username='Admin';"
# Definir para TODOS os usuários de uma vez
mysql -u zabbix -p0fd8UqPoJwiWfamZ zabbix -e "UPDATE users SET lang='pt_BR' WHERE lang<>'pt_BR';"

# --------------------------
# 7. CONFIGURAR APACHE
# --------------------------
echo "=== Configurando Apache ==="
echo "ServerName zabbixserver" | tee /etc/apache2/conf-available/servername.conf
a2enconf servername
systemctl reload apache2

# Ajustar fuso horário no PHP (essencial para funcionar com idioma)
sed -i 's/^;date.timezone =/date.timezone = "America\/Sao_Paulo"/' /etc/zabbix/apache.conf

# --------------------------
# 8. HABILITAR E INICIAR SERVIÇOS
# --------------------------
echo "=== Iniciando serviços ==="
systemctl enable --now zabbix-server zabbix-agent apache2
systemctl restart zabbix-server zabbix-agent apache2

# --------------------------
# FINALIZAÇÃO
# --------------------------
echo ""
echo "✅ INSTALAÇÃO FINALIZADA COM SUCESSO!"
echo "✅ Idiomas do sistema: en_US.UTF-8 (padrão) e pt_BR.UTF-8 (instalado)"
echo "✅ Interface Zabbix configurada em Português do Brasil"
echo "✅ Acesse: http://zabbixserver/zabbix"
echo "✅ Usuário: Admin | Senha padrão: zabbix"
