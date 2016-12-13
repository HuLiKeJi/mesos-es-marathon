Mesos-Marathon-flavored Elasticsearch Docker Image
===

This is a docker image for running Elasticsearch 5.x on Mesos via Marathon. It supports configuration sync'ing and cluster unicast discovery via Zookeeper.

Currently tested under Mesos v1.0.1 and Marathon v1.3.3

Zookeeper Configuration Store
===

TODO: set up prefix options for confd zk 

Marathon Usage
=== 

Basically make sure you have ports allocated using Marathon with names "http" and "transport". The configuration will pick up the right environment variables.

TODO: marathon config json sample


Docker Usage
===

If you pass in the same variables as Mesos would, it should run under Docker (or other Docker orchestration tools). Below is a sample for pure docker:

```shell
docker build .

docker run -p 9200:9200 \
           -p 9300:9300 \
           -e ZK=localhost:2181 \
           -e ZK_CONFIG_PREFIX=xyz-config \
           -e ES_CLUSTER_NAME=xyz-es \
           -e NODE_TYPE=master \
           -e HOST=localhost \
           -e PORT_HTTP=9200 \
           -e PORT_TRANSPORT=9300 \
           -e ES_JAVA_OPTS="-Xms512m -Xmx512m" \
           -v /tmp/es-data:/es-data \
           -d <image_name>
```

Problem Logs
===

* bootstrap.memory_lock cannot be set to true yet. Need to know how to run ulimit under user `elasticsearch`