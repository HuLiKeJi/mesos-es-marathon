#!/bin/bash

RELEASE_TAG=${RELEASE_TAG:-latest}

echo "building master ..."
docker build -t es-cluster-master:$RELEASE_TAG -f es.dockerfile --build-arg ES_CONFIG_FILE=config/es-master.yml .

echo "building slave ..."
docker build -t es-cluster-data:$RELEASE_TAG   -f es.dockerfile --build-arg ES_CONFIG_FILE=config/es-data.yml .

echo "done"
