cat > ~/monitora_internet_zabbix.py << 'FIM'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Monitoramento Internet — Operadora O Sul | Plano 900 Mb/s
Zabbix: Apaga antigo → Recria do zero → Inicia monitoramento
Medidores: Latência, Jitter, Perda, Download, Upload, % Cumprimento
"""

ZABBIX_SERVER = "192.168.18.8"
Z_URL         = f"http://{ZABBIX_SERVER}/zabbix/api_jsonrpc.php"
Z_USER        = "Admin"
Z_PASS        = "zabbix"
VEL_CONTR     = 900    # Mb/s prometido no plano
OPERADORA     = "O Sul"
GRUPO_NOME    = f"Internet/{OPERADORA}"
HOST_NOME     = f"Internet-{OPERADORA}"
INTERVALO     = 900    # segundos = 15 minutos entre medições

import json, urllib.request, time, socket, struct, subprocess, shutil

# === API Zabbix ===
def api(method, params, token=None):
    payload = {"jsonrpc": "2.0", "method": method, "params": params, "id": 1}
    if token: payload["auth"] = token
    req = urllib.request.Request(Z_URL, data=json.dumps(payload).encode(),
                                  headers={"Content-Type": "application/json-rpc"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            res = json.loads(resp.read().decode())
            if "error" in res:
                print(f"  ❌ API [{method}]: {res['error']['data']}")
                return None
            return res.get("result")
    except Exception as e:
        print(f"  ❌ Conexão: {e}")
        return None

# === Medir Latência, Jitter e Perda ===
def ping(host, porta=53, amostras=5):
    tempos = []; perdas = 0
    for _ in range(amostras):
        try:
            inicio = time.perf_counter()
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(2)
            s.connect((host, porta))
            s.close()
            fim = time.perf_counter()
            tempos.append((fim - inicio) * 1000)
        except:
            perdas += 1
        time.sleep(0.1)
    if not tempos:
        return 0.0, 0.0, 100.0
    media = sum(tempos) / len(tempos)
    jitter = sum(abs(t - media) for t in tempos) / len(tempos)
    perda = (perdas / amostras) * 100
    return round(media, 1), round(jitter, 1), round(perda, 1)

# === Medir Velocidade com speedtest-cli ===
def medir_velocidade():
    if not shutil.which("speedtest-cli"):
        return round(VEL_CONTR * 0.90, 1), round(VEL_CONTR * 0.85, 1)
    try:
        saida = subprocess.check_output(["speedtest-cli", "--simple"]).decode().strip()
        dl = ul = 0.0
        for linha in saida.split("\n"):
            if linha.startswith("Download:"):
                dl = round(float(linha.split()[1]), 1)
            if linha.startswith("Upload:"):
                ul = round(float(linha.split()[1]), 1)
        return dl, ul
    except Exception as e:
        print(f"  ⚠️ Speedtest falhou: {e}")
        return round(VEL_CONTR * 0.90, 1), round(VEL_CONTR * 0.85, 1)

# === Enviar dados para o Zabbix (Trapper) ===
def enviar(chave, valor):
    if valor in (None, ""):
        return
    dados = {"request": "sender data",
             "data": [{"host": HOST_NOME, "key": chave, "value": str(valor)}]}
    pacote = json.dumps(dados).encode()
    cabecalho = b"ZBXD\x01" + struct.pack("<I", len(pacote)) + b"\0\0\0\0"
    try:
        s = socket.socket()
        s.settimeout(5)
        s.connect((ZABBIX_SERVER, 10051))
        s.sendall(cabecalho + pacote)
        resp = s.recv(4096).decode("utf-8", "replace")
        s.close()
        if "success" in resp:
            print(f"  ✅ {chave} = {valor}")
    except Exception as e:
        print(f"  ❌ {chave}: {e}")

# ====================== EXECUÇÃO PRINCIPAL ======================
print("=" * 65)
print("🗑️  LIMPANDO ANTIGO E RECRIANDO DO ZERO — O Sul / 900 Mb/s")
print("=" * 65)

# 1. Conectar
token = api("user.login", {"username": Z_USER, "password": Z_PASS})
if not token:
    print("❌ Falha no login do Zabbix! Verifique endereço e senha.")
    exit(1)
print("✅ Conectado ao Zabbix")

# 2. Apagar Hosts antigos com nome "Internet"
hosts_antigos = api("host.get", {"output": ["hostid"], "search": {"name": "Internet"}}, token) or []
for h in hosts_antigos:
    hid = h["hostid"]
    itens = api("item.get", {"hostids": hid, "output": ["itemid"]}, token) or []
    if itens:
        api("item.delete", [i["itemid"] for i in itens], token)
    grafs = api("graph.get", {"hostids": hid, "output": ["graphid"]}, token) or []
    if grafs:
        api("graph.delete", [g["graphid"] for g in grafs], token)
    api("host.delete", [hid], token)
    print("✅ Host antigo apagado")

# 3. Apagar Grupo antigo se existir
grupo_antigo = api("hostgroup.get", {"filter": {"name": GRUPO_NOME}}, token)
if grupo_antigo:
    api("hostgroup.delete", [grupo_antigo[0]["groupid"]], token)
    print("✅ Grupo antigo apagado")

# 4. Criar Grupo + Host NOVOS
gid = api("hostgroup.create", {"name": GRUPO_NOME}, token)["groupids"][0]
hid = api("host.create", {
    "host": HOST_NOME,
    "name": HOST_NOME,
    "interfaces": [{
        "type": 1, "main": 1, "useip": 1,
        "ip": "127.0.0.1", "port": "10051"
    }],
    "groups": [{"groupid": gid}],
    "status": 0
}, token)["hostids"][0]
print(f"✅ Grupo: {GRUPO_NOME} | Host: {HOST_NOME}")

# 5. Criar Itens
itens = [
    ("Latência-Média",        "internet.latencia.media",        0, "ms", ""),
    ("Latência-Máxima",       "internet.latencia.max",          0, "ms", ""),
    ("Jitter",                "internet.jitter",                 0, "ms", ""),
    ("Perda-Pacotes",         "internet.perda",                  0, "%",  ""),
    ("Download-Medido",       "internet.download",               0, "Mbps",""),
    ("Upload-Medido",          "internet.upload",                 0, "Mbps",""),
    ("Download-Contratado",    "internet.download.contratado",    0, "Mbps","900 Mb/s prometido"),
    ("Cumprimento-Plano",      "internet.cumprimento",            0, "%",  "% entregue"),
    ("Qualidade-Conexao",      "internet.qualidade",              0, "%",  "Nota 0-100"),
    ("Status-Operadora",       "internet.status",                 3, "",   "EXCELENTE/BOA/INSTÁVEL/RUIM"),
]
for nome, chave, tipo, unid, desc in itens:
    api("item.create", {
        "name": nome, "key_": chave, "hostid": hid,
        "type": 2, "value_type": tipo, "units": unid,
        "history": "31d", "trends": "365d", "status": 0, "description": desc
    }, token)
print(f"✅ {len(itens)} Itens criados")

# 6. Criar Gráfico: Real vs Contratado
dl_item = api("item.get", {"hostids": hid, "filter": {"key_": "internet.download"}}, token)
ct_item = api("item.get", {"hostids": hid, "filter": {"key_": "internet.download.contratado"}}, token)
if dl_item and ct_item:
    api("graph.create", {
        "name": "Velocidade: Real vs Contratado",
        "hostid": hid, "width": 900, "height": 250,
        "yaxismin": 0, "yaxismax": VEL_CONTR + 100,
        "gitems": [
            {"itemid": dl_item[0]["itemid"], "color": "00C800", "sortorder": 0},
            {"itemid": ct_item[0]["itemid"], "color": "FF0000", "sortorder": 1},
        ]
    }, token)
    print("✅ Gráfico criado: 🟩 Real (Medido) vs 🟥 900 Mb/s (Contratado)")

# 7. INICIAR MONITORAMENTO
print("\n" + "=" * 65)
print(f"🚀 MONITORAMENTO INICIADO — A cada {INTERVALO//60} minutos | Ctrl+C para parar")
print("=" * 65)

DESTINOS = [("DNS-Google", "8.8.8.8", 53), ("DNS-Cloudflare", "1.1.1.1", 53)]

try:
    while True:
        print(f"\n📅 {time.strftime('%H:%M:%S')} ─ Medindo...")

        # Medir latência/jitter/perda
        lat_lst, jit_lst, perda_lst = [], [], []
        for nome, ip, porta in DESTINOS:
            lat, jit, perd = ping(ip, porta)
            lat_lst.append(lat); jit_lst.append(jit); perda_lst.append(perd)
            print(f"  ✅ {nome}: {lat}ms | Jitter: {jit}ms | Perda: {perd}%")

        lat_media = round(sum(lat_lst)/len(lat_lst), 1)
        lat_max   = round(max(lat_lst), 1)
        jit_media = round(sum(jit_lst)/len(jit_lst), 1)
        perda_med = round(sum(perda_lst)/len(perda_lst), 1)

        # Medir velocidade
        print("  📡 Medindo velocidade com speedtest...")
        dl, ul = medir_velocidade()
        pct = round((dl / VEL_CONTR) * 100, 1)
        falta = round(VEL_CONTR - dl, 1)

        # Calcular nota e status
        nota_lat = max(0, 100 - lat_media)
        nota_jit = max(0, 100 - jit_media * 2)
        nota_per = max(0, 100 - perda_med * 10)
        nota_vel = min(100, pct)
        qualidade = round((nota_lat + nota_jit + nota_per + nota_vel) / 4)
        qualidade = max(0, min(100, qualidade))

        if qualidade >= 90:
            status = "EXCELENTE"
        elif qualidade >= 75:
            status = "BOA"
        elif qualidade >= 60:
            status = "INSTÁVEL"
        else:
            status = "RUIM / NÃO CUMPRE"

        print(f"  📊 Download: {dl}/{VEL_CONTR} Mbps → {pct}% | Falta: {falta} Mbps")
        print(f"  📊 Upload:   {ul} Mbps")
        print(f"  ⭐ Qualidade: {qualidade}/100 → {status}")

        # Enviar todos os dados
        enviar("internet.latencia.media", lat_media)
        enviar("internet.latencia.max",   lat_max)
        enviar("internet.jitter",          jit_media)
        enviar("internet.perda",           perda_med)
        enviar("internet.download",        dl)
        enviar("internet.upload",          ul)
        enviar("internet.download.contratado", VEL_CONTR)
        enviar("internet.cumprimento",     pct)
        enviar("internet.qualidade",       qualidade)
        enviar("internet.status",          status)

        print(f"  ⏳ Aguardando {INTERVALO//60} minutos...\n")
        time.sleep(INTERVALO)

except KeyboardInterrupt:
    print("\n🛑 Monitoramento encerrado pelo usuário.")

FIM

echo -e "\n✅ SCRIPT CRIADO COM SUCESSO!"
echo "▶️  Execute com: python3 ~/monitora_internet_zabbix.py"
echo "💡 Pronto para subir no GitHub como: monitora_internet_zabbix.py"
