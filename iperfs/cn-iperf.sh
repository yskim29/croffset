#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

function print_usage() {
    >&2 echo "Usage: `basename $0` <Server Node> [iperf options]"
}

if [[ $# < 1 ]]; then 
    print_usage
    exit 1
fi
SERVER_NODE=$1; shift

if [[ ! $(kubectl get node -o name | grep "node/${SERVER_NODE}") ]]; then
    >&2 echo "[Error] Node ${SERVER_NODE} not found"
    print_usage
    exit 1
fi

echo "[Start] iperf server"
if [[ ! $(kubectl get pods -l app=iperf-server 2> /dev/null) ]]; then
    cat ${DIR}/k8s-iperf.yaml | sed -s "s/{NODE}/${SERVER_NODE}/g" | kubectl apply -f -
elif [[ $(kubectl get pod -l app=iperf-server -o jsonpath='{.items[0].metadata.labels.node}') != "${SERVER_NODE}" ]]; then
    >&2 echo "[Error] Another server had been launched."
    >&2 echo "$(kubectl get pods -l app=iperf-server -o wide)"
    exit 1
fi

until $(kubectl get pods -l app=iperf-server -o jsonpath='{.items[0].status.containerStatuses[0].ready}'); do
    echo "Waiting for iperf server to start..."
    sleep 5
done
echo

echo "[Start] iperf clients" 
CLIENTS=$(kubectl get pods -l app=iperf-client -o name | cut -d'/' -f2)
for POD in ${CLIENTS}; do
    until $(kubectl get pod ${POD} -o jsonpath='{.status.containerStatuses[0].ready}'); do
        echo "Waiting for ${POD} to start..."
        sleep 5
    done
done

for POD in ${CLIENTS}; do
    echo "[Run] iperf-client pod ${POD}"
    kubectl exec ${POD} -- iperf -c iperf-server $@ &> /dev/null &
done

until [[ $(jobs | grep -v Running) != "" ]]; do
    printf "."
    sleep 2
done
printf " done\n"

echo
kubectl logs --tail=20 -l app=iperf-server 
echo

echo "[Cleanup]"
kubectl delete --cascade -f ${DIR}/k8s-iperf.yaml
