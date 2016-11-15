#!/bin/bash
#require $HOST $ZOOKEEPER
set -x

die() { echo $@; exit 1; }

[ "$HOST" != "" ]      || die "HOST not found"
[ "$ZOOKEEPER" != "" ] || die "zookeeper not found"

echo "[HOST]: $HOST"
echo "[ZK]: $ZOOKEEPER"

ES_BACKUP_CONFIG="/es-config/elasticsearch.yml"
DATA_BASE_DIR="/es-data"
export ES_ZK_PATH_ROOT="/es-mesos"
export ES_ZK_PATH_MARATHON="/marathon"

BASE_DIR=`pwd`

cfg_file="config/elasticsearch.yml";
zk_cmd="zookeepercli -servers $ZOOKEEPER " 

[ -f $cfg_file ] || die "$cfg_file `ls -lh $cfg_file` is not file"

replace_from_env() {
    prefix=$1
    delimiter=$2
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

#ES_RAW_CONFIG format:
#"a:1 \n b:2 \n c:3"
replace_from_raw() {
    name=$1
    delimiter=$2
    delimiter_trim=$(echo $delimiter|sed 's/\s//g')

    eval var=\$$name
    if [ "$var" == "" ]; then
        return
    fi
    #remove empty space
    var=`echo $var | tr -d '[:space:]'`
    #split with \n
    cfgs=(`echo -e $var`)
    for cfg in ${cfgs[@]}; do
        key=`echo "$cfg" | sed -r "s/^\s*(.*)\s*$delimiter_trim\s*(.*)\s*$/\1/"`
        val=`echo "$cfg" | sed -r "s/^\s*(.*)\s*$delimiter_trim\s*(.*)\s*$/\2/"`
        update_if_not_exist "$key" "$delimiter" "$val"
    done
}


update_if_not_exist() {
    key=$1; delimiter=$2; value="$3"
    echo $key $delimiter $value
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
    key=$1; delimiter=$2; file=$3
    if [ "$file" == "" ];then
        file=$cfg_file;
    fi
    delimiter_trim=$(echo $delimiter|sed 's/\s//g')
    awk -F $delimiter_trim "/^$key\s*$delimiter_trim\s*/{print \$2}" $file |sed 's/^\s*//'| sed 's/\s*$//'
}

zk_path_ids="$zk_path_root/ids"

#read old node name
if [ -e $ES_BACKUP_CONFIG ]; then
    echo "backup file: $ES_BACKUP_CONFIG"
    NODE_NAME=$(get_config "node.name" ":" $ES_BACKUP_CONFIG)
else
    echo "backup file  $ES_BACKUP_CONFIG not exists"
fi



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

if [[ ! -e $ES_BACKUP_CONFIG ]]; then
    #backup config if create new node
    cp -f config/elasticsearch.yml $ES_BACKUP_CONFIG
fi

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
replace_from_raw "ES_RAW_CONFIG" ": "

#backup config file
cp -f $ES_BACKUP_CONFIG "$ES_BACKUP_CONFIG.1"
cp -f config/elasticsearch.yml $ES_BACKUP_CONFIG

cat <<EOF
----------------------------------
[HOST]: $HOST
[ZK]  : $ZOOKEEPER
[NODE]: $NODE_NAME
[PORT]: $ES_TRANSPORT_PORT
---------------------------------
[$ES_BACKUP_CONFIG.1]
`cat "$ES_BACKUP_CONFIG.1" | sed 's/^/    /g'`
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

#-Dpath.home=/es-config 
./bin/elasticsearch -Des.insecure.allow.root=true || die "start es failed" &
es_pid=$!

wait $es_pid
