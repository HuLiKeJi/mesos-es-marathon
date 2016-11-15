import os,sys
import urllib2
import subprocess
import re,json
import time

my_host         = os.environ.get("HOST"               , "").strip()
zk_host         = os.environ.get("ZOOKEEPER"          , "").strip()
zk_marathon     = os.environ.get("ES_ZK_PATH_MARATHON", "/marathon").strip()
zk_path_es      = os.environ.get("ES_ZK_PATH_ROOT"    , "/es-mesos").strip()
my_name         = os.environ.get("ES_NODE_NAME"       , "").strip()
transport_range = os.environ.get("ES_TRANSPORT_PORT"  , "9300-9400").strip()

assert my_name != "" and  my_host != "" and zk_host != ""

if not transport_range:
    transport_range = "9300-9400"

#write info to stderr
trace=lambda(msg): sys.stderr.write("%s\n"%msg)
trace("checking config ...")

#data stored in zookeeper
my_info={}
my_info["host"]    = os.environ.get("HOST", "")
my_info["port"]    = os.environ.get("PORTS", "")
my_info["app_id"]  = os.environ.get("MARATHON_APP_ID", "")
my_info["task_id"] = os.environ.get("MESOS_TASK_ID", "")
my_info["timestamp"] = str(int(time.time()))


def zk_cmd(*args):
    cmd=("zookeepercli -servers %s"%(zk_host)).split(" ")
    for arg in args:
        if type(arg) in (tuple, list):
              cmd += (arg)
        else:
              cmd += arg.split(" ")
    return cmd

def call_with_check(cmd):
    (code,ret)=call(cmd)
    if (code != 0):
        trace("failed to execute `%s`  %s"%(' '.join(cmd), ret))
        sys.exit(1)
    return ret

def call(cmd):
    trace("  exec: %s"%(' '.join(cmd)))
    try:
        return (0, subprocess.check_output(cmd))
    except subprocess.CalledProcessError as e:
        return (e.returncode,e.output)

#find marathon leader
trace("finding marathon leader ..")
(code, ret) = call(zk_cmd("-c ls %s/leader"%zk_marathon))
if code == 0:
    leader=re.split("\s", ret.strip())[0]
    trace("choose leader %s"%leader)
    (code, marathon_host) = call(zk_cmd("-c get %s/leader/%s"%(zk_marathon, leader)))
    marathon_host=marathon_host.strip()
else:
    trace("no marathon leader found")
    marathon_host = None

def marathon_app_tasks(appid):
    trace(resp)


#check app exist in marathon
marathon_app_task_list={}
def marathon_task_exist(app_id, task_id):
    if not marathon_host :
        return false;
    global marathon_app_task_list
    taskinfo=marathon_app_task_list.get(app_id,None)
    if not taskinfo:
        marathon_url="http://%s/v2/apps/%s/tasks"%(marathon_host, app_id)
        trace("requenst: %s"%marathon_url)
        resp=urllib2.urlopen(urllib2.Request(marathon_url)).read()
        taskinfo = marathon_app_task_list[app_id] = resp

    return taskinfo.find(task_id) != -1

#get elasticsearch nodes
def zk_get_node(node_name):
    (code,node_info)=call(zk_cmd("-c get %s/nodes/%s"%(zk_path_es, node_name)))
    if code != 0:
        trace("get node failed: %s"%node_info)
        return (-1,None)

    node_info = node_info.strip()
    try:
        node_info=json.loads(node_info)
    except ValueError,e:
        trace("not a json node: `%s` %s: %s"%(node_name, node_info, e))
        return (-1,None)

    app_id  = node_info.get("app_id", None)
    task_id = node_info.get("task_id", None)
    host    = node_info.get("host", None)
    port    = node_info.get("port", None)

    if not host:
        trace("no host found in node `%s`"%node_name)
        return (-1,None)
    else:
        return (0, node_info)

trace("update es node info in zk ...")
(code, ret)=call(zk_cmd(( "-force -c create %s/nodes/%s"%(zk_path_es, my_name)).split(" "), ["%s"%json.dumps(my_info)]))
#create failed
if code != 0:
    (ret, node_info) = zk_get_node(my_name)
    if (ret == 0):
        app_id  = node_info["app_id"]
        task_id = node_info["task_id"]
        
        try:
           if ((my_info["app_id"] != app_id or my_info["task_id"] != task_id) 
                   and marathon_task_exist(app_id, task_id)):
               trace("same es node exists and is running")
               sys.exit(1)
        except Exception,e:
            trace(e)
            pass
    trace("force update es node info in zk ...")
    ret = call_with_check(zk_cmd(( "-force -c set %s/nodes/%s"%(zk_path_es, my_name)).split(" "), ["%s"%json.dumps(my_info)]))


trace("generate es unicast host list ...")
node_list=re.split("\s+", call_with_check(zk_cmd("-c ls %s/nodes"%zk_path_es)).strip())
trace(node_list)

zen_list=[]
for node in node_list:
    trace("check node %s ..."%node)
    (ret, node_info) = zk_get_node(node)
    if (ret != 0):
       continue

    app_id    = node_info["app_id"]
    task_id   = node_info["task_id"]
    host      = node_info["host"]
    port      = node_info["port"]
    timestamp = node_info["timestamp"]

    #TODO add expire node clean
#    try:
#        marathon_task_exist(app_id, task_id)
#    except Exception, e:
#        info(e)
#        if (int(time.time()) - int(timestamp)) > 10*24*60*60:
#	    continue
    zen_list.append(host)

zen_port_list=[]
(transport_start,transport_end) = [ int(x) for x in transport_range.split("-", 2) ]

trace("generate tranport port list from %s ..."%zen_port_list)
for host in set(zen_list):
    for port in xrange(transport_start, transport_end+1):
        zen_port_list.append("%s:%s"%(host, port))

hosts='["%s"]'%('","'.join(zen_port_list))

trace(hosts)
print("\n")
sys.stdout.write(hosts)
