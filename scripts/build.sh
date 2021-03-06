#!/bin/bash
set -eo pipefail
shopt -s nullglob
set -o xtrace

tag=$(docker build -t percona-xtradb-cluster-operator:K8SPXC-172-pxc8.0 . | grep -E "^Successfully built .*" | awk '{print $3}')
echo "$tag"
docker tag "$tag" perconalab/percona-xtradb-cluster-operator:K8SPXC-172-pxc8.0
docker push perconalab/percona-xtradb-cluster-operator:K8SPXC-172-pxc8.0
