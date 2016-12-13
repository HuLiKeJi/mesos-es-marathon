#!/usr/bin/env python

import os

confd_toml_location = "/etc/confd/confd.toml"
es_yml_tmpl_location = "/etc/confd/templates/es.yml.tmpl"

confd_toml = '''
backend = "zookeeper"
confdir = "/etc/confd"
log-level = "debug"
interval = 120
nodes = [
%s
]
noop = false
sync-only = true
prefix = "%s"
'''

es_yml_tmpl = '''{{ getv "/es-%s" }}'''

zk_nodes = "\n".join(map(lambda x: '  "%s",' % (x), os.environ.get("ZK", "localhost:2181").split(",")))
prefix = os.environ.get("ZK_CONFIG_PREFIX", "/xyz-config")
node_type = os.environ.get("NODE_TYPE", "master")

with open(confd_toml_location, "w") as f:
  f.write(confd_toml % (zk_nodes, prefix))

with open(es_yml_tmpl_location, "w") as f:
  f.write(es_yml_tmpl % (node_type))
