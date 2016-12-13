#!/usr/bin/env python

import os, sys, logging, time, signal, threading
from kazoo.client import KazooClient, KazooState

zk_hosts = os.environ.get("ZK", "localhost:2181")
host = os.environ.get("HOST", "localhost")
node_type = os.environ.get("NODE_TYPE", "master")
node_name = "%s-%s" % (host, node_type)
http_port = os.environ.get("PORT_HTTP", "9200")
transport_port = os.environ.get("PORT_TRANSPORT", "9300")

logging.basicConfig(level=logging.DEBUG,
                    format='[%(levelname)s] (%(threadName)-10s) %(message)s',
                    stream=sys.stdout)

zk = KazooClient(hosts=zk_hosts)

root_node = "/es-disco-nodes"
node_path = root_node + "/" + node_name

RUNNING = True

def exit_gracefully(signum, frame):
  global RUNNING
  print "Signal is received:" + str(signum)
  RUNNING = False

def zk_sync():
  zk.start()
  logging.debug("zk started")

  zk.ensure_path(root_node)
  if zk.exists(node_path):
    logging.debug("found existing node info, removing from zk")
    zk.delete(node_path, recursive=True)

  zk.create(node_path, b"")
  zk.create(node_path + "/host", b"%s" % host)
  zk.create(node_path + "/http_port", b"%s" % http_port)
  zk.create(node_path + "/transport_port", b"%s" % transport_port)
  logging.debug("zk node info written")

if __name__ == "__main__":
  signal.signal(signal.SIGINT, exit_gracefully)
  signal.signal(signal.SIGTERM, exit_gracefully)
  logging.debug("zk disco sync started")
  t0 = threading.Thread(target=zk_sync)
  t0.start()

  logging.debug("just hanging out")
  while RUNNING:
    time.sleep(10)

  t0.join()
  logging.debug("received sigterm, removing node info from zk")
  zk.delete(node_path, recursive=True)
  zk.stop()
  logging.debug("stopped zk, exiting")
  sys.exit(0)