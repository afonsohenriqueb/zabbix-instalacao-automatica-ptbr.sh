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
    echo -ne "] ${percent}%\n"
}

# --------------------------
# CABEÇALHO
# --------------------------
clear
echo -e "\033[1;36m============================================================\033[0m"
echo -e "\033[1;36m    HABILITAÇÃO DE ALTA DISPONIBILIDADE - ZABBIX 7.0 LTS   \033[0m"
echo -e "\033[1;36m============================================================\033[0m"
echo -e "\nEste script APENAS habilita o HA no Zabbix Server já instalado e funcional"
echo -e "Não altera configurações existentes, não recria banco nem reinstala o Zabbix.\n"

# --------------------------
# DETECÇÃO DE DADOS
# --------------------------
SERVER_IP=$(hostname -I | awk '{print $1}')
if [[ -z "${SERVER_IP}" ]]; then
    echo -e "\033[1;31m❌ Erro: Não foi possível detectar o IP do servidor!\033[0m"
    exit 1
fi

ZABBIX_CONF="/etc/zabbix/zabbix_server.conf"
if [[ ! -f "${ZABBIX_CONF}" ]]; then
    echo -e "\033[1;31m❌ Erro: Arquivo de configuração do Zabbix não encontrado! Verifique a instalação.\033[0m"
    exit 1
fi

CERT_DIR="/etc/zabbix/pki"
ETCD_CERT_DIR="/etc/etcd/pki"
ETCD_VER="v3.5.15"
TOTAL_STEPS=7

echo -e "📌 IP do servidor: \033[1;33m${SERVER_IP}\033[0m"
echo -e "📁 Configuração encontrada em: \033[1;33m${ZABBIX_CONF}\033[0m"

# --------------------------
# ETAPA 1: Instalar apenas dependências que faltam
# --------------------------
progress_bar 1 ${TOTAL_STEPS} "Verificando e instalando dependências necessárias"
apt update -qq
apt install -y -qq wget curl gnupg2 openssl tar net-tools > /dev/null 2>&1

# --------------------------
# ETAPA 2: Criar diretórios e gerar certificados TLS
# --------------------------
progress_bar 2 ${TOTAL_STEPS} "Gerando certificados TLS seguros"
mkdir -p ${CERT_DIR} ${ETCD_CERT_DIR} /var/lib/etcd /root/etcd-certs
cd /root/etcd-certs

# Gera CA apenas se não existir
if [[ ! -f "ca.key" ]]; then
    openssl genrsa -out ca.key 4096 > /dev/null 2>&1
fi
if [[ ! -f "ca.crt" ]]; then
    openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 -out ca.crt \
        -subj "/C=BR/ST=RioGrandeDoSul/L=PortoAlegre/O=ZabbixHA/OU=ETCD/CN=Zabbix-CA" > /dev/null 2>&1
fi

# Cria configuração do certificado
cat > server.conf <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = req_ext

[dn]
C = BR
ST = RioGrandeDoSul
L = PortoAlegre
O = ZabbixHA
OU = ETCD
CN = etcd-node-1

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
IP.1 = 127.0.0.1
IP.2 = ::1
IP.3 = ${SERVER_IP}
EOF

# Gera certificado do servidor
openssl genrsa -out server.key 2048 > /dev/null 2>&1
openssl req -new -key server.key -out server.csr -config server.conf > /dev/null 2>&1
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
    -out server.crt -days 3650 -sha256 -extensions req_ext -extfile server.conf > /dev/null 2>&1

# Copia certificados
cp ca.crt server.crt server.key ${CERT_DIR}/
cp ca.crt server.crt server.key ${ETCD_CERT_DIR}/

# Ajusta permissões
chown -R root:root ${CERT_DIR} ${ETCD_CERT_DIR}
chmod 600 ${CERT_DIR}/server.key ${ETCD_CERT_DIR}/server.key
chmod 644 ${CERT_DIR}/ca.crt ${CERT_DIR}/server.crt ${ETCD_CERT_DIR}/ca.crt ${ETCD_CERT_DIR}/server.crt

# --------------------------
# ETAPA 3: Instalar ETCD apenas se não estiver presente
# --------------------------
progress_bar 3 ${TOTAL_STEPS} "Verificando e instalando ETCD"
if ! command -v etcd &> /dev/null; then
    wget -q "https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz"
    tar xzf "etcd-${ETCD_VER}-linux-amd64.tar.gz" > /dev/null 2>&1
    mv etcd-${ETCD_VER}-linux-amd64/etcd etcd-${ETCD_VER}-linux-amd64/etcdctl /usr/local/bin/
    rm -rf etcd-${ETCD_VER}-linux-amd64.tar.gz etcd-${ETCD_VER}-linux-amd64
else
    echo -e "ℹ️ ETCD já está instalado, mantendo versão existente"
fi

# --------------------------
# ETAPA 4: Configurar ETCD
# --------------------------
progress_bar 4 ${TOTAL_STEPS} "Configurando serviço ETCD"
cat > /etc/etcd/etcd.conf.yml <<EOF
name: etcd-node-1
data-dir: /var/lib/etcd
listen-client-urls: https://${SERVER_IP}:2379,https://127.0.0.1:2379
listen-peer-urls: https://${SERVER_IP}:2380
advertise-client-urls: https://${SERVER_IP}:2379
initial-advertise-peer-urls: https://${SERVER_IP}:2380
initial-cluster: etcd-node-1=https://${SERVER_IP}:2380
initial-cluster-token: zabbix-ha-cluster
initial-cluster-state: new

client-transport-security:
  cert-file: ${ETCD_CERT_DIR}/server.crt
  key-file: ${ETCD_CERT_DIR}/server.key
  trusted-ca-file: ${ETCD_CERT_DIR}/ca.crt
  client-cert-auth: true

peer-transport-security:
  cert-file: ${ETCD_CERT_DIR}/server.crt
  key-file: ${ETCD_CERT_DIR}/server.key
  trusted-ca-file: ${ETCD_CERT_DIR}/ca.crt
  client-cert-auth: true
EOF

cat > /etc/systemd/system/etcd.service <<EOF
[Unit]
Description=ETCD Cluster para Zabbix HA
After=network.target

[Service]
User=root
Type=notify
ExecStart=/usr/local/bin/etcd --config-file /etc/etcd/etcd.conf.yml
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload > /dev/null 2>&1
systemctl restart etcd > /dev/null 2>&1
systemctl enable etcd > /dev/null 2>&1

# --------------------------
# ETAPA 5: Validar ETCD
# --------------------------
progress_bar 5 ${TOTAL_STEPS} "Validando funcionamento do ETCD"
sleep 4
etcdctl --cacert=${ETCD_CERT_DIR}/ca.crt \
        --cert=${ETCD_CERT_DIR}/server.crt \
        --key=${ETCD_CERT_DIR}/server.key \
        --endpoints=https://${SERVER_IP}:2379 \
        endpoint health > /dev/null 2>&1

# --------------------------
# ETAPA 6: Adicionar configuração HA no Zabbix com sed -i
# --------------------------
progress_bar 6 ${TOTAL_STEPS} "Adicionando configuração de HA no Zabbix"

# Remove linhas antigas do HA se já existirem
sed -i '/^ClusterHA=/d' ${ZABBIX_CONF}
sed -i '/^ETCD_SERVERS=/d' ${ZABBIX_CONF}
sed -i '/^ETCD_CA_FILE=/d' ${ZABBIX_CONF}
sed -i '/^ETCD_CERT_FILE=/d' ${ZABBIX_CONF}
sed -i '/^ETCD_KEY_FILE=/d' ${ZABBIX_CONF}

# Adiciona apenas as novas linhas no FINAL do arquivo
sed -i '$a\\n# ==============================================' ${ZABBIX_CONF}
sed -i '$a# ALTA DISPONIBILIDADE - CONFIGURAÇÃO HA' ${ZABBIX_CONF}
sed -i '$a# ==============================================' ${ZABBIX_CONF}
sed -i "$a ClusterHA=1" ${ZABBIX_CONF}
sed -i "$a ETCD_SERVERS=https://${SERVER_IP}:2379" ${ZABBIX_CONF}
sed -i "$a ETCD_CA_FILE=${CERT_DIR}/ca.crt" ${ZABBIX_CONF}
sed -i "$a ETCD_CERT_FILE=${CERT_DIR}/server.crt" ${ZABBIX_CONF}
sed -i "$a ETCD_KEY_FILE=${CERT_DIR}/server.key" ${ZABBIX_CONF}

chown zabbix:zabbix ${ZABBIX_CONF}
chmod 640 ${ZABBIX_CONF}

# --------------------------
# ETAPA 7: Reiniciar Zabbix e verificar
# --------------------------
progress_bar 7 ${TOTAL_STEPS} "Reiniciando Zabbix e validando"
systemctl restart zabbix-server > /dev/null 2>&1
sleep 6

ZABBIX_STATUS=$(systemctl is-active zabbix-server)
ETCD_STATUS=$(systemctl is-active etcd)

# --------------------------
# RESUMO FINAL
# --------------------------
echo -e "\n\033[1;36m============================================================\033[0m"
echo -e "\033[1;32m✅ HA HABILITADO COM SUCESSO NO ZABBIX SERVER!\033[0m"
echo -e "\033[1;36m============================================================\033[0m"
echo -e "\n📋 Resumo:"
echo -e "   • Status Zabbix Server: \033[1;32m${ZABBIX_STATUS}\033[0m"
echo -e "   • Status ETCD: \033[1;32m${ETCD_STATUS}\033[0m"
echo -e "   • Configuração HA adicionada em: \033[1;33m${ZABBIX_CONF}\033[0m"
echo -e "   • Endpoint ETCD: \033[1;33mhttps://${SERVER_IP}:2379\033[0m"

echo -e "\n🔍 Verificar membros do cluster:"
echo -e "etcdctl --cacert=${CERT_DIR}/ca.crt --cert=${CERT_DIR}/server.crt --key=${CERT_DIR}/server.key --endpoints=https://${SERVER_IP}:2379 member list"

echo -e "\n🔍 Verificar status do HA no Zabbix:"
echo -e "zabbix_server -R ha_status"

echo -e "\n💡 Para visualizar o arquivo com vim:"
echo -e "vim ${ZABBIX_CONF}"
echo -e "\033[1;36m============================================================\033[0m"
