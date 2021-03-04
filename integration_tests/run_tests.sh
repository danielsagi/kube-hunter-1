#!/bin/bash

if [ $# -eq 0 ]; then
    echo -e "Not enough arguments.\nUsage:\n  ./run_tests.sh <kube_hunter_image> <kuberentes_version>"
    exit 1
fi

echo "[*] Trying to use kubectl..."
kubectl get pods 2> /dev/null
if [ $? -ne 0 ]; then
    echo "[-] Could not access the cluster using kubectl, Please configure your kube config."
    exit 1
fi


KUBE_HUNTER_IMAGE=$1
KUBE_VERSION=$2
NODE_EXTERNAL_IP=$(kubectl get nodes -o=custom-columns="EXTERNAL IP":.status.addresses[0].address | tail -n 1)

LOGS_DIRECTORY=/tmp/kube-hunter-logs
LOGS_OUTPUT_FILE="${LOGS_DIRECTORY}/logs_output_file.log"
JSON_OUTPUT_FILE="${LOGS_DIRECTORY}/json_output_file.log"


# JSON test files constants
EXPECTED_JSON_DIR="$(pwd)/integration_tests/expected/${KUBE_VERSION}"
REMOTE_SCAN_EXPECTED_FILE="${EXPECTED_JSON_DIR}/remote_scan.json"


# ----------- Utils -------------
compare_json_with_expected() {
    # $1 = expected json file
    echo "[*] Comparing json output with $1"
    jq --argfile a $JSON_OUTPUT_FILE --argfile b "$1" -n '($a | (.. | arrays) |= sort) as $a | ($b | (.. | arrays) |= sort) as $b | $a == $b' > /dev/null 
}

# ----------- Tests -------------
test_remote_scan() {
    echo "[*] Starting Remote Scan Test on: $NODE_EXTERNAL_IP"
    docker run -it --rm --network host -v$LOGS_DIRECTORY:$LOGS_DIRECTORY $KUBE_HUNTER_IMAGE \
        --log debug \
        --active \
        --report json \
        --log-file $LOGS_OUTPUT_FILE \
        --remote $NODE_EXTERNAL_IP \
        > $JSON_OUTPUT_FILE

    compare_json_with_expected "${EXPECTED_JSON_DIR}/remote_scan.json"
}

#####################################
# ------------ Run Tests ------------
echo "[*] Creating tmp logs directory"
mkdir $LOGS_DIRECTORY 2>/dev/null

# Test remote scan
test_remote_scan
if [ $? -eq 0 ]; then
    echo "[++] Remote Scan Passed"
else
    echo "[--] Remote Scan FAILED"
    echo "Expected: $(cat \"$REMOTE_SCAN_EXPECTED_FILE\")"
    echo "Instead Got: $(cat $JSON_OUTPUT_FILE)"
    exit 1
fi

