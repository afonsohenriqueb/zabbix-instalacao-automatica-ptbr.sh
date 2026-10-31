#!/usr/bin/env bash
# ==============================================================
# Script: Instalador Universal Zabbix (v3.0)
# Versões: 7.0 LTS | 7.4 Estável | 8.0 Pré-release (Estudo)
# Autor: Baseado no conceito original de Afonso Henrique
# ==============================================================
set -euo pipefail

# Cores
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'

log()  { echo -e "${CYAN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[AVISO]${NC} $*"; }
erro() { echo -e "${RED}[ERRO]${NC} $*" >&2; exit 1; }

progress_bar() {
    local step=$1 total=$2 message=$3
    local width=40 percent=$(( (step * 100) / total ))
    local filled=$(( (percent * width) / 100 ))
    local empty=$(( width - filled ))
    echo -ne "\n${CYAN}[Etapa ${step}/${total}] ${message}${NC}\n["
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    echo -e "] ${percent}%\n"
}

# --------------------------------------------------------------
# 0. Verificações iniciais
# --------------------------------------------------------------
[[ $EUID -ne 0 ]] && erro "Execute como root ou com sudo."
command -v systemctl >/dev/null || erro "Systemd não encontrado."
[[ -f /etc/os-release ]] || erro "Sistema não suportado (sem /etc/os-release)."

. /etc/os-release
DISTRO_ID=${ID,,}
DISTRO_VER=${VERSION_ID:-0}

case "$DISTRO_ID" in
    ubuntu|debian|raspbian) PKG_MGR="apt" ;;
    rhel|centos|rocky|almalinux|ol|fedora) PKG_MGR="dnf" ;;
    opensuse*|sles) PKG_MGR="zypper" ;;
    *) erro "Distribuição '${DISTRO_ID}' não suportada oficialmente." ;;
esac

log "Distribuição: ${PRETTY_NAME} (gerenciador: ${PKG_MGR})"

# --------------------------------------------------------------
# 1. Menu interativo
# --------------------------------------------------------------
clear
echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN}        🤖 INSTALADOR UNIVERSAL ZABBIX (v3.0)               ${NC}"
echo -e "${CYAN}============================================================${NC}"

echo -e "\n${YELLOW}O que deseja instalar?${NC}"
echo "  1) Zabbix Server (Banco de dados + Frontend Web)"
echo "  2) Zabbix Proxy  (SQLite ou MySQL/PostgreSQL)"
read -rp "Opção [1-2]: " TIPO_INSTALACAO

echo -e "\n${YELLOW}Versão do Zabbix:${NC}"
echo "  1) Zabbix 7.0 LTS (Recomendado para produção)"
echo "  2) Zabbix 7.4     (Última release estável)"
echo "  3) Zabbix 8.0     (Pré-release para estudo e novidades)"
read -rp "Opção [1-3]: " VERSAO_OPC
case $VERSAO_OPC in
    1) ZBX_VER="7.0" ;;
    2) ZBX_VER="7.4" ;;
    3) ZBX_VER="8.0"
       warn "Você selecionou o Zabbix 8.0, que está em fase de PRÉ-RELEASE (Release Candidate)."
       warn "Ideal para estudar novidades como ClickHouse, JSON nativo, Scatter Plot e CEP."
       warn "NÃO recomendado para ambientes de produção."
       read -rp "Deseja continuar com a instalação de estudo? (s/N): " CONT_80
       [[ "${CONT_80,,}" != "s" ]] && exit 1
       ;;
    *) ZBX_VER="7.0" ;;
esac

# Banco de dados
if [[ "$TIPO_INSTALACAO" == "1" ]]; then
    echo -e "\n${YELLOW}Banco de dados para o Server:${NC}"
    echo "  1) MySQL / MariaDB"
    echo "  2) PostgreSQL (com opção TimescaleDB)"
    read -rp "Opção [1-2]: " DB_OPC
    [[ "$DB_OPC" == "1" ]] && DB_TYPE="mysql" || DB_TYPE="postgresql"
    if [[ "$DB_TYPE" == "postgresql" ]]; then
        read -rp "Habilitar TimescaleDB? (s/N): " TS_RESP
        [[ "${TS_RESP,,}" == "s" ]] && USE_TIMESCALE=1 || USE_TIMESCALE=0
    fi
else
    echo -e "\n${YELLOW}Banco de dados para o Proxy:${NC}"
    echo "  1) SQLite (local, simples)"
    echo "  2) MySQL / MariaDB (remoto)"
    echo "  3) PostgreSQL (remoto)"
    read -rp "Opção [1-3]: " PROXY_DB_OPC
    case $PROXY_DB_OPC in
        1) DB_TYPE="sqlite" ;;
        2) DB_TYPE="mysql" ;;
        3) DB_TYPE="postgresql" ;;
        *) DB_TYPE="sqlite" ;;
    esac
fi

# Verificação de RAM
TOTAL_RAM=$(free -m | awk '/Mem:/ {print $2}')
if [[ "$TOTAL_RAM" -lt 1800 && "$TIPO_INSTALACAO" == "1" ]]; then
    warn "RAM insuficiente (${TOTAL_RAM} MB). O Server pode ficar lento."
    read -rp "Continuar mesmo assim? (s/N): " CONT
    [[ "${CONT,,}" != "s" ]] && exit 1
fi
# Aviso específico para 8.0 (recomendado 4GB+)
if [[ "$ZBX_VER" == "8.0" && "$TOTAL_RAM" -lt 3800 ]]; then
    warn "Para o Zabbix 8.0, a recomendação é de pelo menos 4 GB de RAM (6 GB para produção)."
    warn "Seu sistema tem ${TOTAL_RAM} MB. A instalação prosseguirá, mas o desempenho pode ser limitado."
fi

# --------------------------------------------------------------
# 2. Adicionar repositório oficial
# --------------------------------------------------------------
progress_bar 1 5 "Configurando repositório Zabbix ${ZBX_VER}"

case "$PKG_MGR" in
    apt)
        if [[ "$DISTRO_ID" == "ubuntu" ]]; then
            # Mapear versão do Ubuntu (ex.: 24.04, 26.04)
            REL_PKG="zabbix-release_latest_${ZBX_VER}+ubuntu${DISTRO_VER}_all.deb"
            REL_URL="https://repo.zabbix.com/zabbix/${ZBX_VER}/ubuntu/pool/main/z/zabbix-release/${REL_PKG}"
        else
            REL_PKG="zabbix-release_latest_${ZBX_VER}+debian${DISTRO_VER}_all.deb"
            REL_URL="https://repo.zabbix.com/zabbix/${ZBX_VER}/debian/pool/main/z/zabbix-release/${REL_PKG}"
        fi
        wget -qO "/tmp/${REL_PKG}" "$REL_URL" || erro "Falha ao baixar pacote de repositório."
        dpkg -i "/tmp/${REL_PKG}"
        apt update -qq
        ;;
    dnf)
        REL_PKG="zabbix-release-latest-${ZBX_VER}.el${DISTRO_VER}.noarch.rpm"
        REL_URL="https://repo.zabbix.com/zabbix/${ZBX_VER}/rhel/${DISTRO_VER}/x86_64/${REL_PKG}"
        dnf install -y "$REL_URL" || erro "Falha ao instalar repositório RPM."
        ;;
    zypper)
        zypper --non-interactive addrepo -f "https://repo.zabbix.com/zabbix/${ZBX_VER}/sles/15/x86_64/" zabbix || erro "Falha ao adicionar repositório SUSE."
        zypper --non-interactive --gpg-auto-import-keys refresh
        ;;
esac

# --------------------------------------------------------------
# 3. Instalar pacotes
# --------------------------------------------------------------
progress_bar 2 5 "Instalando pacotes do Zabbix ${ZBX_VER}"

if [[ "$TIPO_INSTALACAO" == "1" ]]; then
    # SERVER
    if [[ "$DB_TYPE" == "mysql" ]]; then
        case "$PKG_MGR" in
            apt) apt install -y zabbix-server-mysql zabbix-frontend-php zabbix-nginx-conf zabbix-sql-scripts zabbix-agent2 mariadb-server ;;
            dnf) dnf install -y zabbix-server-mysql zabbix-web-mysql zabbix-nginx-conf zabbix-sql-scripts zabbix-agent2 mariadb-server ;;
            zypper) zypper install -y zabbix-server-mysql zabbix-web-mysql zabbix-nginx-conf zabbix-sql-scripts zabbix-agent2 mariadb ;;
        esac
    else
        case "$PKG_MGR" in
            apt) apt install -y zabbix-server-pgsql zabbix-frontend-php zabbix-nginx-conf zabbix-sql-scripts zabbix-agent2 postgresql ;;
            dnf) dnf install -y zabbix-server-pgsql zabbix-web-pgsql zabbix-nginx-conf zabbix-sql-scripts zabbix-agent2 postgresql-server ;;
            zypper) zypper install -y zabbix-server-pgsql zabbix-web-pgsql zabbix-nginx-conf zabbix-sql-scripts zabbix-agent2 postgresql-server ;;
        esac
    fi
else
    # PROXY
    case "$PKG_MGR" in
        apt) apt install -y zabbix-proxy-${DB_TYPE} zabbix-sql-scripts zabbix-agent2 ;;
        dnf) dnf install -y zabbix-proxy-${DB_TYPE} zabbix-sql-scripts zabbix-agent2 ;;
        zypper) zypper install -y zabbix-proxy-${DB_TYPE} zabbix-sql-scripts zabbix-agent2 ;;
    esac
fi

# --------------------------------------------------------------
# 4. Configurar banco de dados (Server)
# --------------------------------------------------------------
if [[ "$TIPO_INSTALACAO" == "1" ]]; then
    progress_bar 3 5 "Configurando banco de dados (${DB_TYPE})"

    DB_PASS=$(openssl rand -base64 16)

    if [[ "$DB_TYPE" == "mysql" ]]; then
        systemctl enable --now mariadb
        mysql -uroot <<SQL
CREATE DATABASE zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER 'zabbix'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
SET GLOBAL log_bin_trust_function_creators = 1;
FLUSH PRIVILEGES;
SQL
        # Importar esquema (caminho pode variar ligeiramente na 8.0)
        ZCAT_PATH="/usr/share/zabbix-sql-scripts/mysql/server.sql.gz"
        [[ -f "$ZCAT_PATH" ]] || ZCAT_PATH="/usr/share/zabbix/sql-scripts/mysql/server.sql.gz"
        zcat "$ZCAT_PATH" | mysql --default-character-set=utf8mb4 -uzabbix -p"${DB_PASS}" zabbix

        sed -i "s/^# DBPassword=.*/DBPassword=${DB_PASS}/" /etc/zabbix/zabbix_server.conf
    else
        # PostgreSQL
        systemctl enable --now postgresql
        sudo -u postgres psql <<SQL
CREATE USER zabbix WITH PASSWORD '${DB_PASS}';
CREATE DATABASE zabbix OWNER zabbix;
SQL
        ZCAT_PATH="/usr/share/zabbix-sql-scripts/postgresql/server.sql.gz"
        [[ -f "$ZCAT_PATH" ]] || ZCAT_PATH="/usr/share/zabbix/sql-scripts/postgresql/server.sql.gz"
        zcat "$ZCAT_PATH" | sudo -u zabbix psql zabbix
        sed -i "s/^# DBPassword=.*/DBPassword=${DB_PASS}/" /etc/zabbix/zabbix_server.conf
    fi
fi

# --------------------------------------------------------------
# 5. Configurar frontend e serviços
# --------------------------------------------------------------
if [[ "$TIPO_INSTALACAO" == "1" ]]; then
    progress_bar 4 5 "Ajustando frontend e PHP-FPM"

    NGINX_CONF="/etc/zabbix/nginx.conf"
    if [[ -f "$NGINX_CONF" ]]; then
        sed -i 's/# listen 8080;/listen 8080;/' "$NGINX_CONF"
        sed -i 's/# server_name example.com;/server_name _;/' "$NGINX_CONF"
    fi

    # Ajuste de timezone no PHP (tenta localizar o ini carregado)
    PHP_INI=$(php -i 2>/dev/null | grep -oP 'Loaded Configuration File => \K.*' || true)
    if [[ -n "$PHP_INI" && -f "$PHP_INI" ]]; then
        sed -i 's/;date.timezone =/date.timezone = America\/Sao_Paulo/' "$PHP_INI"
    else
        warn "Arquivo php.ini não localizado automaticamente. Ajuste o timezone manualmente, se necessário."
    fi
fi

# Iniciar serviços
progress_bar 5 5 "Iniciando serviços"
# Tenta iniciar php-fpm com o nome de serviço disponível
for svc in php8.5-fpm php8.4-fpm php8.3-fpm php8.2-fpm php8.1-fpm; do
    if systemctl list-unit-files | grep -q "^${svc}.service"; then
        systemctl restart "$svc" 2>/dev/null || true
        systemctl enable "$svc" 2>/dev/null || true
        break
    fi
done
systemctl restart zabbix-server zabbix-agent2 nginx 2>/dev/null || true
systemctl enable zabbix-server zabbix-agent2 nginx 2>/dev/null || true

# --------------------------------------------------------------
# 6. Finalização
# --------------------------------------------------------------
echo -e "\n${GREEN}============================================================${NC}"
echo -e "${GREEN}          🎉 INSTALAÇÃO CONCLUÍDA! 🎉                      ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "Versão instalada: ${CYAN}Zabbix ${ZBX_VER}${NC}"
echo -e "Acesse o frontend em: ${CYAN}http://<IP_DO_SERVIDOR>:8080${NC}"
echo -e "Usuário padrão: ${YELLOW}Admin${NC} | Senha: ${YELLOW}zabbix${NC}"
echo -e "Altere a senha imediatamente após o primeiro login."
if [[ -n "${DB_PASS:-}" ]]; then
    echo -e "\n${YELLOW}Senha do banco de dados (guarde-a):${NC} ${DB_PASS}"
fi

if [[ "$ZBX_VER" == "8.0" ]]; then
    echo -e "\n${YELLOW}🔬 Nota de estudo (Zabbix 8.0):${NC}"
    echo "- Versão pré-release: ideal para laboratório, não para produção."
    echo "- Explore: suporte a ClickHouse, tipo JSON, widget Scatter plot e CEP."
    echo "- Consulte as notas de upgrade oficiais antes de migrar dados reais."
fi
