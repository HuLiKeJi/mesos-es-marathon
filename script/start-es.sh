#!/bin/bash
#require $HOST $ZOOKEEPER
set -x

die() { echo $@; exit 1; }

[ "$HOST" != "" ]      || die "HOST not found"
[ "$ZOOKEEPER" != "" ] || die "zookeeper not found"

echo "[HOST]: $HOST"
echo "[ZK]: $ZOOKEEPER"

CFG_BASE_DIR="/es-config/config"
DATA_BASE_DIR="/es-data"
export ES_ZK_PATH_ROOT="/es-mesos"
export ES_ZK_PATH_MARATHON="/marathon"

BASE_DIR=`pwd`

cfg_file="$CFG_BASE_DIR/elasticsearch.yml";
zk_cmd="zookeepercli -servers $ZOOKEEPER " 

replace_from_env() {

    prefix=$1; delimiter=$2
    for VAR in `env`
    do
        if [[ $VAR =~ ^$prefix ]]; then
            key=`echo "$VAR" | sed -r "s/$prefix(.*)=.*/\1/g" | tr '[:upper:]' '[:lower:]' | tr _ .`
            value=`echo "$VAR" | sed -r "s/(.*)=.*/\1/g"`
            update_if_not_exist $key "$delimiter" ${!value}
        fi
    done

    if [[ -n "$CUSTOM_INIT_SCRIPT" ]] ; then
        eval $CUSTOM_INIT_SCRIPT
    fi
}

update_if_not_exist() {
    key=$1; delimiter=$2; value="$3"
    echo $key, $delimiter, $value
    if [ "$value" == "" ]; then
        return 
    fi

    delimiter_trim=$(echo $delimiter|sed 's/\s//g')
    if egrep -q "(^|^#)$key\s*$delimiter_trim" $cfg_file; then
        sed -r -i "s@(^|^#)($key)\s*$delimiter_trim(.*)@\2$delimiter$value@g" $cfg_file #note that no config values may contain an '@' char
    else
        echo "$key$delimiter$value" >> $cfg_file
    fi
}

get_config() {
    key=$1; delimiter=$2
    grep "$key" $cfg_file|sed "s/^#\?$key\s*$delimiter\s*\(.*\)\s*/\1/"
}

zk_path_ids="$zk_path_root/ids"

mkdir -p $CFG_BASE_DIR 2>/dev/null
if [ ! -e $cfg_file ];then
    touch $cfg_file || die "cannot modify $cfg_file"
fi

cp config-bak/logging.yml $CFG_BASE_DIR

#read old node name
NODE_NAME=$(get_config "node.name" ":")
#override config file
cp -f config-bak/elasticsearch.yml $CFG_BASE_DIR

#gererate node.name if not exist in config
if [ "$NODE_NAME" == "" ];then
    echo "generate new node name.."

    #get node type
    ES_NODE_MASTER=$(get_config "node.master" ":"|sed 's/[ \t\r\n]//')
    ES_NODE_DATA=$(get_config "node.data" ":"|sed 's/[ \t\r\n]//')
    if  [[ $ES_NODE_MASTER =~ "true" && $ES_NODE_DATA =~ "true" ]];then
        NODE_TYPE="node"
    elif [[ $ES_NODE_MASTER =~ "true" ]]; then
        NODE_TYPE="master"
    elif [[ $ES_NODE_DATA =~ "true" ]]; then
        NODE_TYPE="data"
    else
        NODE_TYPE="unknown"
    fi

    #generate node id
    id=`$zk_cmd -force -c inc $zk_path_ids/$NODE_TYPE` || die "cannot get node.name from zk"

    NODE_NAME="$NODE_TYPE-$id"
fi
#write back to new config file
update_if_not_exist "node.name" ": " "$NODE_NAME"


echo "generate unicast host list ..."

export ES_NODE_NAME=$NODE_NAME
export ES_TRANSPORT_PORT=$(get_config "transport.tcp.port" ":")

nodes=`python update-hosts.py | tail -n 1` 
if [ $? -ne 0 ]; then
    echo $nodes
    die "generate hosts failed"
fi
update_if_not_exist "discovery.zen.ping.unicast.hosts" ": " $nodes


echo "update config from env ..."
replace_from_env "ES_CONFIG_" ": "


cat <<EOF
----------------------------------
[HOST]: $HOST
[ZK]  : $ZOOKEEPER
[NODE]: $NODE_NAME
[PORT]: $ES_TRANSPORT_PORT
----------------------------------
[$cfg_file]:
`cat $cfg_file | sed 's/^/    /g'`
----------------------------------
EOF

es_pid=""
stop_es() {
    if [ $es_pid -ne 0 ]; then
        kill -s TERM $es_pid
        wait $es_pid
    fi
}
trap "stop_es" SIGINT SIGTERM SIGQUIT SIGABRT

./bin/elasticsearch -Dpath.home=/es-config -Des.insecure.allow.root=true || die "start es failed" &
es_pid=$!

wait $es_pid
