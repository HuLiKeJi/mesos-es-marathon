# Elasticsearch Dockerfile
FROM anapsix/alpine-java

MAINTAINER HuLiKeJi

ENV ES_PKG_NAME elasticsearch-5.0.2
ENV ES_HOME /opt/elasticsearch

ENV PYTHON_VERSION=2.7.12-r0
ENV PY_PIP_VERSION=8.1.2-r0
ENV SUPERVISOR_VERSION=3.3.0
ENV PY_REQUESTS_VERSION=2.12.3

# Install dependencies
RUN apk update && \
        apk add ca-certificates wget && \
        update-ca-certificates

# Install Python and supervisord
RUN apk add -u python=$PYTHON_VERSION py-pip=$PY_PIP_VERSION
RUN pip install supervisor==$SUPERVISOR_VERSION requests==$PY_REQUESTS_VERSION

# Install confd
RUN wget -q "https://github.com/kelseyhightower/confd/releases/download/v0.11.0/confd-0.11.0-linux-amd64" -O /usr/local/bin/confd

#ENV ES_CONFIG_FILE config/es-data.yml

# Download ES
RUN wget -q "https://artifacts.elastic.co/downloads/elasticsearch/${ES_PKG_NAME}.tar.gz" -O /tmp/elasticsearch.tar.gz && \
        tar xvzf /tmp/elasticsearch.tar.gz -C /tmp && \
        mv /tmp/$ES_PKG_NAME $ES_HOME && \
        rm -f /tmp/elasticsearch.tar.gz

WORKDIR $ES_HOME

# Install File Discovery Plugin
RUN bin/elasticsearch-plugin install discovery-file

#ADD script/start-es.sh       .
#ADD script/update-hosts.py   .
#RUN chmod a+x start-es.sh update-hosts.py

VOLUME ["/es-config", "/es-data"]
#CMD    ["./start-es.sh"]
EXPOSE 9200 9300

#config in /es-config, rename to avoid confusion
#RUN pwd
#WORKDIR $ES_HOME
#RUN rm              config/elasticsearch.yml
#ADD $ES_CONFIG_FILE config/elasticsearch.yml

RUN adduser -S elasticsearch root && \
    chown -R elasticsearch:root $ES_HOME

USER elasticsearch

CMD ["bin/elasticsearch"]