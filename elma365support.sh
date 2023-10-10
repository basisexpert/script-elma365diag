#!/usr/bin/env bash

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit 1;
fi

OS_K8S_NODE_CMD_EXECUTOR="ssh -i $K8S_SSH_KEY ${K8S_SSH_USER}@\${K8S_NODE} sudo -i"
OS_K8S_NODE_DIAG_COMMANDS=(
"hostname"
"hostname -I"
"uname -a"
"cat /etc/os-release"
"free -h"
"lscpu"
"uptime"
"snap list"
"df -x overlay -x tmpfs"
"cat /etc/resolv.conf"
"ufw status"
"ss -nlptu"
"ip route"
)

_K8S_ELMA365_NAMESPACE=${K8S_ELMA365_NAMESPACE:-default}
_K8S_KUBECTL_CMD=${K8S_KUBECTL_CMD:-kubectl}
K8S_DIAG_COMMANDS=(
"$_K8S_KUBECTL_CMD get all -A"
"$_K8S_KUBECTL_CMD -n $_K8S_ELMA365_NAMESPACE logs -l tier=elma365 --all-containers | grep '\"fatal\"' "
"$_K8S_KUBECTL_CMD -n $_K8S_ELMA365_NAMESPACE logs -l tier=elma365 --all-containers | grep '\"error\"' "
"$_K8S_KUBECTL_CMD get all -A | grep dns"
"$_K8S_KUBECTL_CMD logs -l k8s-app=kube-dns -n kube-system -c coredns"
"$_K8S_KUBECTL_CMD get events --all-namespaces"
"$_K8S_KUBECTL_CMD get nodes -o wide"
"$_K8S_KUBECTL_CMD top nodes | sort -k 3"
"$_K8S_KUBECTL_CMD describe nodes"
"$_K8S_KUBECTL_CMD get pods -n $_K8S_ELMA365_NAMESPACE -o wide"
"$_K8S_KUBECTL_CMD top pods -n $_K8S_ELMA365_NAMESPACE | sort -k 3"
"$_K8S_KUBECTL_CMD describe pods"
)

PSQL_URL=$($_K8S_KUBECTL_CMD get secret elma365-db-connections -o jsonpath='{.data.PSQL_URL}' | base64 -d)
PSQL_CMD_EXECUTOR="psql $PSQL_URL"
PSQL_DIAG_COMMANDS=(
'SELECT version();'
'SELECT * FROM pg_extension;'
'SELECT * FROM public.companies;'
'SHOW max_connections;'
'SHOW work_mem;'
'\l+'
'\dt+ *.*'
)

# Arguments:
#   $1: COMMAND EXECUTOR
#   $2: COMMENT
#   $3: COMMAND
diagnostic_cmd() {
    local COMMAND_EXECUTOR="$1"
    shift
    local COMMAND_COMMENT="$1:"
    shift
    local COMMAND=("$@")
    echo -e "\n=========\n\n# $COMMAND_COMMENT $COMMAND\n"
    eval "$COMMAND_EXECUTOR $COMMAND"
}

diagnostic() {
    for K8S_NODE in "${K8S_NODES[@]}"; do
        for i in "${OS_K8S_NODE_DIAG_COMMANDS[@]}"; do
            diagnostic_cmd "$OS_K8S_NODE_CMD_EXECUTOR" "Node $K8S_NODE info" "$i"
        done
    done
    for i in "${K8S_DIAG_COMMANDS[@]}"; do
        diagnostic_cmd "" "Kubernetes info" "$i"
    done    
    for i in "${PSQL_DIAG_COMMANDS[@]}"; do
        diagnostic_cmd "$PSQL_CMD_EXECUTOR -qc" "PostgreSQL info" "'$i'"
    done    
}

diagnostic
