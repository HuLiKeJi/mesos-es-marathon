# Elasticsearch Dockerfile
FROM anapsix/alpine-java

MAINTAINER HuLiKeJi

ENV ES_PKG_NAME=elasticsearch-5.1.1 \
    ES_HOME=/opt/elasticsearch \
    PYTHON_VERSION=2.7.12-r0 \
    PY_PIP_VERSION=8.1.2-r0 \
    SUPERVISOR_VERSION=3.3.0 \
    PY_REQUESTS_VERSION=2.12.3 \
    KAZOO_VERSION=2.2.1

# Install dependencies
RUN apk update && \
        apk add ca-certificates wget && \
        update-ca-certificates

# Install Python and supervisord
RUN apk add -u python=$PYTHON_VERSION py-pip=$PY_PIP_VERSION
RUN pip install supervisor==$SUPERVISOR_VERSION requests==$PY_REQUESTS_VERSION kazoo==$KAZOO_VERSION

# Download confd
# https://github.com/kelseyhightower/confd/releases/download/v0.11.0/confd-0.11.0-linux-amd64
RUN wget -q "https://s3.cn-north-1.amazonaws.com.cn/mesos-centos-repo/confd-0.11.0-linux-amd64" -O /usr/local/bin/confd && \
    chmod a+x /usr/local/bin/confd

# Download ES
RUN wget -q "https://artifacts.elastic.co/downloads/elasticsearch/${ES_PKG_NAME}.tar.gz" -O /tmp/elasticsearch.tar.gz && \
        tar xvzf /tmp/elasticsearch.tar.gz -C /tmp && \
        mv /tmp/$ES_PKG_NAME $ES_HOME && \
        rm -f /tmp/elasticsearch.tar.gz

# Install File Discovery Plugin
WORKDIR $ES_HOME
RUN bin/elasticsearch-plugin install discovery-file
RUN mkdir -p config/discovery-file

# Setup supervisord
RUN mkdir -p /etc/supervisord
ADD config/supervisord.conf /etc/supervisord

# Setup confd
RUN mkdir -p /etc/confd/conf.d && mkdir -p /etc/confd/templates
WORKDIR /etc/confd
ADD config/es-config.toml ./conf.d
ADD config/es-discovery.toml ./conf.d
ADD config/unicast_hosts.txt.tmpl ./templates

# add es config template generation script
ADD script/add-confd-config.py /usr/local/bin
RUN chmod a+x /usr/local/bin/add-confd-config.py

# add es zk discovery script
ADD script/es-zk-disco-sync.py /usr/local/bin
RUN chmod a+x /usr/local/bin/es-zk-disco-sync.py

# create mesos sandbox path and set as volume
ENV MESOS_SANDBOX=/mnt/mesos/sandbox
RUN mkdir -p $MESOS_SANDBOX/config && \
    mkdir -p /es-data

RUN adduser -D -u 1000 -h $MESOS_SANDBOX elasticsearch root && \
    chown -R elasticsearch:root $MESOS_SANDBOX && \
    chown -R elasticsearch:root /es-data && \
    chown -R elasticsearch:root $ES_HOME && \
    chown -R elasticsearch:root /etc/confd && \
    chown -R elasticsearch:root /usr/local/bin/confd

WORKDIR $MESOS_SANDBOX

CMD ["supervisord", "-c", "/etc/supervisord/supervisord.conf"]