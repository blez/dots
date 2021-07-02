#!/bin/bash

set -o errexit
set -o xtrace

killall -9 kubectl || :
kubectl proxy &
kpid="$!"

tmp=$(mktemp -d)
endpoint="http://127.0.0.1:8001/api/v1/namespaces"
kubectl get ns | grep -E "Terminating" | awk '{print $1}' | xargs -I {} sh -c "kubectl get ns '{}' -o json > $tmp/'{}'" -- {}

if [ "$(ls -A "$tmp")" ]; then
    for i in "$tmp"/*; do
        ns=$(basename "$i")
        endpoint="http://127.0.0.1:8001/api/v1/namespaces/$ns/finalize"
        sed -i 's/\"kubernetes\"//' "$i"
        curl -Lf -k -H "Content-Type: application/json" -X PUT --data-binary @"$i" "$endpoint"
        rm "$i"
    done
else
    echo "there are no terminating namespaces"
fi

rm -rf "$tmp"
kill -9 "$kpid"
