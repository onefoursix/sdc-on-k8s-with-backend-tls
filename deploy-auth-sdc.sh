#!/usr/bin/env bash

#### Set these variables ####################################

# Your Control Hub Org
SCH_ORG=

# If using StreamSets Cloud use https://cloud.streamsets.com 
SCH_URL=https://cloud.streamsetscloud.com

# Should be of the form: user@org and the user should have rights to create Data Collector auth tokens
SCH_USER=

# Password for Control Hub user, used to get an SDC auth token
SCH_PASSWORD=

# The full path to your keystore. To minimize configuration changes, it's best to name your custom keystore file "keystore.jks"
SDC_KEYSTORE_FILE=/path/to/keystore.jks

# The password for your keystore      
SDC_KEYSTORE_PASSWORD=

 # The namespace to be used (The namespace will be created if it does not exist)
KUBE_NAMESPACE=

##  End of user variables ####################################


#### Create Namespace
kubectl create namespace ${KUBE_NAMESPACE}

#### Set Context
kubectl config set-context $(kubectl config current-context) --namespace=${KUBE_NAMESPACE}

#### Create a lower-cased UUID and store it in a secret
SDC_ID=`uuidgen | tr "[:upper:]" "[:lower:]"`
echo "Generated sdc.id "${SDC_ID}
kubectl create secret generic sdc-id --from-literal=sdc.id=${SDC_ID}

#### Get an auth token for SDC and store it in a secret

# Get auth token to interact with Control Hub
SCH_AUTH_TOKEN=$(curl -s -X POST -d "{\"userName\":\"${SCH_USER}\", \"password\": \"${SCH_PASSWORD}\"}" ${SCH_URL}/security/public-rest/v1/authentication/login --header "Content-Type:application/json" --header "X-Requested-By:SDC" -c - | sed -n '/SS-SSO-LOGIN/p' | perl -lane 'print $F[$#F]')

# Get an SDC auth token from Control Hub
SDC_AUTH_TOKEN=$(curl -s -X PUT -d "{\"organization\": \"${SCH_ORG}\", \"componentType\" : \"dc\", \"numberOfComponents\" : 1, \"active\" : true}" ${SCH_URL}/security/rest/v1/organization/${SCH_ORG}/components --header "Content-Type:application/json" --header "X-Requested-By:SDC" --header "X-SS-REST-CALL:true" --header "X-SS-User-Auth-Token:${SCH_AUTH_TOKEN}" | jq '.[0].fullAuthToken')

if [ -z "$SDC_AUTH_TOKEN" ]; then
  echo "Failed to generate SDC token."
  echo "Please verify you have permissions in Control Hub"
  exit 1
fi
echo "Generated an Auth Token for SDC"

# Store the SDC auth token in a secret
kubectl create secret generic sdc-auth-token --from-literal=application-token.txt=${SDC_AUTH_TOKEN}

#### Store the custom keystore and keystore password in a secret
kubectl create secret generic sdc-keystore \
 --from-file=${SDC_KEYSTORE_FILE} \
 --from-literal=keystore-password.txt=${SDC_KEYSTORE_PASSWORD} 

#### Deploy ConfigMap for dpm.properties
kubectl apply -f yaml/dpm-configmap.yaml

#### Create SDC Deployment and Service
kubectl apply -f yaml/auth-sdc.yaml

