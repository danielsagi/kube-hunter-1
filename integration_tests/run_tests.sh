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

# ------------- Tests Variables ----------------
KUBE_HUNTER_IMAGE=$1
KUBE_VERSION=$2
NODE_EXTERNAL_IP=$(kubectl get nodes -o=custom-columns="EXTERNAL IP":.status.addresses[0].address | tail -n 1)

LOGS_DIRECTORY=/tmp/kube-hunter-logs
LOGS_OUTPUT_FILE="${LOGS_DIRECTORY}/logs_output_file.log"
JSON_OUTPUT_FILE="${LOGS_DIRECTORY}/json_output_file.log"

# JSON test files constants
EXPECTED_JSON_DIR="$(pwd)/integration_tests/expected/${KUBE_VERSION}"


# ----------- Utils -------------
compare_json_with_expected() {
    # $1 = expected json file
    echo "[*] Comparing json output with $1"
    jq --argfile a $JSON_OUTPUT_FILE --argfile b "$1" -e -n '($a | (.. | arrays) |= sort) as $a | ($b | (.. | arrays) |= sort) as $b | $a == $b' > /dev/null 
}

print_red() {
    printf "\033[0;31m$1\033[0m\n" 
}

print_green() {
    printf "\033[0;32m$1\033[0m\n" 
}

# ----------- Tests -------------
test_remote_scan() {
    # set $1 for additional parameters for running

    active_flag=""
    expected_file="${EXPECTED_JSON_DIR}/remote_scan.json"
    if [[ $1 = "active" ]]; then
        active_flag="--active"
        expected_file="${EXPECTED_JSON_DIR}/remote_scan_active.json"
    fi

    # Run the image on remote scan towards node's ip 
    cmd="docker run -it --rm --network host -v$LOGS_DIRECTORY:$LOGS_DIRECTORY $KUBE_HUNTER_IMAGE \
        --log debug \
        --report json \
        --log-file $LOGS_OUTPUT_FILE \
        --remote $NODE_EXTERNAL_IP \
        $active_flag \
        "
    $cmd > $JSON_OUTPUT_FILE

    compare_json_with_expected "$expected_file"

    if [ $? -eq 0 ]; then
        print_green "[++] Passed"
    else
        print_red "[--] FAILED"
        print_red "Expected: $(cat \"$REMOTE_SCAN_EXPECTED_FILE\")"
        print_red "Instead Got: $(cat $JSON_OUTPUT_FILE)"
        exit 1
    fi
}

# test_pod_scan() {

# }

#####################################
# ------------ Run Tests ------------
echo "[*] Creating tmp logs directory"
mkdir $LOGS_DIRECTORY 2>/dev/null

echo
echo "[*] Starting Remote Passive Scan Test on: $NODE_EXTERNAL_IP"
test_remote_scan

echo
echo "[*] Starting Remote Active Scan Test on: $NODE_EXTERNAL_IP"
test_remote_scan active
echo
