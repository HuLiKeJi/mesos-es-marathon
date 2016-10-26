# Elasticsearch Dockerfile
FROM anapsix/alpine-java

MAINTAINER HuLiKeJi

ENV ES_PKG_NAME elasticsearch-2.3.2
ENV ES_HOME /elasticsearch

# Install Elasticsearch.
RUN apk update && \
        apk add ca-certificates wget&& \
        update-ca-certificates
RUN cd / && \
        wget https://download.elasticsearch.org/elasticsearch/elasticsearch/$ES_PKG_NAME.tar.gz && \
        tar xvzf $ES_PKG_NAME.tar.gz && \
        rm -f $ES_PKG_NAME.tar.gz && \
        mv /$ES_PKG_NAME /elasticsearch

WORKDIR $ES_HOME
RUN ./bin/plugin install lmenezes/elasticsearch-kopf/2.0
RUN ./bin/plugin install hlstudio/bigdesk/v2.2.a

RUN apk add python

#zookeepercli
RUN wget "https://github.com/HuLiKeJi/zookeepercli/releases/download/v1.0.11/zookeepercli-linux.tgz" -O zookeepercli.tgz && \
         tar -xvf zookeepercli.tgz -C /usr/bin && \
         chmod a+x /usr/bin/zookeepercli && \
         rm  zookeepercli.tgz

ENV ES_CONFIG_FILE config/es-data.yml

WORKDIR $ES_HOME
ADD script/start-es.sh       .
ADD script/update-hosts.py   .
RUN chmod a+x start-es.sh update-hosts.py

VOLUME ["/es-config", "/es-data"]
CMD    ["./start-es.sh"]
EXPOSE 9200 9300

#config in /es-config, rename to avoid confusion
RUN pwd
WORKDIR $ES_HOME
RUN rm              config/elasticsearch.yml
ADD $ES_CONFIG_FILE config/elasticsearch.yml
