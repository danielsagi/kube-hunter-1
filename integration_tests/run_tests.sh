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
NODE_CONTAINER_NAME=kind-control-plane
NODE_EXTERNAL_IP=$(kubectl get nodes -o=custom-columns="EXTERNAL IP":.status.addresses[0].address | tail -n 1)

LOGS_DIRECTORY=/tmp/kube-hunter-logs
YAML_TEMPLATES_DIRECTORY=./integration_tests/yaml_templates

# This is where debug logs will output to 
LOGS_OUTPUT_FILE="${LOGS_DIRECTORY}/debug.log"
# This is where kube-hunter's report will output to
JSON_OUTPUT_FILE="${LOGS_DIRECTORY}/report.json"

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

# Runs remote scan method using a prebuilt image  
# Set $1 for additional parameters for running
test_remote_scan() {

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

# Runs kube-hunter job inside the cluster, and extracting results
test_pod_scan() {
    container_log_path=/tmp/debug.log
    node_log_path=/tmp/kube-hunter-debug.log
    args="['--pod', '--active', '--report', 'json', '--log', 'debug', '--log-file', '$LOGS_OUTPUT_FILE']"
    job_template=$(cat "$YAML_TEMPLATES_DIRECTORY/job.yaml")

    echo $(cat "$YAML_TEMPLATES_DIRECTORY/job.yaml")
    # set image in job
    job="${job_template/--image--/$KUBE_HUNTER_IMAGE}"
    echo $job
    job="${job/--args--/$args}"
    echo $job
    job="${job/--container-log-path--/$container_log_path}"
    echo $job
    job="${job/--node-log-path--/$node_log_path}"

    # apply job
    echo $args
    echo $job
    echo $job > /tmp/job.yaml
    kubectl apply -f /tmp/job.yaml
    rm /tmp/job.yaml

    # block until the end of the job
    kubectl wait --for=condition=complete job/kube-hunter
    docker cp $NODE_CONTAINER_NAME:$node_log_path $LOGS_OUTPUT_FILE
}

#####################################
# ------------ Run Tests ------------
echo "$YAML_TEMPLATES_DIRECTORY/job.yaml"
echo "[*] Creating tmp logs directory"
mkdir $LOGS_DIRECTORY 2>/dev/null

echo
echo "[*] Starting Remote Passive Scan Test on: $NODE_EXTERNAL_IP"
test_remote_scan

echo
echo "[*] Starting Remote Active Scan Test on: $NODE_EXTERNAL_IP"
test_remote_scan active
echo

echo
echo "[*] Starting Pod Active Scan Test"
test_pod_scan
