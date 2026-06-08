#!/bin/bash
set -euo pipefail

# --------------------------
# FUNÇÃO: Barra de Progresso
# --------------------------
progress_bar() {
    local step=$1
    local total=$2
    local message=$3
    local width=50
    local percent=$(( (step * 100) / total ))
    local filled=$(( (percent * width) / 100 ))
    local empty=$(( width - filled ))

    echo -ne "\n\033[1;34m[${step}/${total}] ${message}\033[0m\n["
    echo -ne "\033[1;32m"
    printf "%${filled}s" | tr ' ' '#'
    echo -ne "\033[0m"
    printf "%${empty}s" | tr ' ' '-'
    echo -ne "] ${percent}%\r"
    echo -ne "\n"
}

# --------------------------
# CABEÇALHO
# --------------------------
clear
echo -e "\033[1;36m============================================================\033[0m"
echo -e "\033[1;36m        INSTALAÇÃO ZABBIX PROXY 7.0 LTS - UBUNTU          \033[0m"
echo -e "\033[1;36m============================================================\033[0m"
echo -e "\nEste script instala e configura automaticamente o Zabbix Proxy"
echo -e "usando MariaDB como banco de dados e Apache para interface web.\n"

# --------------------------
# DETECÇÃO E ENTRADA DE DADOS
# --------------------------
# Detecta IP automaticamente
PROXY_IP=$(hostname -I | awk '{print $1}')
if [[ -z "${PROXY_IP}" ]]; then
    echo -e "\033[1;31m❌ Erro: Não foi possível detectar o IP do servidor!\033[0m"
    exit 1
fi
echo -e "📌 IP detectado automaticamente: \033[1;33m${PROXY_IP}\033[0m"

# Solicita apenas o IP do servidor principal
while true; do
    read -p "🔹 Digite o IP do Zabbix Server principal: " ZABBIX_SERVER_IP
    if [[ "${ZABBIX_SERVER_IP}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        break
    else
        echo -e "\033[1;31m❌ IP inválido! Digite um endereço no formato: 192.168.1.100\033[0m"
    fi
done

# Variáveis automáticas e seguras
PROXY_NAME="proxy-${PROXY_IP//./-}"
DB_NAME="zabbix_proxy"
DB_USER="zabbix_proxy"
DB_PASS=$(openssl rand -hex 10) # Senha forte gerada automaticamente
TOTAL_STEPS=7

# --------------------------
# ETAPA 1: Atualizar sistema e instalar dependências
# --------------------------
progress_bar 1 ${TOTAL_STEPS} "Atualizando sistema e instalando dependências"
apt update -qq
apt install -y -qq wget gnupg2 mariadb-server apache2 libapache2-mod-php \
    php-mysql php-mbstring php-xml php-gd php-bcmath php-ldap php-cli > /dev/null 2>&1

# --------------------------
# ETAPA 2: Adicionar repositório Zabbix
# --------------------------
progress_bar 2 ${TOTAL_STEPS} "Adicionando repositório oficial do Zabbix 7.0 LTS"
wget -q https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.0+ubuntu24.04_all.deb
dpkg -i zabbix-release_latest_7.0+ubuntu24.04_all.deb > /dev/null 2>&1
apt update -qq
rm -f zabbix-release_latest_7.0+ubuntu24.04_all.deb

# --------------------------
# ETAPA 3: Instalar Zabbix Proxy
# --------------------------
progress_bar 3 ${TOTAL_STEPS} "Instalando Zabbix Proxy e componentes"
apt install -y -qq zabbix-proxy-mysql zabbix-sql-scripts > /dev/null 2>&1

# --------------------------
# ETAPA 4: Configurar Banco de Dados MariaDB
# --------------------------
progress_bar 4 ${TOTAL_STEPS} "Configurando banco de dados MariaDB"
mysql -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;" > /dev/null 2>&1
mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';" > /dev/null 2>&1
mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';" > /dev/null 2>&1
mysql -e "FLUSH PRIVILEGES;" > /dev/null 2>&1

# Importar estrutura do banco
zcat /usr/share/zabbix/sql-scripts/mysql/proxy.sql.gz | \
    mysql --default-character-set=utf8mb4 -u"${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" > /dev/null 2>&1

# --------------------------
# ETAPA 5: Configurar Zabbix Proxy
# --------------------------
progress_bar 5 ${TOTAL_STEPS} "Aplicando configurações do Proxy"
sed -i "s/^Server=127.0.0.1/Server=${ZABBIX_SERVER_IP}/" /etc/zabbix/zabbix_proxy.conf
sed -i "s/^# ServerPort=10051/ServerPort=10051/" /etc/zabbix/zabbix_proxy.conf
sed -i "s/^Hostname=Zabbix proxy/Hostname=${PROXY_NAME}/" /etc/zabbix/zabbix_proxy.conf
sed -i "s/^DBName=zabbix_proxy/DBName=${DB_NAME}/" /etc/zabbix/zabbix_proxy.conf
sed -i "s/^DBUser=zabbix_proxy/DBUser=${DB_USER}/" /etc/zabbix/zabbix_proxy.conf
sed -i "s/^# DBPassword=/DBPassword=${DB_PASS}/" /etc/zabbix/zabbix_proxy.conf

# --------------------------
# ETAPA 6: Definir permissões de segurança
# --------------------------
progress_bar 6 ${TOTAL_STEPS} "Ajustando permissões e segurança"
chown -R zabbix:zabbix /etc/zabbix /var/log/zabbix /var/lib/zabbix
chmod 700 /var/lib/zabbix
chmod 640 /etc/zabbix/zabbix_proxy.conf

# --------------------------
# ETAPA 7: Iniciar e habilitar serviços
# --------------------------
progress_bar 7 ${TOTAL_STEPS} "Iniciando e habilitando serviços"
systemctl daemon-reload > /dev/null 2>&1
systemctl restart zabbix-proxy apache2 > /dev/null 2>&1
systemctl enable zabbix-proxy apache2 > /dev/null 2>&1

# --------------------------
# RESUMO FINAL
# --------------------------
echo -e "\n\033[1;36m============================================================\033[0m"
echo -e "\033[1;32m✅ INSTALAÇÃO CONCLUÍDA COM SUCESSO!\033[0m"
echo -e "\033[1;36m============================================================\033[0m"
echo -e "\n📋 Dados da instalação:"
echo -e "   • Nome do Proxy:      \033[1;33m${PROXY_NAME}\033[0m"
echo -e "   • IP do Proxy:        \033[1;33m${PROXY_IP}\033[0m"
echo -e "   • Servidor Principal: \033[1;33m${ZABBIX_SERVER_IP}:10051\033[0m"
echo -e "   • Banco de Dados:     MariaDB"
echo -e "     → Usuário:          \033[1;33m${DB_USER}\033[0m"
echo -e "     → Senha:            \033[1;33m${DB_PASS}\033[0m"
echo -e "\n📁 Arquivo de configuração: /etc/zabbix/zabbix_proxy.conf"
echo -e "📄 Logs do Proxy:           /var/log/zabbix/zabbix_proxy.log"
echo -e "🌐 Acesso web:              http://${PROXY_IP}/zabbix"

echo -e "\n🔍 Status dos serviços:"
systemctl is-active --quiet zabbix-proxy && echo "   • Zabbix Proxy: \033[1;32mAtivo ✅\033[0m" || echo "   • Zabbix Proxy: \033[1;31mInativo ❌\033[0m"
systemctl is-active --quiet apache2 && echo "   • Apache:       \033[1;32mAtivo ✅\033[0m" || echo "   • Apache:       \033[1;31mInativo ❌\033[0m"

echo -e "\n💡 Próximo passo: Adicione este proxy na interface web do Zabbix Server!"
echo -e "\033[1;36m============================================================\033[0m"
