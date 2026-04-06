#!/bin/bash

# ==============================================
# Script: Instalação Zabbix 7.0 LTS All-in-One
# Banco: MariaDB (última versão estável)
# Idioma: PT-BR
# Autor: Script Automatizado
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
MARIADB_VERSION="10.11"
PHP_VERSION="8.3"
LOG_FILE="/var/log/zabbix_install.log"
INSTALL_DIR="/tmp/zabbix_install"
PROGRESS=0

# Função para atualizar progresso
update_progress() {
    PROGRESS=$1
    echo -ne "${CYAN}[${PROGRESS}%] ${GREEN}$2${NC}\n"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${PROGRESS}%] $2" >> $LOG_FILE
}

# Função para mostrar barra de progresso
show_progress_bar() {
    local current=$1
    local total=100
    local width=50
    local percentage=$((current * 100 / total))
    local filled=$((percentage * width / 100))
    local empty=$((width - filled))
    
    printf "\r${CYAN}["
    printf "%${filled}s" | tr ' ' '='
    printf "%${empty}s" | tr ' ' ' '
    printf "] ${percentage}%%${NC}"
}

# Função para verificar erros
check_error() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ ERRO: $1${NC}"
        echo "[ERRO] $1" >> $LOG_FILE
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
echo ""
sleep 3

# Criar diretório temporário
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

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
apt-get install -y wget curl gnupg apt-transport-https software-properties-common >> $LOG_FILE 2>&1
check_error "Falha ao instalar dependências"

update_progress 12 "Instalando repositório MariaDB..."
curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | bash -s -- --mariadb-server-version=$MARIADB_VERSION >> $LOG_FILE 2>&1
check_error "Falha ao configurar repositório MariaDB"

update_progress 15 "Instalando repositório Zabbix..."
wget -q https://repo.zabbix.com/zabbix/$ZBX_VERSION/ubuntu/pool/main/z/zabbix-release/zabbix-release_${ZBX_VERSION}-1+ubuntu$(lsb_release -rs)_all.deb >> $LOG_FILE 2>&1
dpkg -i zabbix-release_${ZBX_VERSION}-1+ubuntu$(lsb_release -rs)_all.deb >> $LOG_FILE 2>&1
check_error "Falha ao configurar repositório Zabbix"

update_progress 18 "Atualizando repositórios após adições..."
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

# Configuração segura do MariaDB
update_progress 30 "Aplicando configurações de segurança do MariaDB..."

mysql -e "UPDATE mysql.user SET Password=PASSWORD('Zabbix@2024') WHERE User='root';" >> $LOG_FILE 2>&1
mysql -e "DELETE FROM mysql.user WHERE User='';" >> $LOG_FILE 2>&1
mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');" >> $LOG_FILE 2>&1
mysql -e "DROP DATABASE IF EXISTS test;" >> $LOG_FILE 2>&1
mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';" >> $LOG_FILE 2>&1
mysql -e "FLUSH PRIVILEGES;" >> $LOG_FILE 2>&1

# ==============================================
# ETAPA 4: Instalação Zabbix Server (35-50%)
# ==============================================
update_progress 35 "Instalando Zabbix Server e componentes..."
apt-get install -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-sql-scripts zabbix-agent >> $LOG_FILE 2>&1
check_error "Falha ao instalar Zabbix"

update_progress 40 "Criando banco de dados Zabbix..."
mysql -e "CREATE DATABASE IF NOT EXISTS zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;" >> $LOG_FILE 2>&1
mysql -e "CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY 'Zabbix@2024';" >> $LOG_FILE 2>&1
mysql -e "GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';" >> $LOG_FILE 2>&1
mysql -e "FLUSH PRIVILEGES;" >> $LOG_FILE 2>&1

update_progress 45 "Importando schema do Zabbix..."
zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql --default-character-set=utf8mb4 -uzabbix -p'Zabbix@2024' zabbix >> $LOG_FILE 2>&1
check_error "Falha ao importar schema do Zabbix"

# ==============================================
# ETAPA 5: Configuração do Zabbix (50-70%)
# ==============================================
update_progress 50 "Configurando Zabbix Server..."
sed -i 's/# DBPassword=/DBPassword=Zabbix@2024/' /etc/zabbix/zabbix_server.conf
sed -i 's/DBPassword=/DBPassword=Zabbix@2024/' /etc/zabbix/zabbix_server.conf
sed -i 's/# DBHost=localhost/DBHost=localhost/' /etc/zabbix/zabbix_server.conf

update_progress 55 "Ajustando configurações de timezone..."
echo "php_value date.timezone America/Sao_Paulo" >> /etc/zabbix/apache.conf

update_progress 60 "Configurando PHP para Zabbix..."
cat > /etc/php/$PHP_VERSION/apache2/conf.d/99-zabbix.ini << EOF
max_execution_time = 300
memory_limit = 256M
post_max_size = 16M
upload_max_filesize = 2M
max_input_time = 300
date.timezone = America/Sao_Paulo
EOF

# ==============================================
# ETAPA 6: Inicialização dos Serviços (70-85%)
# ==============================================
update_progress 70 "Iniciando serviços..."
systemctl restart zabbix-server zabbix-agent apache2 >> $LOG_FILE 2>&1
systemctl enable zabbix-server zabbix-agent apache2 >> $LOG_FILE 2>&1

update_progress 75 "Verificando status dos serviços..."
sleep 2

# Verificar se serviços estão rodando
if systemctl is-active --quiet zabbix-server; then
    update_progress 80 "✅ Zabbix Server está rodando"
else
    echo -e "${RED}❌ Zabbix Server não iniciou corretamente${NC}"
    systemctl status zabbix-server >> $LOG_FILE
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
Senha: Zabbix@2024

CREDENCIAIS DO ZABBIX (após configuração web):
Usuário padrão: Admin
Senha padrão: zabbix

COMANDOS ÚTEIS:
- Status Zabbix: systemctl status zabbix-server
- Status MariaDB: systemctl status mariadb
- Status Apache: systemctl status apache2
- Log Zabbix: tail -f /var/log/zabbix/zabbix_server.log

ARQUIVOS DE CONFIGURAÇÃO:
- Zabbix Server: /etc/zabbix/zabbix_server.conf
- PHP: /etc/php/$PHP_VERSION/apache2/conf.d/99-zabbix.ini
- Apache: /etc/zabbix/apache.conf

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
echo -e "${GREEN}🗄️  Banco de Dados: ${CYAN}MariaDB $MARIADB_VERSION${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
new_line

echo -e "${CYAN}🔐 CREDENCIAIS DO ZABBIX (após configuração web):${NC}"
echo -e "${GREEN}   Usuário: ${YELLOW}Admin${NC}"
echo -e "${GREEN}   Senha: ${YELLOW}zabbix${NC}"
new_line

echo -e "${CYAN}📝 INFORMAÇÕES IMPORTANTES:${NC}"
echo -e "   • Acesse o link acima para completar a configuração via web"
echo -e "   • Durante a configuração web, use as credenciais do banco:"
echo -e "     ${YELLOW}Usuário: zabbix | Senha: Zabbix@2024${NC}"
echo -e "   • Todas as informações foram salvas em: ${YELLOW}/root/zabbix_info.txt${NC}"
echo -e "   • Log completo da instalação: ${YELLOW}$LOG_FILE${NC}"
new_line

echo -e "${GREEN}✅ Zabbix 7.0 LTS instalado com sucesso!${NC}"
echo -e "${YELLOW}⚠️  Aguarde 1-2 minutos para todos os serviços inicializarem completamente${NC}"
new_line

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

exit 0
