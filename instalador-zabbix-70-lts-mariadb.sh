#!/bin/bash

# ==============================================
# Script: Instalação Zabbix 7.0 LTS All-in-One
# Compatibilidade: Ubuntu, Zorin OS, Mint, Pop!_OS e RHEL
# Banco: MariaDB
# Idioma Padrão: Inglês (en_US) | Disponível: pt_BR
# Autor: Script Automatizado - Versão Atualizada (corrigida)
# ==============================================

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # Sem cor

# Variáveis de configuração
ZBX_VERSION="7.0"
MARIADB_VERSION="10.11"
LOG_FILE="/var/log/zabbix_install.log"
INSTALL_DIR="/tmp/zabbix_install"
TOTAL_STEPS=16
CRED_FILE="/root/.zabbix_credentials"

# ==============================================
# FUNÇÕES AUXILIARES
# ==============================================

update_progress() {
    local current_step=$1
    local message=$2
    local percent=$(( current_step * 100 / TOTAL_STEPS ))
    local filled=$(( percent / 2 ))
    local empty=$(( 50 - filled ))
    local bar="["
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    bar+="]"
    echo -e "${CYAN}${bar} ${GREEN}${percent}% ${NC}- ${message}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${percent}%] ${message}" >> "$LOG_FILE"
}

run_with_spinner() {
    local command="$1"
    local message="$2"
    
    echo -n -e "${YELLOW}⏳ Processando: ${message}... ${NC}"
    
    eval "$command" >> "$LOG_FILE" 2>&1 &
    local pid=$!
    
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep "^$pid$")" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep 0.1
        printf "\b\b\b\b\b\b"
    done
    
    wait $pid
    local status=$?
    
    if [ $status -eq 0 ]; then
        echo -e "\b\b\b\b\b\b${GREEN}✅ Concluído!${NC}      "
    else
        echo -e "\b\b\b\b\b\b${RED}❌ ERRO!${NC}         "
        echo -e "${YELLOW}⚠️ Verifique o log completo em: $LOG_FILE${NC}"
        exit 1
    fi
}

check_error() {
    if [ $? -ne 0 ]; then
        echo -e "\n${RED}❌ ERRO: $1${NC}"
        echo "[ERRO] $1" >> "$LOG_FILE"
        exit 1
    fi
}

new_line() {
    echo -e "\n"
}

# Aguarda o serviço do MariaDB realmente aceitar conexões antes de seguir
wait_for_mariadb() {
    local tries=30
    for ((i=1; i<=tries; i++)); do
        if mysqladmin ping --silent >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

# ==============================================
# VALIDAÇÕES INICIAIS E DETECÇÃO DE SO
# ==============================================

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ Este script deve ser executado como root!${NC}"
    echo -e "${YELLOW}Use: sudo bash $0${NC}"
    exit 1
fi

# Detectar Sistema Operacional e mapear Zorin/Mint/PopOS para Ubuntu
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_VERSION_ID=$VERSION_ID
    
    # Previne que sistemas baseados em debian fiquem sem a variável de codinome
    if [ -z "$UBUNTU_CODENAME" ] && [ -n "$VERSION_CODENAME" ]; then
        UBUNTU_CODENAME=$VERSION_CODENAME
    fi
    
    # Adaptação especial para Zorin OS, Mint e derivados do Ubuntu
    if [[ "$ID_LIKE" == *"ubuntu"* || "$ID_LIKE" == *"debian"* || "$OS" == "zorin" || "$OS" == "ubuntu" ]]; then
        OS_FAMILY="debian"
        OS="ubuntu" # Força o nome para o repositório do Zabbix reconhecer
        
        # Traduz o Codinome do Zorin/Mint para a versão numérica base do Ubuntu
        if [ -n "$UBUNTU_CODENAME" ]; then
            case "$UBUNTU_CODENAME" in
                noble) OS_VERSION_ID="24.04" ;;
                jammy) OS_VERSION_ID="22.04" ;;
                focal) OS_VERSION_ID="20.04" ;;
                bionic) OS_VERSION_ID="18.04" ;;
                *) OS_VERSION_ID="24.04" ;; # Fallback padrão
            esac
        fi
        
        PKG_MGR="apt-get"
        PKG_UPDATE="apt-get update -y"
        PKG_INSTALL="apt-get install -y"
        WEB_SERVER="apache2"
        WEB_USER="www-data"
        PHP_INI_PATH="/etc/php/*/apache2/php.ini"
        
    elif [[ "$OS" =~ ^(centos|rhel|almalinux|rocky)$ ]]; then
        OS_FAMILY="rhel"
        PKG_MGR="dnf"
        PKG_UPDATE="dnf makecache"
        PKG_INSTALL="dnf install -y"
        WEB_SERVER="httpd"
        WEB_USER="apache"
        PHP_INI_PATH="/etc/php.ini"
    else
        echo -e "${RED}❌ Sistema Operacional '$PRETTY_NAME' não é suportado por este script.${NC}"
        exit 1
    fi
else
    echo -e "${RED}❌ Arquivo /etc/os-release não encontrado.${NC}"
    exit 1
fi

clear
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                                                          ║"
echo "║     🚀 INSTALADOR UNIVERSAL ZABBIX 7.0 LTS 🚀            ║"
echo "║                                                          ║"
echo "║     All-in-One com MariaDB + Apache + PHP                ║"
echo "║     Suporte: Ubuntu, Zorin OS, Mint, Pop!_OS, etc.       ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "${YELLOW}📋 Log da instalação: $LOG_FILE${NC}"
echo -e "${YELLOW}⏱️  Tempo estimado: 5-15 minutos (dependendo da internet)${NC}"
echo -e "${YELLOW}🐧 Sistema detectado: $PRETTY_NAME (Base: Ubuntu $OS_VERSION_ID)${NC}"
new_line
sleep 3

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR" || exit 1
> "$LOG_FILE"

# ==============================================
# CREDENCIAIS: gera na primeira execução, reaproveita nas seguintes
# ==============================================
if [ -f "$CRED_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CRED_FILE"
    echo -e "${YELLOW}⚠️  Credenciais de uma execução anterior encontradas em ${CRED_FILE} — reaproveitando as mesmas senhas.${NC}"
    new_line
else
    MYSQL_ROOT_PASSWORD=$(openssl rand -base64 20 | tr -d "=+/" | cut -c1-20)
    ZABBIX_DB_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)
    cat > "$CRED_FILE" << EOF
MYSQL_ROOT_PASSWORD='${MYSQL_ROOT_PASSWORD}'
ZABBIX_DB_PASSWORD='${ZABBIX_DB_PASSWORD}'
EOF
    chmod 600 "$CRED_FILE"
fi

# ==============================================
# ETAPAS DE INSTALAÇÃO
# ==============================================

update_progress 1 "Atualizando lista de pacotes do sistema ($PKG_MGR)"
run_with_spinner "$PKG_UPDATE" "Atualizando repositórios"

update_progress 2 "Instalando ferramentas básicas..."
if [ "$OS_FAMILY" == "debian" ]; then
    run_with_spinner "$PKG_INSTALL wget curl gnupg apt-transport-https software-properties-common lsb-release locales" "Baixando dependências"
else
    run_with_spinner "$PKG_INSTALL wget curl epel-release" "Baixando dependências"
fi

update_progress 3 "Adicionando repositório oficial do Zabbix..."
if [ "$OS_FAMILY" == "debian" ]; then
    ZBX_URL="https://repo.zabbix.com/zabbix/${ZBX_VERSION}/${OS}/pool/main/z/zabbix-release/zabbix-release_${ZBX_VERSION}-1+${OS}${OS_VERSION_ID}_all.deb"
    run_with_spinner "wget -q $ZBX_URL -O zabbix-release.deb && dpkg -i zabbix-release.deb && apt-get update" "Configurando repositório Zabbix"
else
    ZBX_URL="https://repo.zabbix.com/zabbix/${ZBX_VERSION}/${OS}/${OS_VERSION_ID%%.*}/x86_64/zabbix-release-${ZBX_VERSION}-1.el${OS_VERSION_ID%%.*}.noarch.rpm"
    run_with_spinner "rpm -Uvh $ZBX_URL && dnf clean all" "Configurando repositório Zabbix"
fi

update_progress 4 "Adicionando repositório oficial do MariaDB..."
if [ "$OS_FAMILY" == "debian" ]; then
    MARIADB_OS_FLAG="--os-type=ubuntu --os-version=${UBUNTU_CODENAME:-noble}"
    run_with_spinner "curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | bash -s -- --mariadb-server-version=${MARIADB_VERSION} $MARIADB_OS_FLAG" "Configurando repositório MariaDB"
else
    run_with_spinner "curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | bash -s -- --mariadb-server-version=${MARIADB_VERSION}" "Configurando repositório MariaDB"
fi

update_progress 5 "Instalando servidor e cliente MariaDB..."
run_with_spinner "$PKG_INSTALL mariadb-server mariadb-client" "Baixando MariaDB (Isso pode demorar um pouco)"

update_progress 6 "Iniciando e configurando segurança do Banco de Dados..."
systemctl start mariadb >> "$LOG_FILE" 2>&1
systemctl enable mariadb >> "$LOG_FILE" 2>&1

if ! wait_for_mariadb; then
    echo -e "\n${RED}❌ ERRO: O serviço do MariaDB não respondeu a tempo.${NC}"
    echo "[ERRO] MariaDB não respondeu a tempo" >> "$LOG_FILE"
    exit 1
fi

# Detecta o estado atual do root: instalação nova (sem senha) x reexecução (senha já definida)
if mysql -u root -e "SELECT 1;" >/dev/null 2>&1; then
    # Root ainda sem senha -> primeira execução, faz o hardening normal
    mysql -u root << EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
    check_error "Falha ao configurar a senha inicial do root do MariaDB"
elif mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" >/dev/null 2>&1; then
    # Root já está com a senha salva em CRED_FILE (execução anterior) -> nada a fazer
    :
else
    echo -e "\n${RED}❌ ERRO: Não foi possível autenticar no MariaDB como root (nem sem senha, nem com a senha salva em ${CRED_FILE}).${NC}"
    echo -e "${YELLOW}Se o MariaDB já foi configurado manualmente antes, redefina a senha do root ou remova ${CRED_FILE} e reinstale o MariaDB do zero.${NC}"
    exit 1
fi

update_progress 7 "Instalando Zabbix Server, Frontend e Agente..."
if [ "$OS_FAMILY" == "debian" ]; then
    run_with_spinner "$PKG_INSTALL zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-sql-scripts zabbix-agent" "Instalando Zabbix e Frontend"
else
    run_with_spinner "$PKG_INSTALL zabbix-server-mysql zabbix-web-mysql zabbix-apache-conf zabbix-sql-scripts zabbix-selinux-policy zabbix-agent" "Instalando Zabbix e Frontend"
fi

update_progress 8 "Criando banco de dados do Zabbix..."
run_with_spinner "mysql -uroot -p\"${MYSQL_ROOT_PASSWORD}\" -e \"CREATE DATABASE IF NOT EXISTS zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin; CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY '${ZABBIX_DB_PASSWORD}'; ALTER USER 'zabbix'@'localhost' IDENTIFIED BY '${ZABBIX_DB_PASSWORD}'; GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost'; FLUSH PRIVILEGES;\"" "Criando DB"

update_progress 9 "Importando esquema de dados do Zabbix..."
SQL_FILE="/usr/share/zabbix-sql-scripts/mysql/server.sql.gz"
ZBX_TABLE_COUNT=$(mysql -uzabbix -p"${ZABBIX_DB_PASSWORD}" -N -B -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='zabbix';" 2>>"$LOG_FILE")
if [ "${ZBX_TABLE_COUNT:-0}" -gt 0 ]; then
    update_progress 9 "Esquema do Zabbix já existe no banco — pulando importação"
else
    run_with_spinner "zcat $SQL_FILE | mysql -uzabbix -p\"${ZABBIX_DB_PASSWORD}\" zabbix" "Importando tabelas (Aguarde...)"
fi

update_progress 10 "Configurando arquivo principal do Zabbix Server..."
sed -i "s/^# DBPassword=/DBPassword=${ZABBIX_DB_PASSWORD}/" /etc/zabbix/zabbix_server.conf
sed -i "s/^DBPassword=.*/DBPassword=${ZABBIX_DB_PASSWORD}/" /etc/zabbix/zabbix_server.conf
sed -i "s/^# DBHost=localhost/DBHost=localhost/" /etc/zabbix/zabbix_server.conf

update_progress 11 "Configurando PHP e Web Server..."
ACTUAL_PHP_INI=$(ls $PHP_INI_PATH 2>/dev/null | head -n 1)
if [ -n "$ACTUAL_PHP_INI" ]; then
    sed -i 's/^max_execution_time.*/max_execution_time = 300/' "$ACTUAL_PHP_INI"
    sed -i 's/^memory_limit.*/memory_limit = 256M/' "$ACTUAL_PHP_INI"
    sed -i 's/^post_max_size.*/post_max_size = 16M/' "$ACTUAL_PHP_INI"
    sed -i 's/^upload_max_filesize.*/upload_max_filesize = 2M/' "$ACTUAL_PHP_INI"
    sed -i 's/^max_input_time.*/max_input_time = 300/' "$ACTUAL_PHP_INI"
    sed -i 's|^;date.timezone.*|date.timezone = America/Sao_Paulo|' "$ACTUAL_PHP_INI"
fi

update_progress 12 "Configurando idiomas do Frontend (Inglês e PT-BR)..."
if [ "$OS_FAMILY" == "debian" ]; then
    locale-gen en_US.UTF-8 pt_BR.UTF-8 >> "$LOG_FILE" 2>&1
    update-locale LANG=en_US.UTF-8 >> "$LOG_FILE" 2>&1
fi

cat > /etc/zabbix/web/zabbix.conf.php << EOF
<?php
// Arquivo gerado automaticamente
\$DB['TYPE']     = 'MYSQL';
\$DB['SERVER']   = 'localhost';
\$DB['PORT']     = '0';
\$DB['DATABASE'] = 'zabbix';
\$DB['USER']     = 'zabbix';
\$DB['PASSWORD'] = '${ZABBIX_DB_PASSWORD}';
\$DB['SCHEMA']   = '';
\$DB['ENCRYPTION'] = false;
\$ZBX_SERVER_NAME = 'Zabbix Server';
\$IMAGE_FORMAT_DEFAULT = IMAGE_FORMAT_PNG;
\$DEFAULT_LANG = 'en_US';
EOF
chown $WEB_USER:$WEB_USER /etc/zabbix/web/zabbix.conf.php
chmod 644 /etc/zabbix/web/zabbix.conf.php

mysql -u zabbix -p"${ZABBIX_DB_PASSWORD}" zabbix -e "UPDATE users SET lang='en_US' WHERE username='Admin';" >> "$LOG_FILE" 2>&1

update_progress 13 "Iniciando e habilitando serviços ($WEB_SERVER, Zabbix)..."
run_with_spinner "systemctl restart zabbix-server zabbix-agent $WEB_SERVER mariadb && systemctl enable zabbix-server zabbix-agent $WEB_SERVER mariadb" "Reiniciando serviços"

update_progress 14 "Configurando regras de firewall..."
if command -v ufw &> /dev/null; then
    ufw allow "Apache Full" >> "$LOG_FILE" 2>&1
    ufw allow in 80/tcp >> "$LOG_FILE" 2>&1
    ufw allow 10050/tcp comment 'Zabbix Agent' >> "$LOG_FILE" 2>&1
    ufw allow 10051/tcp comment 'Zabbix Server' >> "$LOG_FILE" 2>&1
    ufw reload >> "$LOG_FILE" 2>&1
fi

update_progress 15 "Ajustando permissões finais..."
chown -R $WEB_USER:$WEB_USER /etc/zabbix/ /usr/share/zabbix/
rm -rf "$INSTALL_DIR"

update_progress 16 "Gerando relatório final..."
SERVER_IP=$(hostname -I | awk '{print $1}')
[ -z "$SERVER_IP" ] && SERVER_IP="127.0.0.1"

# Atualiza o arquivo de senhas em formato legível (sempre reflete o estado atual)
cat > /root/.zabbix_passwords << EOF
============================================
🔐 SENHAS - GUARDE COM SEGURANÇA!
============================================
MySQL Root: ${MYSQL_ROOT_PASSWORD}
--------------------------------------------
Banco Zabbix:
Usuário: zabbix
Senha: ${ZABBIX_DB_PASSWORD}
============================================
EOF
chmod 600 /root/.zabbix_passwords

new_line
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    🎉 INSTALAÇÃO CONCLUÍDA! 🎉                 ║"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
new_line
echo -e "${CYAN}📌 RESUMO DAS INFORMAÇÕES:${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🌐 Endereço Web: ${CYAN}http://${SERVER_IP}/zabbix${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}🔑 ACESSO ZABBIX (WEB):${NC}"
echo -e "${GREEN}   Usuário: ${YELLOW}Admin${NC}"
echo -e "${GREEN}   Senha:   ${YELLOW}zabbix${NC}"
echo -e "${YELLOW}   (troque essa senha padrão no primeiro login pela interface web)${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}🗄️  CREDENCIAIS DO BANCO DE DADOS:${NC}"
echo -e "${GREEN}   Root MySQL:  ${YELLOW}${MYSQL_ROOT_PASSWORD}${NC}"
echo -e "${GREEN}   Usuário DB:  ${YELLOW}zabbix${NC}"
echo -e "${GREEN}   Senha DB:    ${YELLOW}${ZABBIX_DB_PASSWORD}${NC}"
echo -e "${YELLOW}   *(Também salvo em: /root/.zabbix_passwords e ${CRED_FILE})*${NC}"
new_line

# ==============================================
# ABRIR NAVEGADOR AUTOMATICAMENTE
# ==============================================
if command -v xdg-open &> /dev/null; then
    echo -e "${YELLOW}🌐 Abrindo o Zabbix no seu navegador padrão...${NC}"
    # Usa o usuário original que invocou o sudo para que a janela abra na área de trabalho dele
    if [ -n "$SUDO_USER" ]; then
        sudo -u "$SUDO_USER" env DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" xdg-open "http://localhost/zabbix" > /dev/null 2>&1 &
    else
        xdg-open "http://localhost/zabbix" > /dev/null 2>&1 &
    fi
fi

new_line
echo -e "${BLUE}✨ Instalação finalizada com sucesso em $(date '+%H:%M:%S')! ✨${NC}"
exit 0
