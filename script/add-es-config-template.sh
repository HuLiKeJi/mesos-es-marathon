#!/bin/sh
echo "{{ getv \"/xyz-config/es-$NODE_TYPE\" }}" > /etc/confd/templates/es.yml.tmpl