#!/bin/bash
# GNUnet 集群快速部署脚本
# 使用方法: ./quick-cluster-setup.sh [bootstrap|node] [node_number]

set -e

NODE_TYPE=${1:-node}
NODE_NUMBER=${2:-1}
CLUSTER_NAME="gnunet-cluster"
BASE_PORT=12000

# 日志输出函数
log_info() {
    echo "[INFO] $1"
}

log_success() {
    echo "[SUCCESS] $1"
}

log_error() {
    echo "[ERROR] $1"
}

# 检查是否为 root 或有 sudo 权限
check_privileges() {
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        log_error "需要 root 权限或 sudo 权限来执行此脚本"
        exit 1
    fi
}

# 安装依赖
install_dependencies() {
    log_info "安装 GNUnet 依赖..."
    
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y gnunet gnunet-dev sqlite3 netcat-openbsd
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y gnunet gnunet-devel sqlite netcat
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y gnunet gnunet-devel sqlite nc
    else
        log_error "不支持的包管理器，请手动安装 GNUnet"
        exit 1
    fi
    
    # 创建 gnunet 用户（如果不存在）
    if ! id "gnunet" >/dev/null 2>&1; then
        sudo useradd -r -s /bin/false gnunet
    fi
}

# 创建目录结构
create_directories() {
    local node_dir="/opt/gnunet-cluster/node-${NODE_NUMBER}"
    
    log_info "创建目录结构..."
    
    sudo mkdir -p "${node_dir}/data"
    sudo mkdir -p "${node_dir}/config"
    sudo mkdir -p "${node_dir}/cache"
    sudo mkdir -p "${node_dir}/run"
    sudo mkdir -p "${node_dir}/logs"
    
    sudo chown -R gnunet:gnunet "/opt/gnunet-cluster"
    
    echo "$node_dir"
}

# 生成配置文件
generate_config() {
    local node_dir=$1
    local config_file="${node_dir}/config/gnunet.conf"
    local tcp_port=$((BASE_PORT + NODE_NUMBER))
    local arm_port=$((BASE_PORT + NODE_NUMBER + 1000))
    local core_port=$((BASE_PORT + NODE_NUMBER + 2000))
    local dht_port=$((BASE_PORT + NODE_NUMBER + 3000))
    
    log_info "生成节点配置文件..."
    
    if [ "$NODE_TYPE" = "bootstrap" ]; then
        generate_bootstrap_config "$config_file" "$tcp_port" "$arm_port" "$core_port" "$dht_port" "$node_dir"
    else
        generate_node_config "$config_file" "$tcp_port" "$arm_port" "$core_port" "$dht_port" "$node_dir"
    fi
}

generate_bootstrap_config() {
    local config_file=$1
    local tcp_port=$2
    local arm_port=$3
    local core_port=$4
    local dht_port=$5
    local node_dir=$6
    
    sudo tee "$config_file" > /dev/null << EOF
# GNUnet Bootstrap 节点配置 - 节点 ${NODE_NUMBER}
[PATHS]
GNUNET_HOME = ${node_dir}/data
GNUNET_CONFIG_HOME = ${node_dir}/config
GNUNET_RUNTIME_DIR = ${node_dir}/run
GNUNET_CACHE_HOME = ${node_dir}/cache

[arm]
PORT = ${arm_port}
HOSTNAME = localhost
DEFAULTSERVICES = core datastore fs dht cadet gns statistics peerinfo hostlist
AUTOSTART = YES

[transport]
PLUGINS = tcp udp unix
PORT = $((tcp_port + 100))
HOSTNAME = localhost

[transport-tcp]
DISABLE = NO
PORT = ${tcp_port}
HOSTNAME = 0.0.0.0
ADVERTISED_PORT = ${tcp_port}
USE_LOCALADDR = YES

[transport-udp]
DISABLE = NO
PORT = ${tcp_port}
HOSTNAME = 0.0.0.0
BROADCAST = YES
BROADCAST_INTERVAL = 30s

[transport-unix]
DISABLE = NO

[core]
PORT = ${core_port}
HOSTNAME = localhost
MAX_CONNECTIONS = 100

[dht]
PORT = ${dht_port}
HOSTNAME = localhost
STORAGE = 1 GB
REPLICATION_LEVEL = 3

[datastore]
PORT = $((dht_port + 100))
HOSTNAME = localhost
DATABASE = sqlite
QUOTA = 5 GB
AUTOSTART = YES

[datastore-sqlite]
FILENAME = ${node_dir}/data/datastore.db

[fs]
PORT = $((dht_port + 200))
HOSTNAME = localhost

[cadet]
PORT = $((dht_port + 300))
HOSTNAME = localhost

[gns]
PORT = $((dht_port + 400))
HOSTNAME = localhost

[namestore]
PORT = $((dht_port + 500))
HOSTNAME = localhost
DATABASE = sqlite

[namestore-sqlite]
FILENAME = ${node_dir}/data/namestore.db

[identity]
PORT = $((dht_port + 600))
HOSTNAME = localhost

[statistics]
PORT = $((dht_port + 700))
HOSTNAME = localhost

[peerinfo]
PORT = $((dht_port + 800))
HOSTNAME = localhost

[hostlist]
ENABLE_HOSTLIST_CLIENT = NO
ENABLE_HOSTLIST_SERVER = YES
HTTPPORT = $((tcp_port + 8000))
BINDTO = 0.0.0.0

[nat]
ENABLE_UPNP = NO
USE_HOSTNAME = NO
RETURN_LOCAL_ADDRESSES = YES

[LOGGING]
DEFAULT_LOG_LEVEL = INFO
LOG_FILE = ${node_dir}/logs/gnunet.log
EOF
    
    sudo chown gnunet:gnunet "$config_file"
}

generate_node_config() {
    local config_file=$1
    local tcp_port=$2
    local arm_port=$3
    local core_port=$4
    local dht_port=$5
    local node_dir=$6
    
    sudo tee "$config_file" > /dev/null << EOF
# GNUnet 普通节点配置 - 节点 ${NODE_NUMBER}
[PATHS]
GNUNET_HOME = ${node_dir}/data
GNUNET_CONFIG_HOME = ${node_dir}/config
GNUNET_RUNTIME_DIR = ${node_dir}/run
GNUNET_CACHE_HOME = ${node_dir}/cache

[arm]
PORT = ${arm_port}
HOSTNAME = localhost
DEFAULTSERVICES = core datastore fs dht cadet statistics peerinfo
AUTOSTART = YES

[transport]
PLUGINS = tcp udp unix
PORT = $((tcp_port + 100))
HOSTNAME = localhost

[transport-tcp]
DISABLE = NO
PORT = ${tcp_port}
HOSTNAME = 0.0.0.0
ADVERTISED_PORT = ${tcp_port}
USE_LOCALADDR = YES

[transport-udp]
DISABLE = NO
PORT = ${tcp_port}
HOSTNAME = 0.0.0.0
BROADCAST = YES

[transport-unix]
DISABLE = NO

[core]
PORT = ${core_port}
HOSTNAME = localhost
MAX_CONNECTIONS = 50

[dht]
PORT = ${dht_port}
HOSTNAME = localhost
STORAGE = 500 MB

[datastore]
PORT = $((dht_port + 100))
HOSTNAME = localhost
DATABASE = sqlite
QUOTA = 2 GB
AUTOSTART = YES

[datastore-sqlite]
FILENAME = ${node_dir}/data/datastore.db

[fs]
PORT = $((dht_port + 200))
HOSTNAME = localhost

[cadet]
PORT = $((dht_port + 300))
HOSTNAME = localhost

[statistics]
PORT = $((dht_port + 700))
HOSTNAME = localhost

[peerinfo]
PORT = $((dht_port + 800))
HOSTNAME = localhost

[hostlist]
ENABLE_HOSTLIST_CLIENT = YES
SERVERS = http://localhost:$((BASE_PORT + 1 + 8000))

[nat]
ENABLE_UPNP = NO
USE_HOSTNAME = NO
RETURN_LOCAL_ADDRESSES = YES

[LOGGING]
DEFAULT_LOG_LEVEL = INFO
LOG_FILE = ${node_dir}/logs/gnunet.log
EOF
    
    sudo chown gnunet:gnunet "$config_file"
}

# 创建启动脚本
create_startup_script() {
    local node_dir=$1
    local startup_script="${node_dir}/start-node.sh"
    local config_file="${node_dir}/config/gnunet.conf"
    
    log_info "创建启动脚本..."
    
    sudo tee "$startup_script" > /dev/null << EOF
#!/bin/bash
# GNUnet 节点 ${NODE_NUMBER} 启动脚本

NODE_DIR="${node_dir}"
CONFIG_FILE="${config_file}"

export GNUNET_HOME="\${NODE_DIR}/data"
export GNUNET_CONFIG_HOME="\${NODE_DIR}/config"

# 检查配置文件
if [ ! -f "\$CONFIG_FILE" ]; then
    echo "错误: 配置文件不存在: \$CONFIG_FILE"
    exit 1
fi

# 创建 PID 文件目录
mkdir -p "\${NODE_DIR}/run"

echo "启动 GNUnet 节点 ${NODE_NUMBER}..."
echo "配置文件: \$CONFIG_FILE"
echo "数据目录: \$GNUNET_HOME"

# 启动 GNUnet ARM
sudo -u gnunet GNUNET_HOME="\$GNUNET_HOME" gnunet-arm -c "\$CONFIG_FILE" -s

# 等待服务启动
sleep 5

# 检查状态
echo "检查节点状态..."
sudo -u gnunet GNUNET_HOME="\$GNUNET_HOME" gnunet-arm -c "\$CONFIG_FILE" -I

echo "节点 ${NODE_NUMBER} 启动完成"
echo "查看日志: tail -f \${NODE_DIR}/logs/gnunet.log"
echo "停止节点: sudo -u gnunet GNUNET_HOME=\$GNUNET_HOME gnunet-arm -c \$CONFIG_FILE -e"
EOF
    
    sudo chmod +x "$startup_script"
    sudo chown gnunet:gnunet "$startup_script"
}

# 创建停止脚本
create_stop_script() {
    local node_dir=$1
    local stop_script="${node_dir}/stop-node.sh"
    local config_file="${node_dir}/config/gnunet.conf"
    
    log_info "创建停止脚本..."
    
    sudo tee "$stop_script" > /dev/null << EOF
#!/bin/bash
# GNUnet 节点 ${NODE_NUMBER} 停止脚本

NODE_DIR="${node_dir}"
CONFIG_FILE="${config_file}"

export GNUNET_HOME="\${NODE_DIR}/data"

echo "停止 GNUnet 节点 ${NODE_NUMBER}..."

# 停止所有 GNUnet 服务
sudo -u gnunet GNUNET_HOME="\$GNUNET_HOME" gnunet-arm -c "\$CONFIG_FILE" -e

echo "节点 ${NODE_NUMBER} 已停止"
EOF
    
    sudo chmod +x "$stop_script"
    sudo chown gnunet:gnunet "$stop_script"
}

# 创建状态检查脚本
create_status_script() {
    local node_dir=$1
    local status_script="${node_dir}/status-node.sh"
    local config_file="${node_dir}/config/gnunet.conf"
    
    log_info "创建状态检查脚本..."
    
    sudo tee "$status_script" > /dev/null << EOF
#!/bin/bash
# GNUnet 节点 ${NODE_NUMBER} 状态检查脚本

NODE_DIR="${node_dir}"
CONFIG_FILE="${config_file}"

export GNUNET_HOME="\${NODE_DIR}/data"

echo "GNUnet 节点 ${NODE_NUMBER} 状态检查"
echo "=================================="

# 检查服务状态
echo "1. 服务状态:"
sudo -u gnunet GNUNET_HOME="\$GNUNET_HOME" gnunet-arm -c "\$CONFIG_FILE" -I

# 检查连接数
echo -e "\n2. 网络连接:"
echo "本节点身份:"
sudo -u gnunet GNUNET_HOME="\$GNUNET_HOME" gnunet-peerinfo -c "\$CONFIG_FILE" -s -q 2>/dev/null || echo "无法获取身份信息"
echo "已知对等节点数量:"
sudo -u gnunet GNUNET_HOME="\$GNUNET_HOME" gnunet-peerinfo -c "\$CONFIG_FILE" -i -q 2>/dev/null | wc -l || echo "0"

# 检查端口监听
echo -e "\n3. 端口监听:"
netstat -tlnp | grep gnunet | head -5

# 检查磁盘使用
echo -e "\n4. 磁盘使用:"
du -sh "\${NODE_DIR}/data" 2>/dev/null || echo "数据目录为空"

# 检查日志
echo -e "\n5. 最近日志 (最后10行):"
if [ -f "\${NODE_DIR}/logs/gnunet.log" ]; then
    tail -10 "\${NODE_DIR}/logs/gnunet.log"
else
    echo "日志文件不存在"
fi
EOF
    
    sudo chmod +x "$status_script"
    sudo chown gnunet:gnunet "$status_script"
}

# 创建集群管理脚本
create_cluster_manager() {
    local cluster_script="/opt/gnunet-cluster/cluster-manager.sh"
    
    log_info "创建集群管理脚本..."
    
    sudo tee "$cluster_script" > /dev/null << 'EOF'
#!/bin/bash
# GNUnet 集群管理脚本

CLUSTER_DIR="/opt/gnunet-cluster"
COMMAND=$1
NODE_ID=$2

usage() {
    echo "GNUnet 集群管理器"
    echo "用法:"
    echo "  $0 start [node_id]     # 启动节点(或所有节点)"
    echo "  $0 stop [node_id]      # 停止节点(或所有节点)"
    echo "  $0 status [node_id]    # 查看节点状态(或所有节点)"
    echo "  $0 list                # 列出所有节点"
    echo "  $0 connect NODE1 NODE2 # 连接两个节点"
    echo "  $0 logs NODE_ID        # 查看节点日志"
}

list_nodes() {
    echo "集群节点列表:"
    echo "============="
    for node_dir in "$CLUSTER_DIR"/node-*; do
        if [ -d "$node_dir" ]; then
            node_num=$(basename "$node_dir" | sed 's/node-//')
            node_type="普通节点"
            if grep -q "ENABLE_HOSTLIST_SERVER = YES" "$node_dir/config/gnunet.conf" 2>/dev/null; then
                node_type="Bootstrap节点"
            fi
            echo "节点 $node_num: $node_type ($node_dir)"
        fi
    done
}

start_node() {
    local node_id=$1
    if [ -z "$node_id" ]; then
        # 启动所有节点
        for node_dir in "$CLUSTER_DIR"/node-*; do
            if [ -d "$node_dir" ] && [ -x "$node_dir/start-node.sh" ]; then
                echo "启动节点 $(basename "$node_dir")..."
                "$node_dir/start-node.sh"
                sleep 2
            fi
        done
    else
        local node_dir="$CLUSTER_DIR/node-$node_id"
        if [ -x "$node_dir/start-node.sh" ]; then
            "$node_dir/start-node.sh"
        else
            echo "错误: 节点 $node_id 不存在或启动脚本不可执行"
        fi
    fi
}

stop_node() {
    local node_id=$1
    if [ -z "$node_id" ]; then
        # 停止所有节点
        for node_dir in "$CLUSTER_DIR"/node-*; do
            if [ -d "$node_dir" ] && [ -x "$node_dir/stop-node.sh" ]; then
                echo "停止节点 $(basename "$node_dir")..."
                "$node_dir/stop-node.sh"
                sleep 1
            fi
        done
    else
        local node_dir="$CLUSTER_DIR/node-$node_id"
        if [ -x "$node_dir/stop-node.sh" ]; then
            "$node_dir/stop-node.sh"
        else
            echo "错误: 节点 $node_id 不存在或停止脚本不可执行"
        fi
    fi
}

status_node() {
    local node_id=$1
    if [ -z "$node_id" ]; then
        # 查看所有节点状态
        for node_dir in "$CLUSTER_DIR"/node-*; do
            if [ -d "$node_dir" ] && [ -x "$node_dir/status-node.sh" ]; then
                echo "=== 节点 $(basename "$node_dir") 状态 ==="
                "$node_dir/status-node.sh"
                echo
            fi
        done
    else
        local node_dir="$CLUSTER_DIR/node-$node_id"
        if [ -x "$node_dir/status-node.sh" ]; then
            "$node_dir/status-node.sh"
        else
            echo "错误: 节点 $node_id 不存在或状态脚本不可执行"
        fi
    fi
}

connect_nodes() {
    local node1=$1
    local node2=$2
    
    if [ -z "$node1" ] || [ -z "$node2" ]; then
        echo "错误: 需要指定两个节点ID"
        echo "用法: $0 connect NODE1 NODE2"
        return 1
    fi
    
    local node1_dir="$CLUSTER_DIR/node-$node1"
    local node2_dir="$CLUSTER_DIR/node-$node2"
    
    if [ ! -d "$node1_dir" ] || [ ! -d "$node2_dir" ]; then
        echo "错误: 指定的节点不存在"
        return 1
    fi
    
    echo "连接节点 $node1 和节点 $node2..."
    
    # 获取节点的 PKEY
    export GNUNET_HOME="$node2_dir/data"
    local node2_pkey=$(sudo -u gnunet gnunet-peerinfo -c "$node2_dir/config/gnunet.conf" -g -s 2>/dev/null | head -1)
    
    if [ -n "$node2_pkey" ]; then
        export GNUNET_HOME="$node1_dir/data"
        sudo -u gnunet gnunet-peerinfo -c "$node1_dir/config/gnunet.conf" -p "$node2_pkey"
        echo "节点连接命令已执行"
    else
        echo "错误: 无法获取节点 $node2 的 PKEY"
    fi
}

show_logs() {
    local node_id=$1
    if [ -z "$node_id" ]; then
        echo "错误: 需要指定节点ID"
        echo "用法: $0 logs NODE_ID"
        return 1
    fi
    
    local log_file="$CLUSTER_DIR/node-$node_id/logs/gnunet.log"
    if [ -f "$log_file" ]; then
        echo "节点 $node_id 日志 (实时):"
        echo "按 Ctrl+C 停止"
        tail -f "$log_file"
    else
        echo "错误: 节点 $node_id 的日志文件不存在"
    fi
}

case "$COMMAND" in
    "start")
        start_node "$NODE_ID"
        ;;
    "stop")
        stop_node "$NODE_ID"
        ;;
    "status")
        status_node "$NODE_ID"
        ;;
    "list")
        list_nodes
        ;;
    "connect")
        connect_nodes "$NODE_ID" "$3"
        ;;
    "logs")
        show_logs "$NODE_ID"
        ;;
    *)
        usage
        ;;
esac
EOF
    
    sudo chmod +x "$cluster_script"
}

# 启动节点
start_node() {
    local node_dir=$1
    local config_file="${node_dir}/config/gnunet.conf"
    
    log_info "启动 GNUnet 节点 ${NODE_NUMBER}..."
    
    export GNUNET_HOME="${node_dir}/data"
    
    # 启动 ARM 服务
    sudo -u gnunet GNUNET_HOME="$GNUNET_HOME" gnunet-arm -c "$config_file" -s
    
    # 等待服务启动
    sleep 5
    
    # 检查状态
    log_info "检查节点状态..."
    sudo -u gnunet GNUNET_HOME="$GNUNET_HOME" gnunet-arm -c "$config_file" -I
}

# 主函数
main() {
    log_info "GNUnet 集群快速部署脚本"
    log_info "节点类型: $NODE_TYPE, 节点编号: $NODE_NUMBER"
    
    check_privileges
    install_dependencies
    
    # 分步执行，避免输出干扰
    log_info "创建目录结构..."
    local node_dir="/opt/gnunet-cluster/node-${NODE_NUMBER}"
    sudo mkdir -p "${node_dir}/data"
    sudo mkdir -p "${node_dir}/config"
    sudo mkdir -p "${node_dir}/cache"
    sudo mkdir -p "${node_dir}/run"
    sudo mkdir -p "${node_dir}/logs"
    sudo chown -R gnunet:gnunet "/opt/gnunet-cluster"
    
    generate_config "$node_dir"
    create_startup_script "$node_dir"
    create_stop_script "$node_dir"
    create_status_script "$node_dir"
    create_cluster_manager
    
    log_success "节点配置完成!"
    log_info "节点目录: $node_dir"
    
    echo
    echo "下一步操作:"
    echo "1. 启动节点: $node_dir/start-node.sh"
    echo "2. 查看状态: $node_dir/status-node.sh"
    echo "3. 停止节点: $node_dir/stop-node.sh"
    echo "4. 集群管理: /opt/gnunet-cluster/cluster-manager.sh"
    echo
    
    read -p "是否现在启动节点? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        start_node "$node_dir"
        log_success "节点已启动!"
    fi
    
    log_info "部署完成!"
}

# 执行主函数
main
