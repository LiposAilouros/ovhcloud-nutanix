#!/bin/bash                                                                                                                                                                                                                                                           
#set -eux
RED='\033[0;31m'
NC='\033[0m' # No Color
GREEN='\033[0;32m'        # Green
BYellow='\033[1;33m'      # Bold Yellow
set -o pipefail

ovhapirequest() {
    # curl ovhapi
    eval ${@}
    query=${ENDPOINT}${query}
    tstamp=$(date +%s)
    if [ "${method}" == 'GET' ] || [ "${method}" == 'DELETE' ]
    then
        body=""
    fi
    sha=$(echo -n $AS+$CK+${method}+${query}+${body}+${tstamp} | shasum | cut -d ' ' -f 1)
    signature="\$1\$$sha"
    fnret=$(curl -s -X $method -H "Content-type: application/json" -H "X-Ovh-Application: $AK" -H "X-Ovh-Consumer: $CK" -H "X-Ovh-Signature: $signature" -H "X-Ovh-Timestamp: $tstamp" "${query}" --data "${body}")
    echo ${fnret} | jq .
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
nic=$(ovhapirequest method='GET' query='/1.0/me' | jq -r .nichandle)
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
srv=${1}
if [ ! ${srv} ]
then
    echo -e "${RED} Server parameter is missing${NC}"
    echo -e "${RED} Usage : script.sh "server name"${NC}"
    exit 1
fi

# Test if server exists
srvid=$(ovhapirequest method='GET' query='/1.0/dedicated/server/${srv}' | jq -r .serverId)
re='^[0-9]+$'
if ! [[ ${srvid} =~ $re ]] ; then
    echo -e "${RED}Server does not exit${NC}"
    echo "${srvid}" | jq .
    exit 1
fi

#-----------------main--------------

bootid=1
echo -e "${GREEN}Setting BooId to HDD${NC}"
setshutdownbootid=$(ovhapirequest method='PUT' query='/1.0/dedicated/server/${srv}' body='{\"bootId\":\"${bootid}\",\"monitoring\":false,\"noIntervention\":false}')
echo "$setshutdownbootid"
ovhapirequest method='POST' query='/1.0/dedicated/server/$srv/reboot'
srvpowerstate=$(method='GET' query='/1.0/dedicated/server/${srv}' | jq -r .powerState)
while [ "${srvpowerstate}" != "poweron" ]
do
    echo -e "${BYellow}Waiting for server ${srv} hard Reboot task to be completed${NC}"
    sleep 10
    srvpowerstate=$(method='GET' query='/1.0/dedicated/server/${srv}' | jq -r .powerState)
done

echo -e "${GREEN}Server ${srv} is in state ${srvpowerstate}${NC}"
exit 0
