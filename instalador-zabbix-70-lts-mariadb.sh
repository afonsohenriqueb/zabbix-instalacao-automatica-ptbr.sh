#!/bin/bash

# ==============================================
# Script: Instalação Zabbix 7.0 LTS All-in-One
# Banco: MariaDB (última versão estável)
# Idioma: PT-BR
# Autor: Script Automatizado
# Versão: 2.0 - Corrigido e Melhorado
# ==============================================

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Variáveis de configuração
ZBX_VERSION="7.0"
PHP_VERSION="8.3"
LOG_FILE="/var/log/zabbix_install.log"
INSTALL_DIR="/tmp/zabbix_install"

# Função para atualizar progresso
update_progress() {
    local progress=$1
    local message=$2
    echo -e "${CYAN}[${progress}%] ${GREEN}${message}${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${progress}%] ${message}" >> $LOG_FILE
}

# Função para verificar erros
check_error() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ ERRO: $1${NC}"
        echo "[ERRO] $1" >> $LOG_FILE
        echo -e "${YELLOW}⚠️  Verifique o log em: $LOG_FILE${NC}"
        exit 1
    fi
}

# Função para pular linha
new_line() {
    echo ""
}

# Verificar execução como root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}❌ Este script deve ser executado como root!${NC}"
   echo -e "${YELLOW}Use: sudo $0${NC}"
   exit 1
fi

# Verificar versão do Ubuntu
UBUNTU_VERSION=$(lsb_release -rs)
UBUNTU_CODENAME=$(lsb_release -sc)

if [[ ! "$UBUNTU_VERSION" =~ ^(22.04|24.04)$ ]]; then
    echo -e "${RED}❌ Este script funciona apenas no Ubuntu 22.04 ou 24.04${NC}"
    echo -e "${YELLOW}Versão detectada: $UBUNTU_VERSION${NC}"
    exit 1
fi

clear

# Banner inicial
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                                                          ║"
echo "║     🚀 INSTALADOR AUTOMÁTICO ZABBIX 7.0 LTS 🚀          ║"
echo "║                                                          ║"
echo "║          All-in-One com MariaDB + PHP $PHP_VERSION          ║"
echo "║                                                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo -e "${YELLOW}📋 Log da instalação será salvo em: $LOG_FILE${NC}"
echo -e "${YELLOW}⏱️  Tempo estimado: 5-10 minutos${NC}"
echo -e "${YELLOW}🐧 Ubuntu $UBUNTU_VERSION ($UBUNTU_CODENAME) detectado${NC}"
echo ""
sleep 3

# Criar diretório temporário
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

# Gerar senhas seguras
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 20 | tr -d "=+/" | cut -c1-20)
ZABBIX_DB_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)

# Salvar senhas em arquivo seguro
cat > /root/.zabbix_passwords << EOF
============================================
SENHAS GERADAS NA INSTALAÇÃO - GUARDE COM SEGURANÇA!
============================================
MySQL Root Password: $MYSQL_ROOT_PASSWORD
Zabbix Database User: zabbix
Zabbix Database Password: $ZABBIX_DB_PASSWORD
============================================
EOF
chmod 600 /root/.zabbix_passwords

# ==============================================
# ETAPA 1: Atualização do Sistema (0-10%)
# ==============================================
update_progress 0 "Iniciando instalação do Zabbix 7.0 LTS..."
sleep 1

update_progress 2 "Atualizando repositórios do sistema..."
apt-get update -y >> $LOG_FILE 2>&1
check_error "Falha ao atualizar repositórios"

update_progress 5 "Atualizando pacotes do sistema..."
apt-get upgrade -y >> $LOG_FILE 2>&1
check_error "Falha ao atualizar pacotes"

# ==============================================
# ETAPA 2: Instalação dos Repositórios (10-20%)
# ==============================================
update_progress 10 "Instalando dependências básicas..."
apt-get install -y wget curl gnupg apt-transport-https software-properties-common openssl >> $LOG_FILE 2>&1
check_error "Falha ao instalar dependências"

update_progress 12 "Instalando repositório MariaDB..."
curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | bash -s -- --mariadb-server-version="10.11" >> $LOG_FILE 2>&1
check_error "Falha ao configurar repositório MariaDB"

update_progress 15 "Instalando repositório Zabbix..."
wget -q https://repo.zabbix.com/zabbix/$ZBX_VERSION/ubuntu/pool/main/z/zabbix-release/zabbix-release_${ZBX_VERSION}-1+ubuntu${UBUNTU_VERSION}_all.deb >> $LOG_FILE 2>&1
dpkg -i zabbix-release_${ZBX_VERSION}-1+ubuntu${UBUNTU_VERSION}_all.deb >> $LOG_FILE 2>&1
check_error "Falha ao configurar repositório Zabbix"

update_progress 18 "Adicionando repositório PHP $PHP_VERSION..."
add-apt-repository -y ppa:ondrej/php >> $LOG_FILE 2>&1

update_progress 19 "Atualizando repositórios após adições..."
apt-get update -y >> $LOG_FILE 2>&1

# ==============================================
# ETAPA 3: Instalação MariaDB (20-35%)
# ==============================================
update_progress 20 "Instalando MariaDB Server..."
apt-get install -y mariadb-server mariadb-client >> $LOG_FILE 2>&1
check_error "Falha ao instalar MariaDB"

update_progress 25 "Configurando MariaDB..."
systemctl start mariadb >> $LOG_FILE 2>&1
systemctl enable mariadb >> $LOG_FILE 2>&1

# Configuração segura do MariaDB (método correto para versões atuais)
update_progress 30 "Aplicando configurações de segurança do MariaDB..."

mysql << EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
check_error "Falha ao configurar segurança do MariaDB"

# ==============================================
# ETAPA 4: Instalação Zabbix Server (35-50%)
# ==============================================
update_progress 35 "Instalando Zabbix Server e componentes..."
apt-get install -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-sql-scripts zabbix-agent php${PHP_VERSION} php${PHP_VERSION}-mysql php${PHP_VERSION}-gd php${PHP_VERSION}-mbstring php${PHP_VERSION}-bcmath php${PHP_VERSION}-xml php${PHP_VERSION}-ldap >> $LOG_FILE 2>&1
check_error "Falha ao instalar Zabbix"

update_progress 40 "Criando banco de dados Zabbix..."
mysql -uroot -p${MYSQL_ROOT_PASSWORD} << EOF
CREATE DATABASE IF NOT EXISTS zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY '${ZABBIX_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
FLUSH PRIVILEGES;
EOF
check_error "Falha ao criar banco de dados"

update_progress 45 "Importando schema do Zabbix..."
zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql --default-character-set=utf8mb4 -uzabbix -p${ZABBIX_DB_PASSWORD} zabbix >> $LOG_FILE 2>&1
check_error "Falha ao importar schema do Zabbix"

# ==============================================
# ETAPA 5: Configuração do Zabbix (50-70%)
# ==============================================
update_progress 50 "Configurando Zabbix Server..."
# Configurar senha do banco no zabbix_server.conf
sed -i "s/# DBPassword=/DBPassword=${ZABBIX_DB_PASSWORD}/" /etc/zabbix/zabbix_server.conf
# Configurar DBHost
sed -i 's/# DBHost=localhost/DBHost=localhost/' /etc/zabbix/zabbix_server.conf

update_progress 55 "Configurando PHP e Timezone..."
# Configurar PHP para Apache
cat > /etc/php/${PHP_VERSION}/apache2/conf.d/99-zabbix.ini << EOF
max_execution_time = 300
memory_limit = 256M
post_max_size = 16M
upload_max_filesize = 2M
max_input_time = 300
date.timezone = America/Sao_Paulo
EOF

# Configurar PHP para CLI
cat > /etc/php/${PHP_VERSION}/cli/conf.d/99-zabbix.ini << EOF
date.timezone = America/Sao_Paulo
EOF

update_progress 60 "Configurando Apache para Zabbix..."
# Garantir que o Apache carrega a configuração do Zabbix
if [ -f /etc/zabbix/apache.conf ]; then
    ln -sf /etc/zabbix/apache.conf /etc/apache2/conf-available/zabbix.conf
    a2enconf zabbix >> $LOG_FILE 2>&1
fi

# ==============================================
# ETAPA 6: Inicialização dos Serviços (70-85%)
# ==============================================
update_progress 70 "Iniciando serviços..."
systemctl restart zabbix-server zabbix-agent apache2 >> $LOG_FILE 2>&1
systemctl enable zabbix-server zabbix-agent apache2 >> $LOG_FILE 2>&1

update_progress 75 "Verificando status dos serviços..."
sleep 3

# Verificar se serviços estão rodando
if systemctl is-active --quiet zabbix-server; then
    update_progress 80 "✅ Zabbix Server está rodando"
else
    echo -e "${RED}❌ Zabbix Server não iniciou corretamente${NC}"
    systemctl status zabbix-server >> $LOG_FILE
    echo -e "${YELLOW}⚠️  Verifique o log: journalctl -u zabbix-server${NC}"
fi

if systemctl is-active --quiet mariadb; then
    update_progress 82 "✅ MariaDB está rodando"
fi

if systemctl is-active --quiet apache2; then
    update_progress 84 "✅ Apache2 está rodando"
fi

# ==============================================
# ETAPA 7: Configurações Finais (85-95%)
# ==============================================
update_progress 85 "Ajustando permissões..."
chown -R www-data:www-data /etc/zabbix/
chmod -R 755 /etc/zabbix/

update_progress 88 "Configurando firewall..."
if command -v ufw &> /dev/null; then
    ufw allow 80/tcp >> $LOG_FILE 2>&1
    ufw allow 443/tcp >> $LOG_FILE 2>&1
    ufw allow 10050/tcp >> $LOG_FILE 2>&1
    ufw allow 10051/tcp >> $LOG_FILE 2>&1
    update_progress 90 "✅ Firewall configurado"
fi

update_progress 92 "Limpando arquivos temporários..."
rm -rf $INSTALL_DIR

update_progress 95 "Finalizando instalação..."

# ==============================================
# ETAPA 8: Informações Finais (95-100%)
# ==============================================
# Obter IP do servidor
SERVER_IP=$(hostname -I | awk '{print $1}')
if [ -z "$SERVER_IP" ]; then
    SERVER_IP="localhost"
fi

# Criar arquivo de configuração com informações
cat > /root/zabbix_info.txt << EOF
============================================
INFORMAÇÕES DO ZABBIX 7.0 LTS
============================================
URL de Acesso: http://$SERVER_IP/zabbix
IP do Servidor: $SERVER_IP

CREDENCIAIS DO BANCO DE DADOS:
Banco: zabbix
Usuário: zabbix
Senha: $ZABBIX_DB_PASSWORD

SENHA ROOT DO MYSQL/MARIADB:
Senha: $MYSQL_ROOT_PASSWORD

CREDENCIAIS DO ZABBIX (após configuração web):
Usuário padrão: Admin
Senha padrão: zabbix

COMANDOS ÚTEIS:
- Status Zabbix: systemctl status zabbix-server
- Status MariaDB: systemctl status mariadb
- Status Apache: systemctl status apache2
- Log Zabbix: tail -f /var/log/zabbix/zabbix_server.log
- Ver senhas: cat /root/.zabbix_passwords

ARQUIVOS DE CONFIGURAÇÃO:
- Zabbix Server: /etc/zabbix/zabbix_server.conf
- PHP: /etc/php/$PHP_VERSION/apache2/conf.d/99-zabbix.ini
- Apache Zabbix: /etc/apache2/conf-available/zabbix.conf

============================================
INSTALAÇÃO CONCLUÍDA COM SUCESSO!
============================================
EOF

update_progress 98 "Gerando relatório final..."
update_progress 100 "✅ INSTALAÇÃO COMPLETA!"

new_line
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    🎉 INSTALAÇÃO CONCLUÍDA! 🎉                   ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
new_line

# Exibir informações finais
echo -e "${CYAN}📊 INFORMAÇÕES DO ZABBIX:${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🌐 URL de Acesso: ${CYAN}http://$SERVER_IP/zabbix${NC}"
echo -e "${GREEN}🖥️  IP do Servidor: ${CYAN}$SERVER_IP${NC}"
echo -e "${GREEN}🗄️  Banco de Dados: ${CYAN}MariaDB 10.11${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
new_line

echo -e "${CYAN}🔐 CREDENCIAIS DO ZABBIX (após configuração web):${NC}"
echo -e "${GREEN}   Usuário: ${YELLOW}Admin${NC}"
echo -e "${GREEN}   Senha: ${YELLOW}zabbix${NC}"
new_line

echo -e "${RED}⚠️  ATENÇÃO - CREDENCIAIS IMPORTANTES:${NC}"
echo -e "${YELLOW}   As senhas foram salvas em: /root/.zabbix_passwords${NC}"
echo -e "${YELLOW}   Execute: cat /root/.zabbix_passwords${NC}"
new_line

echo -e "${CYAN}📝 PRÓXIMOS PASSOS:${NC}"
echo -e "   1️⃣  Acesse: ${YELLOW}http://$SERVER_IP/zabbix${NC}"
echo -e "   2️⃣  Clique em \"Next step\" até finalizar"
echo -e "   3️⃣  Na tela do banco de dados, use:"
echo -e "       ${YELLOW}Database: zabbix${NC}"
echo -e "       ${YELLOW}User: zabbix${NC}"
echo -e "       ${YELLOW}Password: $ZABBIX_DB_PASSWORD${NC}"
echo -e "   4️⃣  Login padrão: ${YELLOW}Admin / zabbix${NC}"
new_line

echo -e "${GREEN}✅ Zabbix 7.0 LTS instalado com sucesso!${NC}"
echo -e "${YELLOW}⚠️  Aguarde 1-2 minutos para todos os serviços inicializarem completamente${NC}"
new_line

# Perguntar se quer ver as senhas
read -p "$(echo -e ${CYAN}"Deseja ver as senhas geradas agora? (s/N): "${NC})" -n 1 -r
echo
if [[ $REPLY =~ ^[Ss]$ ]]; then
    cat /root/.zabbix_passwords
    new_line
fi

# Perguntar se quer abrir a URL automaticamente
read -p "$(echo -e ${CYAN}"Deseja abrir a URL no navegador? (s/N): "${NC})" -n 1 -r
echo
if [[ $REPLY =~ ^[Ss]$ ]]; then
    if command -v xdg-open &> /dev/null; then
        xdg-open "http://$SERVER_IP/zabbix" >> $LOG_FILE 2>&1
        echo -e "${GREEN}🌐 Abrindo navegador...${NC}"
    else
        echo -e "${YELLOW}⚠️  Não foi possível abrir o navegador automaticamente${NC}"
        echo -e "${GREEN}   Acesse manualmente: http://$SERVER_IP/zabbix${NC}"
    fi
fi

new_line
echo -e "${BLUE}✨ Script finalizado com sucesso! ✨${NC}"
echo -e "${BLUE}📁 Informações completas em: /root/zabbix_info.txt${NC}"
echo -e "${BLUE}🔑 Senhas em: /root/.zabbix_passwords${NC}"

exit 0
