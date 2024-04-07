#!/bin/bash                                                                                                                                                                                                                                                           
#set -eux
RED='\033[0;31m'
NC='\033[0m' # No Color
GREEN='\033[0;32m'        # Green
BYellow='\033[1;33m'      # Bold Yellow
set -o pipefail

CURL() {
    METHOD=$1
    QUERY=${ENDPOINT}$2
    TSTAMP=$(date +%s)
    if [ $METHOD == "GET" ] || [ $METHOD == "DELETE" ]
        then
            BODY=""
            SHA=$(echo -n $AS+$CK+$METHOD+$QUERY+$BODY+$TSTAMP | shasum | cut -d ' ' -f 1)
            SIGNATURE="\$1\$$SHA"
            fnret=$(curl -s -X $METHOD -H "Content-type: application/json" -H "X-Ovh-Application: $AK" -H "X-Ovh-Consumer: $CK" -H "X-Ovh-Signature: $SIGNATURE" -H "X-Ovh-Timestamp: $TSTAMP" $QUERY)
            echo ${fnret} | jq .
        else
            BODY=$3
            SHA=$(echo -n $AS+$CK+$METHOD+$QUERY+$BODY+$TSTAMP | shasum | cut -d ' ' -f 1)
            SIGNATURE="\$1\$$SHA"
            fnret=$(curl -s -X $METHOD -H "Content-type: application/json" -H "X-Ovh-Application: $AK" -H "X-Ovh-Consumer: $CK" -H "X-Ovh-Signature: $SIGNATURE" -H "X-Ovh-Timestamp: $TSTAMP" "${QUERY}" --data "${BODY}")
            echo ${fnret} | jq .
    fi
}

# Checking token file
if [ ! -f "$(pwd)/secret.cfg" ]; then
    echo -e "${RED}Can't find $(pwd)/secret.cfg file${NC}"
    exit 1
fi
# Test jq is avalaible
if [ ! $(which jq) ]
then
    echo -e "${RED}jq binary not found try to install it${NC}"
    exit 1
fi

# Source token and endpoint
source $(pwd)/secret.cfg

# Checking Token
nic=$(CURL GET "/1.0/me" | jq -r .nichandle)
if [ ! ${nic} ] || [ ${nic} == null ]; then
    echo -e "${RED}Unable to fetch your nichandle${NC}"
    if [ ! ${AK} ] || [ ! ${CK} ] || [ ! ${ENDPOINT} ] || [ ! ${AS} ]; then
        echo -e "${RED}Missing entry in secret.cfg${NC}"
        echo -e "${BYellow}Example bellow${NC}"
        echo -e "AK='*********************'\nAS='*********************'\nCK='*********************'\nENDPOINT='https://eu.api.ovh.com'"
    else
        echo -e "${RED}Check your API token and connectivity to ${ENDPOINT}${NC}"
    fi
    exit 1
fi

# Test if parameter is present
cluster=${1}
if [ ! ${cluster} ]
then
    echo -e "${RED} cluster parameter is missing${NC}"
    echo -e "${RED} Usage : script.sh "cluster name"${NC}"
    exit 1
fi

# Todo :    define ip pool for ahv and cvm 
#           check if there is one or more server to scale up 
#           checks ips and get ips in ip pools


cvmIp="172.16.1.40"
ahvIp="172.16.0.40"
version="6.5"

# check if there is a node unconfigured ie : cvmIp = 0.0.0.0
unconfiguredcvmnumber=$(CURL GET "/1.0/nutanix/${cluster}" | jq -r '.targetSpec.nodes[]'.cvmIp | grep 0.0.0.0 | wc -l)
if [ "${unconfiguredcvmnumber}" -le "0" ]; then
    echo -e "${RED}There is no node to configure${NC}"
    exit 1
fi

# check if ips are in the same subnet as cluster
gatewaycidr=$(CURL GET "/1.0/nutanix/${cluster}" | jq -r '.targetSpec.gatewayCidr')
clustermask=$(ipcalc -b 172.16.3.254/22 | grep 'Netmask' | cut -f 4 -d ' ')
clusternetwork=$(ipcalc -b ${gatewaycidr} | grep 'Network' | cut -f 4 -d ' ')
cvmnetwork=$(ipcalc -b ${cvmIp} ${clustermask}| grep 'Network' | cut -f 4 -d ' ')
ahvnetwork=$(ipcalc -b ${ahvIp} ${clustermask}| grep 'Network' | cut -f 4 -d ' ')

if [ "${cvmnetwork}" != "${clusternetwork}" ] || [ "${ahvnetwork}" != "${clusternetwork}" ]; then
    echo "Ip are not in the same network than cluster"
    echo "Cluster Network : ${clusternetwork}"
    echo "Cvm Network : ${cvmnetwork}"
    echo "Ahv Network : ${ahvnetwork}"
    exit 1
fi

# check version
availableVersions=$(CURL GET "/1.0/nutanix/${cluster}" | jq -r '.availableVersions[]')
for availableVersion in ${availableVersions[*]}; do
    if [ "${version}" == "${availableVersion}" ]; then
        echo -e "${BYellow}Calling :${NC}"
        echo -e "${GREEN}CURL PUT /1.0/nutanix/${cluster}?scaleUp=true {"erasureCoding":false,"nodes":[{"ahvIp":"${ahvIp}","cvmIp":"${cvmIp}"}],"version":"${version}"}"
        CURL PUT "/1.0/nutanix/${cluster}?scaleUp=true" "{\"erasureCoding\":false,\"nodes\":[{\"ahvIp\":\"${ahvIp}\",\"cvmIp\":\"${cvmIp}\"}],\"version\":\"${version}\"}"
        exit 0
    fi
done
echo -e "${RED}${version} is not available${NC}"

exit 1 
