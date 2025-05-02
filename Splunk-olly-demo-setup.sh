#!/bin/bash

#============= Prerequisites ============#
#Ensure Docker, Minikube, helm and gsed are installed. Refer to below links for installation
# https://app.us1.signalfx.com/#/gdi/scripted/TileHipstershopNonTabbed/step-1?gdiState=%7B%22integrationId%22:%22TileHipstershopNonTabbed%22%7D



setup_splunk_olly() {
    # Check if the environment already exists
    if minikube status &>/dev/null; then
        echo "Environment already exists. Please tear it down first if you want to set it up again."
        exit 1
    fi

    # Launch Minikube cluster
    minikube start --cpus=6 --memory 4096 --disk-size 32g --container-runtime=docker --vm=true --namespace='magenta'

    # Check Minikube's Docker daemon's environment variables
    minikube docker-env

    # Point your shell to minikube's docker daemon
    eval "$(minikube -p minikube docker-env)"

    git clone https://github.com/signalfx/splunk-otel-collector-chart

    # Add Helm repo splunk-otel-collector-chart to the minikube environment
    helm repo add splunk-otel-collector-chart https://signalfx.github.io/splunk-otel-collector-chart

    # Create namespace
    kubectl create namespace magenta

    # Install splunk-otel-collector-chart
    helm install my-local-splunk-o11y-otel-collector --set="splunkObservability.realm=us1,splunkObservability.accessToken=KksthzcGRxvbWMFt_BheVg,clusterName=my-local-otel-collector-cluster" splunk-otel-collector-chart/splunk-otel-collector

    # Ensure deployment is successful
    helm list -n magenta

    # Build and install the microservices demo (Hipster Shop) to run locally
    git clone https://github.com/signalfx/microservices-demo-rum
    cd ./microservices-demo-rum || exit

    # Export Real User Monitoring (RUM) Token & Realm
    export RUM_REALM=us1 RUM_AUTH=ypRMtwxuBgtZsAnDLSVgDQ

    # Create Kubernetes manifest files
    ./hack/make-release-artifacts.sh

    # Deploy the application
    kubectl apply -f ./release/kubernetes-manifests.yaml

    # Verify that the services are running and the external IP is exposed
    kubectl get pods -n magenta

    # Wait for the frontend service to be in Running state
    echo "Waiting for the 'frontend' service to be in Running state..."
    while true; do
        frontend_status=$(kubectl get pods -n magenta -l app=frontend -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
        if [ "$frontend_status" == "Running" ]; then
            echo "'frontend' service is now Running."
            break
        fi
        echo "Current status of 'frontend': $frontend_status. Retrying in 10 seconds..."
        sleep 10
    done

# Forward the port of frontend service
    kubectl port-forward deployment/frontend 8080:8080 &

    # Wait for the loadgenerator service to be in Running state
    echo "Waiting for the 'loadgenerator' service to be in Running state..."
    while true; do
        loadgenerator_status=$(kubectl get pods -n magenta -l app=loadgenerator -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
        if [ "$loadgenerator_status" == "Running" ]; then
            echo "'loadgenerator' service is now Running."
            break
        fi
        echo "Current status of 'loadgenerator': $loadgenerator_status. Retrying in 10 seconds..."
        sleep 10
    done

    # Get the nodeport and address for the loadgenerator service
    minikube service loadgenerator --url -n magenta
}

teardown_splunk_olly() {
    # Check if the environment exists
    if ! minikube status &>/dev/null; then
        echo "Environment does not exist. Nothing to tear down."
        exit 1
    fi

    # Uninstall splunk-otel-collector
    helm uninstall my-local-splunk-o11y-otel-collector

    # Scale down all deployments
    kubectl scale deployment --all=true --replicas=0 -n magenta

    # Delete all resources in the magenta namespace
    kubectl delete all --all -n magenta

    # Remove Helm repo
    helm repo remove splunk-otel-collector-chart
    # Sleep for a few seconds to ensure all resources are deleted
    sleep 5

    # Stop and delete Minikube cluster
    minikube stop
    minikube delete
    cd /Users/sudarsanam/Documents/prasad/Work/Day-Zero/workspace/splunk-olly || exit
    rm -rf microservices-demo-rum splunk-otel-collector-chart
    echo "Splunk O11y setup has been removed."
}

main() {
    if [ "$1" == "setup" ]; then
        setup_splunk_olly
    elif [ "$1" == "teardown" ]; then
        teardown_splunk_olly
    else
        echo "Usage: $0 {setup|teardown}"
        exit 1
    fi
}

# Call the main function with the first script argument
main "$@"