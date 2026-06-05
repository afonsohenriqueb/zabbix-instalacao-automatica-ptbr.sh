#!/bin/bash

# ==============================================
# Script: Instalação Zabbix 7.0 LTS All-in-One
# Banco: MariaDB (última versão estável)
# Idioma: PT-BR
# Autor: Script Automatizado
# Versão: 3.0 - Corrigido e com Barra de Progresso
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
PHP_VERSION="8.3"
MARIADB_VERSION="10.11"
LOG_FILE="/var/log/zabbix_install.log"
INSTALL_DIR="/tmp/zabbix_install"
TOTAL_STEPS=20  # Quantidade total de etapas para cálculo da barra

# ==============================================
# FUNÇÕES AUXILIARES
# ==============================================

# Função: Exibir barra de progresso visual + porcentagem
update_progress() {
    local current_step=$1
    local message=$2
    # Cálculo da porcentagem
    local percent=$(( current_step * 100 / TOTAL_STEPS ))
    # Cálculo do preenchimento da barra (50 caracteres)
    local filled=$(( percent / 2 ))
    local empty=$(( 50 - filled ))
    
    # Construir barra
    local bar="["
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    bar+="]"

    # Exibir na tela
    echo -ne "\r${CYAN}${bar} ${GREEN}${percent}% ${NC}- ${message}"
    # Registrar no log
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${percent}%] ${message}" >> "$LOG_FILE"
}

# Função: Verificar se houve erro em comando anterior
check_error() {
    if [ $? -ne 0 ]; then
        echo -e "\n${RED}❌ ERRO: $1${NC}"
        echo "[ERRO] $1" >> "$LOG_FILE"
        echo -e "${YELLOW}⚠️  Verifique o log completo em: $LOG_FILE${NC}"
        echo -e "${YELLOW}💡 Dica: Execute 'journalctl -xe' para detalhes do sistema${NC}"
        exit 1
    fi
}

# Função: Pular linha
new_line() {
    echo -e "\n"
}

# ==============================================
# VALIDAÇÕES INICIAIS
# ==============================================

# Verificar execução como root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}❌ Este script deve ser executado como root!${NC}"
   echo -e "${YELLOW}Use: sudo bash $0${NC}"
   exit 1
fi

# Verificar versão do Ubuntu
UBUNTU_VERSION=$(lsb_release -rs)
UBUNTU_CODENAME=$(lsb_release -sc)

if [[ ! "$UBUNTU_VERSION" =~ ^(22.04|24.04)$ ]]; then
    echo -e "${RED}❌ Este script funciona APENAS no Ubuntu 22.04 ou 24.04${NC}"
    echo -e "${YELLOW}Versão detectada: $UBUNTU_VERSION${NC}"
    exit 1
fi

# Limpar tela e exibir banner
clear
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                                                          ║"
echo "║     🚀 INSTALADOR AUTOMÁTICO ZABBIX 7.0 LTS 🚀          ║"
echo "║                                                          ║"
echo "║          All-in-One com MariaDB ${MARIADB_VERSION} + PHP ${PHP_VERSION}          ║"
echo "║                                                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "${YELLOW}📋 Log da instalação: $LOG_FILE${NC}"
echo -e "${YELLOW}⏱️  Tempo estimado: 5-10 minutos${NC}"
echo -e "${YELLOW}🐧 Sistema detectado: Ubuntu $UBUNTU_VERSION ($UBUNTU_CODENAME)${NC}"
new_line
sleep 2

# Preparar ambiente
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR" || exit 1
> "$LOG_FILE"  # Limpar log anterior

# Gerar senhas seguras
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 20 | tr -d "=+/" | cut -c1-20)
ZABBIX_DB_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)

# Salvar senhas com permissão restrita
cat > /root/.zabbix_passwords << EOF
============================================
🔐 SENHAS GERADAS - GUARDE COM SEGURANÇA!
============================================
MySQL Root: ${MYSQL_ROOT_PASSWORD}
--------------------------------------------
Banco Zabbix:
  Usuário: zabbix
  Senha: ${ZABBIX_DB_PASSWORD}
============================================
EOF
chmod 600 /root/.zabbix_passwords
chown root:root /root/.zabbix_passwords

# ==============================================
# ETAPAS DE INSTALAÇÃO (20 ETAPAS TOTAIS)
# ==============================================

# ETAPA 1: Atualizar repositórios
update_progress 1 "Atualizando lista de pacotes do sistema..."
apt-get update -y >> "$LOG_FILE" 2>&1
check_error "Falha ao atualizar repositórios"

# ETAPA 2: Atualizar pacotes
update_progress 2 "Atualizando pacotes instalados..."
apt-get upgrade -y >> "$LOG_FILE" 2>&1
check_error "Falha ao atualizar sistema"

# ETAPA 3: Instalar dependências básicas
update_progress 3 "Instalando ferramentas e dependências..."
apt-get install -y wget curl gnupg apt-transport-https software-properties-common openssl lsb-release >> "$LOG_FILE" 2>&1
check_error "Falha ao instalar dependências"

# ETAPA 4: Configurar repositório MariaDB
update_progress 4 "Adicionando repositório oficial do MariaDB..."
curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | bash -s -- --mariadb-server-version="${MARIADB_VERSION}" >> "$LOG_FILE" 2>&1
check_error "Falha ao configurar repositório MariaDB"

# ETAPA 5: Configurar repositório Zabbix
update_progress 5 "Adicionando repositório oficial do Zabbix..."
wget -q "https://repo.zabbix.com/zabbix/${ZBX_VERSION}/ubuntu/pool/main/z/zabbix-release/zabbix-release_${ZBX_VERSION}-1+ubuntu${UBUNTU_VERSION}_all.deb" >> "$LOG_FILE" 2>&1
dpkg -i "zabbix-release_${ZBX_VERSION}-1+ubuntu${UBUNTU_VERSION}_all.deb" >> "$LOG_FILE" 2>&1
check_error "Falha ao instalar pacote de repositório Zabbix"

# ETAPA 6: Adicionar repositório PHP
update_progress 6 "Adicionando repositório PHP ${PHP_VERSION}..."
add-apt-repository -y ppa:ondrej/php >> "$LOG_FILE" 2>&1
check_error "Falha ao adicionar repositório PHP"

# ETAPA 7: Atualizar repositórios após adições
update_progress 7 "Atualizando repositórios com novas fontes..."
apt-get update -y >> "$LOG_FILE" 2>&1
check_error "Falha na atualização pós-repositórios"

# ETAPA 8: Instalar MariaDB
update_progress 8 "Instalando servidor e cliente MariaDB..."
apt-get install -y mariadb-server mariadb-client >> "$LOG_FILE" 2>&1
check_error "Falha na instalação do MariaDB"

# ETAPA 9: Configurar segurança do MariaDB
update_progress 9 "Aplicando configurações de segurança do banco..."
systemctl start mariadb >> "$LOG_FILE" 2>&1
systemctl enable mariadb >> "$LOG_FILE" 2>&1

mysql --defaults-file=/dev/null << EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
check_error "Falha na configuração segura do MariaDB"

# ETAPA 10: Instalar componentes Zabbix
update_progress 10 "Instalando Zabbix Server, Frontend e Agente..."
apt-get install -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-sql-scripts zabbix-agent >> "$LOG_FILE" 2>&1
check_error "Falha na instalação dos pacotes Zabbix"

# ETAPA 11: Instalar extensões PHP
update_progress 11 "Instalando extensões PHP necessárias..."
apt-get install -y php${PHP_VERSION} php${PHP_VERSION}-mysql php${PHP_VERSION}-gd php${PHP_VERSION}-mbstring php${PHP_VERSION}-bcmath php${PHP_VERSION}-xml php${PHP_VERSION}-ldap php${PHP_VERSION}-cli php${PHP_VERSION}-common >> "$LOG_FILE" 2>&1
check_error "Falha na instalação do PHP e extensões"

# ETAPA 12: Criar banco e usuário Zabbix
update_progress 12 "Criando banco de dados e usuário do Zabbix..."
mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" --default-character-set=utf8mb4 << EOF
CREATE DATABASE IF NOT EXISTS zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY '${ZABBIX_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
FLUSH PRIVILEGES;
EOF
check_error "Falha ao criar estrutura do banco de dados"

# ETAPA 13: Importar estrutura inicial
update_progress 13 "Importando esquema e dados iniciais do Zabbix..."
zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql -uzabbix -p"${ZABBIX_DB_PASSWORD}" --default-character-set=utf8mb4 zabbix >> "$LOG_FILE" 2>&1
check_error "Falha ao importar dados para o banco"

# ETAPA 14: Configurar Zabbix Server
update_progress 14 "Configurando arquivo principal do Zabbix Server..."
if [ -f /etc/zabbix/zabbix_server.conf ]; then
    sed -i "s/^# DBPassword=/DBPassword=${ZABBIX_DB_PASSWORD}/" /etc/zabbix/zabbix_server.conf
    sed -i "s/^# DBHost=localhost/DBHost=localhost/" /etc/zabbix/zabbix_server.conf
    sed -i "s/^# DBPort=3306/DBPort=3306/" /etc/zabbix/zabbix_server.conf
else
    check_error "Arquivo de configuração do Zabbix não encontrado"
fi

# ETAPA 15: Configurar PHP
update_progress 15 "Ajustando configurações PHP (tempo, memória, fuso horário)..."
cat > /etc/php/${PHP_VERSION}/apache2/conf.d/99-zabbix.ini << EOF
max_execution_time = 300
memory_limit = 256M
post_max_size = 16M
upload_max_filesize = 2M
max_input_time = 300
date.timezone = America/Sao_Paulo
EOF

cat > /etc/php/${PHP_VERSION}/cli/conf.d/99-zabbix.ini << EOF
date.timezone = America/Sao_Paulo
EOF
check_error "Falha ao configurar arquivos do PHP"

# ETAPA 16: Configurar Apache
update_progress 16 "Habilitando configurações do Zabbix no Apache..."
if [ -f /etc/zabbix/apache.conf ]; then
    ln -sf /etc/zabbix/apache.conf /etc/apache2/conf-available/zabbix.conf
    a2enconf zabbix > /dev/null 2>&1
    a2enmod rewrite > /dev/null 2>&1
else
    check_error "Arquivo de configuração do Apache para Zabbix não encontrado"
fi

# ETAPA 17: Iniciar e habilitar serviços
update_progress 17 "Iniciando e habilitando serviços para inicialização automática..."
systemctl restart zabbix-server zabbix-agent apache2 mariadb >> "$LOG_FILE" 2>&1
systemctl enable zabbix-server zabbix-agent apache2 mariadb >> "$LOG_FILE" 2>&1
check_error "Falha ao reiniciar serviços"

# Verificação rápida de status
systemctl is-active --quiet zabbix-server || check_error "Zabbix Server não está em execução"
systemctl is-active --quiet mariadb || check_error "MariaDB não está em execução"
systemctl is-active --quiet apache2 || check_error "Apache não está em execução"

# ETAPA 18: Configurar Firewall
update_progress 18 "Configurando regras de firewall (portas necessárias)..."
if command -v ufw &> /dev/null; then
    ufw allow in "Apache Full" >> "$LOG_FILE" 2>&1
    ufw allow 10050/tcp comment 'Zabbix Agent' >> "$LOG_FILE" 2>&1
    ufw allow 10051/tcp comment 'Zabbix Server' >> "$LOG_FILE" 2>&1
    ufw reload >> "$LOG_FILE" 2>&1
fi

# ETAPA 19: Limpeza e permissões
update_progress 19 "Ajustando permissões e limpando arquivos temporários..."
chown -R www-data:www-data /etc/zabbix/ /usr/share/zabbix/
chmod -R 755 /etc/zabbix/ /usr/share/zabbix/
rm -rf "$INSTALL_DIR"

# ETAPA 20: Finalização
update_progress 20 "Gerando relatório final e finalizando..."
new_line

# ==============================================
# EXIBIÇÃO DE RESULTADO FINAL
# ==============================================

# Obter IP do servidor
SERVER_IP=$(hostname -I | awk '{print $1}')
[ -z "$SERVER_IP" ] && SERVER_IP="127.0.0.1"

# Gerar arquivo de informações completas
cat > /root/zabbix_info.txt << EOF
============================================
📊 RELATÓRIO DE INSTALAÇÃO - ZABBIX 7.0 LTS
============================================
✅ Status: INSTALAÇÃO BEM-SUCEDIDA
🗓️ Data: $(date '+%d/%m/%Y %H:%M:%S')
🐧 Sistema: Ubuntu ${UBUNTU_VERSION}
🗄️ Banco: MariaDB ${MARIADB_VERSION}
🐘 PHP: ${PHP_VERSION}

🔗 ACESSO:
URL Web: http://${SERVER_IP}/zabbix
IP Servidor: ${SERVER_IP}

🔐 CREDENCIAIS:
→ Interface Web:
   Usuário: Admin
   Senha: zabbix

→ Banco de Dados:
   Raiz MySQL: ${MYSQL_ROOT_PASSWORD}
   Usuário Zabbix: zabbix
   Senha Zabbix: ${ZABBIX_DB_PASSWORD}

⚙️ ARQUIVOS DE CONFIGURAÇÃO:
- Zabbix Server: /etc/zabbix/zabbix_server.conf
- PHP: /etc/php/${PHP_VERSION}/apache2/conf.d/99-zabbix.ini
- Apache: /etc/apache2/conf-available/zabbix.conf

📋 LOGS:
- Instalação: ${LOG_FILE}
- Zabbix Server: /var/log/zabbix/zabbix_server.log
- Apache: /var/log/apache2/
============================================
EOF

# Exibir mensagem final formatada
new_line
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    🎉 INSTALAÇÃO CONCLUÍDA! 🎉                   ║"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
new_line

echo -e "${CYAN}📌 RESUMO DAS INFORMAÇÕES:${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🌐 Endereço Web: ${CYAN}http://${SERVER_IP}/zabbix${NC}"
echo -e "${GREEN}🖥️  IP do Servidor: ${CYAN}${SERVER_IP}${NC}"
echo -e "${GREEN}🗄️  Banco de Dados: ${CYAN}MariaDB ${MARIADB_VERSION}${NC}"
echo -e "${GREEN}🐘 Versão PHP: ${CYAN}${PHP_VERSION}${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
new_line

echo -e "${CYAN}🔑 ACESSO PADRÃO:${NC}"
echo -e "${GREEN}   Usuário: ${YELLOW}Admin${NC}"
echo -e "${GREEN}   Senha: ${YELLOW}zabbix${NC}"
new_line

echo -e "${RED}⚠️  IMPORTANTE:${NC}"
echo -e "${YELLOW}   • Senhas salvas em: /root/.zabbix_passwords${NC}"
echo -e "${YELLOW}   • Relatório completo: /root/zabbix_info.txt${NC}"
echo -e "${YELLOW}   • Troque a senha padrão após o first login!${NC}"
new_line

echo -e "${CYAN}📝 PRÓXIMOS PASSOS:${NC}"
echo -e "   1️⃣  Acesse: ${YELLOW}http://${SERVER_IP}/zabbix${NC}"
echo -e "   2️⃣  Avance pelos passos de configuração"
echo -e "   3️⃣  No passo do banco, informe:"
echo -e "       ${YELLOW}Servidor: localhost${NC}"
echo -e "       ${YELLOW}Banco: zabbix${NC}"
echo -e "       ${YELLOW}Usuário: zabbix${NC}"
echo -e "       ${YELLOW}Senha: ${ZABBIX_DB_PASSWORD}${NC}"
new_line

# Opções finais para o usuário
read -p "$(echo -e ${CYAN}"Deseja exibir as senhas geradas agora? (s/N): "${NC})" -n 1 -r
echo
if [[ $REPLY =~ ^[Ss]$ ]]; then
    cat /root/.zabbix_passwords
    new_line
fi

read -p "$(echo -e ${CYAN}"Deseja abrir o endereço web no navegador? (s/N): "${NC})" -n 1 -r
echo
if [[ $REPLY =~ ^[Ss]$ ]]; then
    if command -v xdg-open &> /dev/null; then
        xdg-open "http://${SERVER_IP}/zabbix" > /dev/null 2>&1
        echo -e "${GREEN}🌐 Abrindo interface web...${NC}"
    else
        echo -e "${YELLOW}⚠️  Navegador não detectado. Acesse manualmente:${NC}"
        echo -e "${GREEN}   http://${SERVER_IP}/zabbix${NC}"
    fi
fi

new_line
echo -e "${BLUE}✨ Script finalizado com sucesso em $(date '+%H:%M:%S')! ✨${NC}"

exit 0
