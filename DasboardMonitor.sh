#!/usr/bin/env bash

# ==============================================================================
# VERIFICAÇÃO DE PRIVILÉGIOS (SUDO/ROOT)
# ==============================================================================
if [ "$EUID" -ne 0 ]; then 
    echo "Este script precisa ser executado como root ou via sudo."
    echo "Use: sudo $0"
    exit 1
fi

# Ajusta o PATH para garantir acesso aos comandos em /sbin e /usr/sbin
export PATH="$PATH:/sbin:/usr/sbin:/usr/local/sbin"

# ==============================================================================
# ESTRUTURA DE DIRETÓRIOS E ARQUIVOS DE CONFIGURAÇÃO
# ==============================================================================
DIR_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR_CONFIG="$DIR_SCRIPT/config"
ARQUIVO_CONF_ALERTAS="$DIR_CONFIG/alertas.conf"
ARQUIVO_CONF_DEPENDENCIAS="$DIR_CONFIG/dependencias.conf"
ARQUIVO_CONF_SERVICOS="$DIR_CONFIG/servicos.conf"

# Garante a existência do diretório de configurações
mkdir -p "$DIR_CONFIG"

# FUNÇÃO: Inicializa os arquivos de configuração padrão caso não existam
INICIALIZAR_CONFIGURACOES() {
    # 1. Alertas
    if [ ! -f "$ARQUIVO_CONF_ALERTAS" ]; then
        cat <<EOF > "$ARQUIVO_CONF_ALERTAS"
LIMITE_DISCO=70
LIMITE_RAM=80
LIMITE_CPU=85
EOF
    fi

    # 2. Dependências (Formato "comando:pacote")
    if [ ! -f "$ARQUIVO_CONF_DEPENDENCIAS" ]; then
        cat <<'EOF' > "$ARQUIVO_CONF_DEPENDENCIAS"
DEPENDENCIAS_CONFIG=(
    "column:bsdmainutils"
    "mpstat:sysstat"
    "ufw:ufw"
    "fail2ban-client:fail2ban"
    "curl:curl"
    "dig:bind9-dnsutils"
)
EOF
    fi

    # 3. Serviços do Systemd
    if [ ! -f "$ARQUIVO_CONF_SERVICOS" ]; then
        cat <<'EOF' > "$ARQUIVO_CONF_SERVICOS"
SERVICOS_CONFIG=(
    "ssh"
    "cron"
    "networking"
    "docker"
    "apache2"
    "nginx"
    "ufw"
)
EOF
    fi
}

INICIALIZAR_CONFIGURACOES

# Carrega os arquivos de configuração
source "$ARQUIVO_CONF_ALERTAS"
source "$ARQUIVO_CONF_DEPENDENCIAS"
source "$ARQUIVO_CONF_SERVICOS"

# ==============================================================================
# FUNÇÕES DE FORMATAÇÃO E INTERFACE
# ==============================================================================
BARRA() {
    local CH="="
    local LARG=$(tput cols 2>/dev/null)
    local LARG=$(((LARG/2)-3))

    case $# in
        0)
            LARG=$(tput cols 2>/dev/null || echo 75)
            ;;
        1)
            if [[ "$1" =~ ^[0-9]+$ ]]; then
                LARG="$1"
            else
                CH="$1"
            fi
            ;;
        2)
            CH="$1"
            LARG="$2"
            ;;
    esac

    printf '%*s\n' "$LARG" '' | tr ' ' "$CH"
}

CENTER() {
    local TEXTO="$1"
    local LARG=75
    local LEN=${#TEXTO}
    local PAD=$(( (LARG - LEN) / 2 ))
    [ "$PAD" -lt 0 ] && PAD=0
    printf '%*s%s\n' "$PAD" '' "$TEXTO"
}

# ==============================================================================
# VERIFICAÇÃO E INSTALAÇÃO DE DEPENDÊNCIAS
# ==============================================================================
CHECAR_DEPENDENCIAS() {
    local PACOTES_PARA_INSTALAR=()
    local ITEM CMD PKG

    echo "Verificando dependências do sistema..."

    for ITEM in "${DEPENDENCIAS_CONFIG[@]}"; do
        IFS=":" read -r CMD PKG <<< "$ITEM"
        if ! command -v "$CMD" &>/dev/null; then
            if [[ ! " ${PACOTES_PARA_INSTALAR[*]} " =~ " ${PKG} " ]]; then
                PACOTES_PARA_INSTALAR+=("$PKG")
            fi
        fi
    done

    if [ ${#PACOTES_PARA_INSTALAR[@]} -gt 0 ]; then
        echo "-------------------------------------------------------------------"
        echo " Faltam pacotes necessários: ${PACOTES_PARA_INSTALAR[*]}"
        echo " Instalando dependências automaticamente..."
        echo "-------------------------------------------------------------------"
        
        apt update -qq 2>/dev/null
        apt install -y "${PACOTES_PARA_INSTALAR[@]}"

        echo "-------------------------------------------------------------------"
        echo " [OK] Todas as dependências foram instaladas com sucesso!"
        echo "-------------------------------------------------------------------"
        sleep 2
    fi
}

CHECAR_DEPENDENCIAS

# ==============================================================================
# FUNÇÕES DE COLETA DE DADOS E CONFIGURAÇÃO
# ==============================================================================
COLETAR_INFO() {
    # Informações Básicas e Identificação
    HOSTNAME_ATUAL=$(hostname 2>/dev/null)
    HOSTNAME_ATUAL="${HOSTNAME_ATUAL:-N/A}"
    DATA_ATUAL=$(date '+%d/%m/%Y %H:%M')
    SISTEMA=$(uname -o)
    TEMPO_LIGADO=$(uptime -p | sed 's/^up //')

    # Distro
    if command -v lsb_release &>/dev/null; then
        DISTRO=$(lsb_release -ds 2>/dev/null)
    else
        DISTRO=$(grep "PRETTY_NAME" /etc/os-release 2>/dev/null | cut -d '"' -f2)
    fi
    DISTRO="${DISTRO:-N/A}"

    # Memória RAM
    LINHA_MEMORIA=$(free -h | grep "Mem.")
    MEMORIA_TOTAL=$(awk '{print $2}' <<< "$LINHA_MEMORIA")
    MEMORIA_USADA=$(awk '{print $3}' <<< "$LINHA_MEMORIA")
    MEMORIA_LIVRE=$(awk '{print $4}' <<< "$LINHA_MEMORIA")
    MEMORIA_CACHE=$(awk '{print $6}' <<< "$LINHA_MEMORIA")
    MEMORIA_DISPONIVEL=$(awk '{print $7}' <<< "$LINHA_MEMORIA")

    PCT_RAM_USADA=$(free | grep "Mem." | awk '{printf "%d", $3/$2 * 100}')

    # Memória SWAP
    LINHA_SWAP=$(free -h | grep "Swap")
    SWAP_TOTAL=$(awk '{print $2}' <<< "$LINHA_SWAP")
    SWAP_USADA=$(awk '{print $3}' <<< "$LINHA_SWAP")

    # Disco e Inodes
    LINHA_DISCO=$(df -h / | awk 'NR==2')
    DISCO_TOTAL=$(awk '{print $2}' <<< "$LINHA_DISCO")
    DISCO_USADA=$(awk '{print $3}' <<< "$LINHA_DISCO")
    DISCO_LIVRE=$(awk '{print $4}' <<< "$LINHA_DISCO")
    DISCO_PORCENTAGEM=$(awk '{print $5}' <<< "$LINHA_DISCO")

    PCT_DISCO_USADO=$(sed 's/%//' <<< "$DISCO_PORCENTAGEM")
    INODES=$(df -i / | awk 'NR==2 {print $5}')

    # CPU
    LINHA_CPU=$(mpstat 1 1 2>/dev/null | awk '/Average:|Média:/')
    if [ -n "$LINHA_CPU" ]; then
        CPU_SYS=$(awk '{print $5}' <<< "$LINHA_CPU")
        CPU_IOWAIT=$(awk '{print $6}' <<< "$LINHA_CPU")
        CPU_IDLE=$(awk '{print $12}' <<< "$LINHA_CPU")
        PCT_CPU_USADA=$(awk '{printf "%d", 100 - $12}' <<< "$LINHA_CPU")
    else
        CPU_SYS="0"
        CPU_IOWAIT="0"
        CPU_IDLE="100"
        PCT_CPU_USADA=0
    fi

    # Rede e Conexões
    IP_LOCAL=$(hostname -I 2>/dev/null | awk '{print $1}')
    IP_LOCAL="${IP_LOCAL:-N/A}"
    IP_PUBLICO=$(curl -4 -s --max-time 2 ifconfig.me 2>/dev/null)
    IP_PUBLICO="${IP_PUBLICO:-Indisponivel:10}"
    IP_PUBLICO="${IP_PUBLICO::15}"
    CONEXOES_ATIVAS=$(ss -tun 2>/dev/null | tail -n +2 | wc -l)
    PORTAS_ESCUTA=$(ss -lntu 2>/dev/null | tail -n +2 | wc -l)

    # Segurança e Usuários
    USUARIOS_LOGADOS=$(who 2>/dev/null | wc -l)

    if command -v ufw &>/dev/null; then
        if ufw status 2>/dev/null | grep -qi "active"; then
            UFW_STATUS="ATIVO"
        else
            UFW_STATUS="INATIVO"
        fi
    else
        UFW_STATUS="N/D"
    fi

    TENTATIVAS_BLOQUEADAS=0
    if command -v fail2ban-client &>/dev/null && systemctl is-active --quiet fail2ban 2>/dev/null; then
        FAIL2BAN_STATUS="ATIVO"
        TOTAL_BANIDOS=0
        local JAIL BANIDOS
        for JAIL in $(fail2ban-client status 2>/dev/null | awk -F: '/Jail list/ {gsub(/,/, "", $2); print $2}'); do
            BANIDOS=$(fail2ban-client status "$JAIL" 2>/dev/null | awk -F: '/Currently banned/ {gsub(/ /, "", $2); print $2}')
            [[ "$BANIDOS" =~ ^[0-9]+$ ]] && TOTAL_BANIDOS=$((TOTAL_BANIDOS + BANIDOS))
        done
        TENTATIVAS_BLOQUEADAS=$TOTAL_BANIDOS
    else
        FAIL2BAN_STATUS="INATIVO"
    fi

    # --------------------------------------------------------------------------
    # MÉTRICAS AVANÇADAS DE SERVIDOR
    # --------------------------------------------------------------------------
    # Latência do DNS
    if command -v dig &>/dev/null; then
        DNS_MS=$(dig +time=1 +tries=1 google.com 2>/dev/null | awk '/Query time:/ {print $4}')
        if [ -n "$DNS_MS" ]; then
            DNS_STATUS="${DNS_MS} ms"
        else
            DNS_STATUS="Falha"
        fi
    else
        DNS_STATUS="Sem dig"
    fi

    # Conntrack (Connection Tracking do Kernel)
    if [ -f /proc/sys/net/netfilter/nf_conntrack_count ]; then
        CONN_ATUAIS=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null)
        CONN_MAX=$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null)
        if [ -n "$CONN_MAX" ] && [ "$CONN_MAX" -gt 0 ]; then
            CONN_PCT=$(( CONN_ATUAIS * 100 / CONN_MAX ))
            CONNTRACK_INFO="${CONN_ATUAIS}/${CONN_MAX} (${CONN_PCT}%)"
        else
            CONNTRACK_INFO="N/A"
        fi
    else
        CONNTRACK_INFO="N/A"
    fi

    # File Descriptors (Manipuladores de Arquivos Abertos)
    FD_ALLOCATED=$(sysctl -n fs.file-nr 2>/dev/null | awk '{print $1}')
    FD_MAX=$(sysctl -n fs.file-nr 2>/dev/null | awk '{print $3}')
    if [ -n "$FD_MAX" ] && [ "$FD_MAX" -gt 0 ]; then
        FD_PCT=$(( FD_ALLOCATED * 100 / FD_MAX ))
        FD_INFO="${FD_ALLOCATED} (${FD_PCT}%)"
    else
        FD_INFO="N/A"
    fi

    # Processos Zumbis
    ZOMBIES=$(ps aux | awk '{if ($8 ~ /Z/) print $0}' | wc -l)
    if [ "$ZOMBIES" -gt 0 ]; then
        ZOMBIE_STATUS="● ${ZOMBIES} ALERTA"
    else
        ZOMBIE_STATUS="○ 0 (OK)"
    fi
    
    # Tamanho ocupado pelas pastas temporárias e de logs
    TAMANHO_TMP=$(du -sh /tmp 2>/dev/null | awk '{print $1}')
    TAMANHO_LOGS=$(du -sh /var/log 2>/dev/null | awk '{print $1}')
}

SALVAR_ALTERACOES() {
    cat <<EOF > "$ARQUIVO_CONF_ALERTAS"
LIMITE_DISCO=$LIMITE_DISCO
LIMITE_RAM=$LIMITE_RAM
LIMITE_CPU=$LIMITE_CPU
EOF
}

# ==============================================================================
# COMPONENTES VISUAIS DA TELA PRINCIPAL
# ==============================================================================
BLOCO_SERVIDOR_AVANCADO() {
    echo "[ MÁQUINA & RECURSOS DE INFRAESTRUTURA ]"
    {
        echo " Latência DNS : ${DNS_STATUS:-N/A}; Conntrack (Kernel): ${CONNTRACK_INFO:-N/A}"
        echo " Arquivos/FDs : ${FD_INFO:-N/A}; Proc. Zumbis     : ${ZOMBIE_STATUS:-N/A}"
        echo " Espaço /tmp  : ${TAMANHO_TMP:-0B}; Espaço /var/log  : ${TAMANHO_LOGS:-0B}"
    } | column -t -s ";" -o "   |   "

    BARRA "-"
}

DASHBOARD() {
    {
        echo "[ INFORMACOES DO SISTEMA ]"
        echo " SISTEMA: ${DISTRO:-N/A};HOST: ${HOSTNAME_ATUAL}"
        echo " UPTIME: ${TEMPO_LIGADO:-N/A};DATA: ${DATA_ATUAL};"
    } | column -t -s ";" -o "    "

    BARRA "-"
    
    {
        echo "[ CPU ];[ RAM ]"
        echo " Uso Total: ${PCT_CPU_USADA:-0}%; RAM Usada : ${MEMORIA_USADA:-N/A} (${PCT_RAM_USADA:-0}%)"
        echo " Sistema  : ${CPU_SYS:-0}%; RAM Livre : ${MEMORIA_LIVRE:-N/A}"
        echo " I/O Wait : ${CPU_IOWAIT:-0}%; RAM Total : ${MEMORIA_TOTAL:-N/A}"
        echo " Ociosa   : ${CPU_IDLE:-0}%; SWAP Usada: ${SWAP_USADA:-N/A} de ${SWAP_TOTAL:-N/A}"
    } | column -t -s ";" -o "             |              "
    
    BARRA "-"
    
    [ "${UFW_STATUS:-INATIVO}" = "ATIVO" ] && UFW_EXIBICAO="● ATIVO" || UFW_EXIBICAO="● INATIVO"
    [ "${FAIL2BAN_STATUS:-INATIVO}" = "ATIVO" ] && FAIL2BAN_EXIBICAO="● ATIVO" || FAIL2BAN_EXIBICAO="● INATIVO"

    {
        echo " [ DISCO ];[ REDE ];[ SEGURANÇA ]"
        echo "  Total: ${DISCO_TOTAL:-N/A}; IP Local: ${IP_LOCAL:-N/A}; UFW: ${UFW_EXIBICAO}"
        echo "  Usado: ${DISCO_USADA:-N/A}; IP Público: ${IP_PUBLICO:-N/A:10}; Fail2Ban: ${FAIL2BAN_EXIBICAO}"
        echo "  Livre: ${DISCO_LIVRE:-N/A}; Conexões: ${CONEXOES_ATIVAS:-0}; Usuários: ${USUARIOS_LOGADOS}"
        echo "  Inodes: ${INODES:-N/A}; Portas em escuta: ${PORTAS_ESCUTA:-0}; Bloqueios: ${TENTATIVAS_BLOQUEADAS}"
    } | column -t -s ";" -o "   |   "

    BARRA "-"

    BLOCO_SERVIDOR_AVANCADO
}

BLOCO_SERVICOS_DOCKER() {
    echo "[ STATUS DOS SERVIÇOS ]"

    SERVICOS=("${SERVICOS_CONFIG[@]:0:8}")
    TOTAL=${#SERVICOS[@]}
    
    for (( i=0; i<TOTAL; i+=2 )); do
        S1="${SERVICOS[i]}"
        if systemctl is-active --quiet "$S1" 2>/dev/null; then
            STATUS1="$S1: ● Ativo"
        else
            STATUS1="$S1: ○ Inativo"
        fi

        STATUS2=""
        if (( i+1 < TOTAL )); then
            S2="${SERVICOS[i+1]}"
            if systemctl is-active --quiet "$S2" 2>/dev/null; then
                STATUS2="$S2: ● Ativo"
            else
                STATUS2="$S2: ○ Inativo"
            fi
        fi

        printf "  %-35s %-35s\n" "$STATUS1" "$STATUS2"
    done

    BARRA "-"

    echo "[ CONTAINERS DOCKER ]"
    if command -v docker >/dev/null 2>&1; then
        containers=$(docker ps --format "  {{.Names}}: {{.Status}}" 2>/dev/null | head -n 3)
        if [ -n "$containers" ]; then
             echo "$containers"
        else
             echo "  Nenhum container ativo"
        fi
    else
        echo "  Docker não instalado"
    fi
    }

BLOCO_MENUS() {
    BARRA "="
    {
        echo " MENU PRINCIPAL ; MENU PACOTES"
        echo " [1] Diagnóstico ; [5] Listar Instalados"
        echo " [2] Logs Críticos ; [6] Buscar/Remover APT"
        echo " [3] Redes e Usuarios ; [7] Buscar/Remover Flatpak"
        echo " [4] Atualizações ; [8] Limpar Órfãos"
        echo " [0] Sair ; [9] Config. Limites"
    } | column -t -s ";" -o "  |  "
    BARRA "-"
}

BLOCO_USO_DISCO() {
    echo "[ MAIORES DIRETÓRIOS EM DISCO ]"
    du -hx --max-depth=3 /home 2>/dev/null | sort -rh | head -n 5 | awk '{printf " %-5s %s\n", $1, $2}'
}

ALERTAS() {
    BARRA
    local ALERTA_ENCONTRADO=0

    if [ "$PCT_DISCO_USADO" -gt "$LIMITE_DISCO" ]; then
        echo " [ ALERTA DISCO ] Uso em $PCT_DISCO_USADO% (Limite: $LIMITE_DISCO%)"
        ALERTA_ENCONTRADO=1
    fi

    if [ "$PCT_RAM_USADA" -gt "$LIMITE_RAM" ]; then
        echo " [ ALERTA RAM ] Uso em $PCT_RAM_USADA% (Limite: $LIMITE_RAM%)"
        ALERTA_ENCONTRADO=1
    fi

    if [ "$PCT_CPU_USADA" -gt "$LIMITE_CPU" ]; then
        echo " [ ALERTA CPU ] Uso em $PCT_CPU_USADA% (Limite: $LIMITE_CPU%)"
        ALERTA_ENCONTRADO=1
    fi

    if [ "$ALERTA_ENCONTRADO" -eq 0 ]; then
        echo " [ OK ] Nenhum alerta. Sistema operando dentro dos limites."
    fi

    BARRA
}

CONSUMO_RAM() {
    echo "[ TOP 5 PROCESSOS - RAM ]"
    echo "  PID      USUÁRIO      %MEM     COMANDO"
    BARRA "-"
    ps -eo pid,user,%mem,comm --sort=-%mem | head -n 6 | tail -n 5 | awk '{printf "  %-8s %-12s %-8s %s\n", $1, $2, $3, $4}'
}

CONSUMO_CPU() {
    echo "[ TOP 5 PROCESSOS - CPU ]"
    echo "  PID      USUÁRIO      %CPU     COMANDO"
    BARRA "-"
    ps -eo pid,user,%cpu,comm --sort=-%cpu | head -n 6 | tail -n 5 | awk '{printf "  %-8s %-12s %-8s %s\n", $1, $2, $3, $4}'
}

BLOCO_PROCESSOS_LADO_A_LADO() {
    paste -d '@@' <(CONSUMO_RAM) <(CONSUMO_CPU) | column -t -s "@@" -o " | "
}

LADO_ESQUERDO() {
    DASHBOARD
}

LADO_DIREITO() {
    BLOCO_SERVICOS_DOCKER
    BLOCO_MENUS
    BLOCO_USO_DISCO
}

TELA() {
    BARRA
    printf '%*s%s\n' "$(( (${COLUMNS:-$(tput cols 2>/dev/null || echo 130)} - 26) / 2 ))" '' "DASHBOARD DE MONITORAMENTO"
    BARRA
    
    # Topo: Dashboard (Esq) vs Serviços/Docker/Menus/Disco (Direita)
    paste -d '@@' <(LADO_ESQUERDO) <(LADO_DIREITO) | column -t -s "@@" -o " | "
    
    # Meio: Consumo de RAM e CPU
    BARRA
    BLOCO_PROCESSOS_LADO_A_LADO
    
    # Rodapé: Alertas de Limite
    ALERTAS
}

# ==============================================================================
# FUNÇÕES DE DIAGNÓSTICO DETALHADO E EXPORTAÇÃO
# ==============================================================================
GERAR_TEXTO_DIAGNOSTICO() {
    local DATA_LOG=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Coleta de pacotes instalados
    local PACOTES_APT=$(dpkg --list 2>/dev/null | grep -c '^ii')
    local PACOTES_FLATPAK=0
    command -v flatpak &>/dev/null && PACOTES_FLATPAK=$(flatpak list 2>/dev/null | wc -l)
    local PACOTES_SNAP=0
    command -v snap &>/dev/null && PACOTES_SNAP=$(snap list 2>/dev/null | tail -n +2 | wc -l)

    local CPU_MODELO=$(lscpu 2>/dev/null | grep "Nome do modelo\|Model name" | cut -d ':' -f2 | sed 's/^ *//')
    CPU_MODELO="${CPU_MODELO:-N/A}"

    echo "==============================================================================="
    echo "                 RELATÓRIO DE DIAGNÓSTICO COMPLETO DO SISTEMA                  "
    echo "==============================================================================="
    echo " Data/Hora de Geração : $DATA_LOG"
    echo " Hostname              : $HOSTNAME_ATUAL"
    echo " Sistema Operacional   : $SISTEMA ($DISTRO)"
    echo " Kernel / Arquitetura  : $(uname -r) ($(uname -m))"
    echo " Uptime (Tempo Ligado) : $TEMPO_LIGADO"
    echo " Shell / Terminal      : ${SHELL:-N/A} / ${TERM:-N/A}"
    echo " Pacotes Instalados    : APT: $PACOTES_APT | Flatpak: $PACOTES_FLATPAK | Snap: $PACOTES_SNAP"
    echo "==============================================================================="
    echo ""
    echo "[ 1. RECURSOS DE INFRAESTRUTURA & REDE ]"
    echo "-------------------------------------------------------------------------------"
    echo " Endereço IP Local     : $IP_LOCAL"
    echo " Endereço IP Público   : $IP_PUBLICO"
    echo " Latência DNS (google) : $DNS_STATUS"
    echo " Conntrack (Kernel)    : $CONNTRACK_INFO"
    echo " File Descriptors (FD) : $FD_INFO"
    echo " Processos Zumbis      : $ZOMBIE_STATUS"
    echo " Conexões Ativas (SS)  : $CONEXOES_ATIVAS"
    echo " Portas em Escuta      : $PORTAS_ESCUTA"
    echo " Espaço Ocupado /tmp   : $TAMANHO_TMP"
    echo " Espaço Ocupado /logs  : $TAMANHO_LOGS"
    echo ""
    echo "[ 2. PROCESSADOR (CPU) ]"
    echo "-------------------------------------------------------------------------------"
    echo " Modelo da CPU         : $CPU_MODELO"
    echo " Cores / Núcleos       : $(nproc)"
    echo " Uso Total da CPU      : ${PCT_CPU_USADA}% (Sistema: ${CPU_SYS}%, I/O Wait: ${CPU_IOWAIT}%, Idle: ${CPU_IDLE}%)"
    echo ""
    echo " --- Uso Detalhado por Núcleo ---"
    mpstat -P ALL 1 1 2>/dev/null | grep "Média:\|Average:" | grep -v "CPU" | grep -v "all" | awk '{printf "   Core %-2s -> Usuário: %6s | Sistema: %6s | I/O Wait: %6s | Ocioso: %6s\n", $2, $3"%", $5"%", $6"%", $12"%"}'
    echo ""
    echo "[ 3. MEMÓRIA RAM E SWAP ]"
    echo "-------------------------------------------------------------------------------"
    echo " RAM Total            : $MEMORIA_TOTAL"
    echo " RAM Usada            : $MEMORIA_USADA (${PCT_RAM_USADA}%)"
    echo " RAM Livre            : $MEMORIA_LIVRE"
    echo " RAM Cache            : $MEMORIA_CACHE"
    echo " RAM Disponível       : $MEMORIA_DISPONIVEL"
    echo " SWAP Usada / Total   : $SWAP_USADA / $SWAP_TOTAL"
    echo ""
    echo "[ 4. ARMAZENAMENTO E PARTIÇÕES ]"
    echo "-------------------------------------------------------------------------------"
    echo " Raiz (/) Uso Total   : $DISCO_TOTAL | Usado: $DISCO_USADA ($PCT_DISCO_USADO%) | Livre: $DISCO_LIVRE"
    echo " Inodes Utilizados    : $INODES"
    echo ""
    echo " --- Dispositivos de Bloco (lsblk) ---"
    lsblk -e7 -o NAME,SIZE,FSTYPE,MOUNTPOINT 2>/dev/null
    echo ""
    echo " --- Uso de Espaço em Disco (df) ---"
    df -h -x tmpfs -x devtmpfs 2>/dev/null
    echo ""
    echo " --- Maiores Diretórios em Disco (/var, /home) ---"
    du -hx --max-depth=5 /var /home 2>/dev/null | sort -rh | head -n 10 | awk '{printf "   %-8s %s\n", $1, $2}'
    echo ""
    echo "[ 5. SEGURANÇA E USUÁRIOS ]"
    echo "-------------------------------------------------------------------------------"
    echo " Status Firewall (UFW): $UFW_STATUS"
    echo " Status Fail2ban       : $FAIL2BAN_STATUS"
    echo " Total IPs Banidos     : $TENTATIVAS_BLOQUEADAS"
    echo " Usuários Logados Agora: $USUARIOS_LOGADOS"
    echo ""
    echo "[ 6. STATUS DOS SERVIÇOS DO SYSTEMD ]"
    echo "-------------------------------------------------------------------------------"
    for SERVICO in "${SERVICOS_CONFIG[@]}"; do
        if systemctl is-active --quiet "$SERVICO" 2>/dev/null; then
            STATUS_S="[ ATIVO ]"
        elif systemctl list-unit-files "$SERVICO.service" &>/dev/null; then
            STATUS_S="[ INATIVO ]"
        else
            STATUS_S="[ NÃO INSTALADO ]"
        fi
        printf "   %-25s %s\n" "$SERVICO" "$STATUS_S"
    done
    echo ""
    echo "[ 7. CONTAINERS DOCKER ]"
    echo "-------------------------------------------------------------------------------"
    if command -v docker >/dev/null 2>&1; then
        docker ps -a --format "   {{.Names}}\t\tStatus: {{.Status}}\t\tPortas: {{.Ports}}" 2>/dev/null
    else
        echo "   Docker não está instalado no sistema."
    fi
    echo ""
    echo "[ 8. TOP 5 PROCESSOS - CONSUMO DE RECURSOS ]"
    echo "-------------------------------------------------------------------------------"
    echo " --- Maior Consumo de RAM ---"
    ps -eo pid,user,%mem,comm --sort=-%mem | head -n 6 | tail -n 5 | awk '{printf "   PID: %-8s Usuário: %-12s RAM: %-6s Comando: %s\n", $1, $2, $3"%", $4}'
    echo ""
    echo " --- Maior Consumo de CPU ---"
    ps -eo pid,user,%cpu,comm --sort=-%cpu | head -n 6 | tail -n 5 | awk '{printf "   PID: %-8s Usuário: %-12s CPU: %-6s Comando: %s\n", $1, $2, $3"%", $4}'
    echo ""
    echo "[ 9. AVALIAÇÃO DE ALERTAS DO SISTEMA ]"
    echo "-------------------------------------------------------------------------------"
    local ALERTA_ENCONTRADO=0
    if [ "$PCT_DISCO_USADO" -gt "$LIMITE_DISCO" ]; then
        echo " [!] ALERTA DE DISCO : Uso em $PCT_DISCO_USADO% (Limite configurado: $LIMITE_DISCO%)"
        ALERTA_ENCONTRADO=1
    fi
    if [ "$PCT_RAM_USADA" -gt "$LIMITE_RAM" ]; then
        echo " [!] ALERTA DE RAM   : Uso em $PCT_RAM_USADA% (Limite configurado: $LIMITE_RAM%)"
        ALERTA_ENCONTRADO=1
    fi
    if [ "$PCT_CPU_USADA" -gt "$LIMITE_CPU" ]; then
        echo " [!] ALERTA DE CPU   : Uso em $PCT_CPU_USADA% (Limite configurado: $LIMITE_CPU%)"
        ALERTA_ENCONTRADO=1
    fi
    if [ "$ALERTA_ENCONTRADO" -eq 0 ]; then
        echo " [OK] Nenhum alerta detectado. O sistema está operando dentro dos limites salvos."
    fi
    echo "==============================================================================="
    echo "                            FIM DO RELATÓRIO                                   "
    echo "==============================================================================="
}

DIAGNOSTICO_DETALHADO() {
    # Coleta/Atualiza todas as métricas
    COLETAR_INFO

    while true; do
        clear
        # Exibe o relatório detalhado e estruturado na tela
        GERAR_TEXTO_DIAGNOSTICO

        echo ""
        echo " OPÇÕES:"
        echo "   [1] Salvar diagnóstico em arquivo TXT"
        echo "   [0] Voltar ao Menu Principal"
        BARRA "="
        read -p "Escolha uma opção: " OP_DIAG

        case $OP_DIAG in
            1)
                local DATA_ARQ=$(date '+%Y%m%d_%H%M%S')
                local NOME_PADRAO="diagnostico_${HOSTNAME_ATUAL}_${DATA_ARQ}.txt"
                
                echo ""
                read -p "Digite o nome/caminho do arquivo [$NOME_PADRAO]: " NOME_ARQ
                NOME_ARQ="${NOME_ARQ:-$NOME_PADRAO}"

                GERAR_TEXTO_DIAGNOSTICO > "$NOME_ARQ"

                if [ $? -eq 0 ]; then
                    echo ""
                    echo "[OK] Relatório salvo com sucesso em: $NOME_ARQ"
                else
                    echo ""
                    echo "[ERRO] Não foi possível salvar o arquivo em: $NOME_ARQ"
                fi
                echo ""
                read -p "Pressione [Enter] para continuar..." PAUSA
                ;;
            0)
                break
                ;;
            *)
                echo "Opção inválida!"; sleep 1
                ;;
        esac
    done
}

# ==============================================================================
# OUTRAS FUNÇÕES DAS OPÇÕES DO MENU
# ==============================================================================
CONSULTAR_LOGS() {
    clear
    BARRA 
    CENTER "ÚLTIMOS ERROS CRÍTICOS (LOGS)"
    BARRA 
    echo ""
    journalctl -p err..emerg --since "00:00:00" --no-pager
    echo ""
    read -p "Pressione [Enter] para voltar..." PAUSA
}

REDES_CONEXCOES() {
    clear
    BARRA "="
    CENTER "INTERFACES DE REDE E CONEXÕES"
    BARRA "="
    echo "--> Endereços de IP (Interfaces Ativas): "
    ip -brief address show 
    echo ""
    echo "--> Portas em Escuta (Sockets TCP/UDP): "
    if command -v ss >/dev/null 2>&1; then
        ss -tuln 
    fi
    echo ""
    read -p "Pressione [Enter] para voltar..." PAUSA
}

STATUS_SERVICOS() {
    clear
    BARRA "="
    CENTER "STATUS DOS SERVIÇOS DO SISTEMA"
    BARRA "="
    echo ""
    echo "  SERVIÇO              STATUS ATUAL"
    echo "---------------------------------------"

    for SERVICO in "${SERVICOS_CONFIG[@]}"; do
        if systemctl is-active --quiet "$SERVICO" 2>/dev/null; then
            STATUS="● Ativo (Running)"
        elif systemctl list-unit-files "$SERVICO.service" &>/dev/null; then
            STATUS="○ Inativo (Stopped)"
        else
            STATUS="- Nao instalado"
        fi
        echo -e "  $(printf '%-20s' "$SERVICO") $STATUS"
    done
    echo ""
    read -p "Pressione [Enter] para continuar..." PAUSA
}

STATUS_DOCKER() {
    clear
    BARRA "="
    CENTER "STATUS DOS CONTAINERS DOCKER"
    BARRA "="
    if command -v docker >/dev/null 2>&1; then
        docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}"
    else
        echo "Docker não está instalado no sistema."
    fi
    echo ""
    read -p "Pressione [Enter] para voltar..." PAUSA
}

USER_LOGADOS() {
    while true; do
        clear
        BARRA "="
        CENTER "USUÁRIOS LOGADOS E HISTÓRICO"
        BARRA "="
        echo "--> Usuários Atualmente Logados no Sistema:"
        who
        BARRA "-"
        echo "--> Consultar Histórico de Logins:"
        echo "   [1] Logins Efetuados hoje via SSH"
        echo "   [2] Logins Efetuados hoje como usuário Root"
        echo "   [0] Voltar"
        BARRA "-"
        read -p "Digite a opção desejada [0-2]: " LOGINS

        case $LOGINS in
            1)
                clear
                BARRA "="
                CENTER "LOGINS EFETUADOS HOJE VIA SSH"
                BARRA "="
                journalctl -u ssh -g "Accepted" --since "00:00:00" --no-pager 
                read -p "Pressione [Enter] para continuar..." PAUSA
                ;;
            2)
                clear
                BARRA "="
                CENTER "LOGINS EFETUADOS HOJE COMO USUÁRIO ROOT"
                BARRA "="
                journalctl -g "session opened for user root" --since "00:00:00" --no-pager | awk '/Boot/ {print "[BOOT]", $0; next} {print " Data:", $1, $2, $3,"| Máquina:", $4, " | Acesso:", $7, $8, $9, $10, $11, $12, $13}'
                read -p "Pressione [Enter] para continuar..." PAUSA
                ;;
            0)
                break
                ;;
            *) 
                echo "Opção inválida!"; sleep 1
                ;;
        esac
    done
}

REDE_E_USUARIOS() {
    while true; do
        clear
        BARRA "="
        CENTER "MONITOR DE REDE & USUÁRIOS LOGADOS"
        BARRA "="
        
        echo "--> INTERFACES DE REDE E CONEXÕES:"
        ip -brief address show 2>/dev/null
        
        echo ""
        echo "--> PORTAS EM ESCUTA (SOCKETS TCP/UDP):"
        if command -v ss >/dev/null 2>&1; then
            ss -tuln 2>/dev/null | head -n 10
        fi
        
        BARRA "-"
        echo "--> USUÁRIOS ATUALMENTE CONECTADOS:"
        who
        BARRA "-"
        
        echo " Opções Adicionais:"
        echo "   [1] Ver Sockets/Portas em Escuta Detalhados"
        echo "   [2] Logins efetuados hoje via SSH"
        echo "   [3] Logins efetuados hoje como ROOT"
        echo "   [0] Voltar ao Menu Principal"
        BARRA "="
        
        read -p "Digite a opção desejada [0-3]: " OP_RU

        case $OP_RU in
            1)
                clear
                BARRA "="
                CENTER "DETALHAMENTO DE PORTAS E SOCKETS (SS)"
                BARRA "="
                ss -tulnp 2>/dev/null || ss -tuln 2>/dev/null
                echo ""
                read -p "Pressione [Enter] para continuar..." PAUSA
                ;;
            2)
                clear
                BARRA "="
                CENTER "LOGINS EFETUADOS HOJE VIA SSH"
                BARRA "="
                journalctl -u ssh -g "Accepted" --since "00:00:00" --no-pager 2>/dev/null
                echo ""
                read -p "Pressione [Enter] para continuar..." PAUSA
                ;;
            3)
                clear
                BARRA "="
                CENTER "LOGINS EFETUADOS HOJE COMO USUÁRIO ROOT"
                BARRA "="
                journalctl -g "session opened for user root" --since "00:00:00" --no-pager 2>/dev/null | awk '/Boot/ {print "[BOOT]", $0; next} {print " Data:", $1, $2, $3,"| Máquina:", $4, " | Acesso:", $7, $8, $9, $10, $11, $12, $13}'
                echo ""
                read -p "Pressione [Enter] para continuar..." PAUSA
                ;;
            0)
                break
                ;;
            *)
                echo "Opção inválida!"; sleep 1
                ;;
        esac
    done
}

ATUALIZACOES_SEGURANCA() {
    clear
    BARRA "="
    CENTER "ATUALIZAÇÕES DE SEGURANÇA E PACOTES"
    BARRA "="
    echo ""
    echo "  [1/2] Verificando lista de pacotes atualizáveis..."
    BARRA "-"
    
    apt update -qq 2>/dev/null

    PACOTES_PENDENTES=$(apt list --upgradable 2>/dev/null | grep -v "Listing..." | grep -v "Listagem...")

    if [ -z "$PACOTES_PENDENTES" ]; then
        echo "  [OK] O sistema já está totalmente atualizado!"
        BARRA "="
        read -p "Pressione ENTER para voltar ao MENU principal..." PAUSA
        return
    fi

    echo "$PACOTES_PENDENTES" | head -n 15
    TOTAL=$(echo "$PACOTES_PENDENTES" | wc -l)
    
    if [ "$TOTAL" -gt 15 ]; then
        echo "  ... e mais $((TOTAL - 15)) pacote(s)."
    fi

    BARRA "-"
    echo "  Total de pacotes pendentes: $TOTAL"
    BARRA "="
    echo ""
    
    read -p "Deseja instalar todas as atualizações agora? (s/N): " RESP
    case "$RESP" in
        [sS]|[yY])
            echo ""
            echo "  [2/2] Instalando atualizações do sistema..."
            BARRA "-"
            apt upgrade -y
            BARRA "-"
            echo "  [OK] Atualização concluída com sucesso!"
            ;;
        *)
            echo ""
            echo "  [!] Operação de atualização cancelada pelo usuário."
            ;;
    esac

    echo ""
    read -p "Pressione ENTER para voltar ao MENU principal..." PAUSA
}

CONFIG_LIMITES() {
    while true; do
        clear
        BARRA "="
        CENTER "CONFIGURAÇÃO DE LIMITES DE ALERTA"
        BARRA "="
        echo "Limites Atuais de Disparo:"
        echo "  1) Uso de Disco: ${LIMITE_DISCO}%"
        echo "  2) Uso de RAM:   ${LIMITE_RAM}%"
        echo "  3) Uso de CPU:   ${LIMITE_CPU}%"
        echo "  0) Voltar ao Menu Principal"
        BARRA "="
        read -p "Escolha o limite que deseja alterar: " OP_CONF

        case $OP_CONF in
            1)
                read -p "Informe o novo limite para DISCO (1-99%): " NOVO_VAL
                if [[ "$NOVO_VAL" =~ ^[0-9]+$ ]] && [ "$NOVO_VAL" -ge 1 ] && [ "$NOVO_VAL" -le 99 ]; then
                    LIMITE_DISCO=$NOVO_VAL
                    SALVAR_ALTERACOES
                    echo "[OK] Limite alterado para ${LIMITE_DISCO}%"
                else
                    echo "[ERRO] Valor inválido!"
                fi
                sleep 1
                ;;
            2)
                read -p "Informe o novo limite para RAM (1-99%): " NOVO_VAL
                if [[ "$NOVO_VAL" =~ ^[0-9]+$ ]] && [ "$NOVO_VAL" -ge 1 ] && [ "$NOVO_VAL" -le 99 ]; then
                    LIMITE_RAM=$NOVO_VAL
                    SALVAR_ALTERACOES
                    echo "[OK] Limite alterado para ${LIMITE_RAM}%"
                else
                    echo "[ERRO] Valor inválido!"
                fi
                sleep 1
                ;;
            3)
                read -p "Informe o novo limite para CPU (1-99%): " NOVO_VAL
                if [[ "$NOVO_VAL" =~ ^[0-9]+$ ]] && [ "$NOVO_VAL" -ge 1 ] && [ "$NOVO_VAL" -le 99 ]; then
                    LIMITE_CPU=$NOVO_VAL
                    SALVAR_ALTERACOES
                    echo "[OK] Limite alterado para ${LIMITE_CPU}%"
                else
                    echo "[ERRO] Valor inválido!"
                fi
                sleep 1
                ;;
            0)
                break
                ;;
            *)
                echo "[ERRO] Opção inválida!"; sleep 1.5
                ;;
        esac
    done
}

OPMENU() {
    read -t 60 -p "Escolha uma opção [0-9]: " OP

    case $OP in
        1) DIAGNOSTICO_DETALHADO ;;
        2) CONSULTAR_LOGS ;;
        3) REDE_E_USUARIOS ;;
        4) ATUALIZACOES_SEGURANCA ;;
        
        5)
             clear
             echo "Pacotes instalados:"
             apt list --installed 2>/dev/null | grep -v "Listando..." | cat -n | more
             echo ""
             read -p "Aperte Enter para continuar..." PAUSA
        ;;
        6)
                clear
                read -p "Qual pacote buscas: " BUSCA
                if [ -n "$BUSCA" ]; then
                    RESULTADO=$(apt search "$BUSCA" 2>/dev/null | grep -v "Ordenando" | grep -v "Pesquisa de texto completo")

                    if [ -n "$RESULTADO" ]; then
                        echo "$RESULTADO" | cat -n | more
                        echo ""
                        
                        read -p "Pacote para remover: " PKG
                        
                        if [ -n "$PKG" ]; then
                            read -p "Remover $PKG? [s/N]: " CONFIRM
                            case "$CONFIRM" in
                                s|S) 
                                    apt purge -y "$PKG" && apt autoremove -y && echo "Pacote removido com sucesso."  
                                    ;;
                                *) 
                                    echo "Cancelado." 
                                    ;;
                            esac
                        fi
                    else
                        echo "Pacote não encontrado nos repositórios."
                    fi
                else
                    echo "Você não digitou nenhum termo de busca."
                fi
                echo ""
                read -p "Pressione Enter para continuar..." PAUSA
                ;;
            7)
                clear
                read -p "Qual app-flatpak buscas: " BUSCA
                if [ -n "$BUSCA" ]; then
                    RESULTADO=$(flatpak list --app 2>/dev/null | grep "$BUSCA")

                    if [ -n "$RESULTADO" ]; then
                        echo "Resultados encontrados:"
                        echo "$RESULTADO"
                        echo ""
                        
                        read -p "App ID para remover: " APPID
                        if [ -n "$APPID" ]; then
                            if echo "$RESULTADO" | grep -q "$APPID"; then
                                read -p "Remover ${APPID}? [s/N]: " CONFIRM
                                case "$CONFIRM" in
                                    s|S) 
                                        flatpak uninstall -y "$APPID" && echo "$APPID removido." 
                                        ;;
                                    *) 
                                        echo "Cancelado." 
                                        ;;
                                esac
                            fi
                        fi
                    else
                        echo "Nenhum aplicativo Flatpak encontrado com o termo '$BUSCA'."
                    fi
                else
                    echo "Você não digitou nenhum termo de busca."
                fi
                echo ""
                read -p "Pressione Enter para continuar..." PAUSA
                ;;
            8)
                clear
                apt autoremove -y && echo "Limpeza concluída."
                read -p "Pressione Enter para continuar..." PAUSA
                ;;
        9) CONFIG_LIMITES ;;
        0) echo "Encerrando o monitoramento..."; exit 0 ;;
        *) echo "Opção inválida!"; sleep 1 ;;
    esac
}

# ==============================================================================
# EXECUÇÃO PRINCIPAL
# ==============================================================================
EXIBIR_AJUDA() {
    BARRA "="
    CENTER "AJUDA E INSTRUÇÕES DE USO"
    BARRA "="
    echo "SINOPSES:"
    echo "  sudo $0 [OPÇÃO]"
    echo ""
    echo "DESCRIÇÃO:"
    echo "  Script de monitorização, diagnóstico de recursos e gestão de pacotes"
    echo "  para sistemas Linux (Ubuntu/Debian)."
    echo ""
    echo "OPÇÕES:"
    echo "  -d, --dashboard    Exibe apenas o resumo (Dashboard) do sistema e encerra."
    echo "  -h, --help, help   Exibe este menu de ajuda detalhado e encerra."
    echo ""
    echo "MODO INTERATIVO:"
    echo "  Se executado sem argumentos (sudo $0), o script entra no modo gráfico"
    echo "  interativo com atualização de métricas e menu de opções:"
    echo ""
    echo "  [1] Diagnóstico       Gera relatório completo de infraestrutura e exporta em TXT."
    echo "  [2] Logs Críticos     Exibe erros recentes do sistema via journalctl."
    echo "  [3] Redes e Usuários  Apresenta sockets, portas em escuta e acessos no sistema."
    echo "  [4] Atualizações      Verifica e instala atualizações de segurança pendentes."
    echo "  [5] Listar Pacotes    Lista todos os pacotes APT instalados no sistema."
    echo "  [6] Gestão APT        Procura e remove pacotes/aplicações via APT."
    echo "  [7] Gestão Flatpak    Procura e remove aplicações instaladas via Flatpak."
    echo "  [8] Limpar Órfãos     Remove dependências obsoletas (apt autoremove)."
    echo "  [9] Configurações     Ajusta os limites de alerta (CPU, RAM e Disco)."
    echo "  [0] Sair              Encerra o script."
    echo ""
    echo "REQUISITOS:"
    echo "  Necessita de permissões de superutilizador (root/sudo)."
    BARRA "="
    exit 0
}

if [ -n "$1" ]; then
    case $1 in
        -d|--dashboard)
            COLETAR_INFO
            DASHBOARD
            exit 0
            ;;
        -h|help|--help)
            EXIBIR_AJUDA
            ;;
        *)
            echo "Erro: Opção '$1' desconhecida."
            echo "Tente '$0 --help' para mais informações."
            exit 1
            ;;
    esac
else
    while true; do 
        clear
        COLETAR_INFO
        TELA
        OPMENU
    done
fi
