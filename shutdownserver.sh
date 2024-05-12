#!/bin/bash                                                                                                                                                                                                                                                           
#set -eux # Debug purpose
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

requestIPMIAccess() {
    publicip=$(curl -4sS ifconfig.ovh)
    echo -e "${GREEN}Requesting IPMI access for ${publicip}\n${NC}"
    ovhapirequest method='POST' query='/1.0/dedicated/server/${srv}/features/ipmi/access' body='{\"ipToAllow\":\"${publicip}\",\"ttl\":\"5\",\"type\":\"kvmipHtml5URL\"}'
    echo "$fnret" | jq .
    sleep 10
    waitingForTask
}

getIPMIAccessUrl() {
    ovhapirequest method='GET' query='/1.0/dedicated/server/${srv}/features/ipmi/access?type=kvmipHtml5URL'
    #CURL 'GET' "/1.0/dedicated/server/${srv}/features/ipmi/access?type=kvmipHtml5URL"
    url=$(echo ${fnret} | jq -r .value)
    if [ ${url} == "null" ]; then
        echo -e "${RED}${fnret}${NC}"
    else
	echo -e "${GREEN}You can follow the process by accesing the KVM${NC}"
        echo -e "\n${GREEN}KVM URL :${NC} ${RED}$url\n${NC}"
    fi
}

waitingForTask() {
    taskstatus=""
    until [ "${taskstatus}" = "done" ]; do
        taskId=$(echo "$fnret" | jq -r .taskId)
        if [ ${taskId} == "null" ]; then
            echo -e "${RED}Something went wrong${NC}"
            exit 1
        fi
        ovhapirequest method='GET' query='/1.0/dedicated/server/${srv}/task/$taskId'
        #CURL 'GET' "/1.0/dedicated/server/${srv}/task/$taskId"
        taskstatus=$(echo "$fnret" | jq -r .status)
        function=$(echo "$fnret" | jq -r .function)
        echo -e "${GREEN}Waiting for task ${function} completion${NC}"
        sleep 10
    done
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
#nic=$(CURL GET "/1.0/me" | jq -r .nichandle)
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

srvpowerstate=$(ovhapirequest method='GET' query='/1.0/dedicated/server/${srv}' | jq -r .powerState)
echo -e "${GREEN}Server ${srv} is actually ${srvpowerstate}${NC}"
if [ "${srvpowerstate}" = "poweroff" ]
then
    echo -e "${GREEN}Nothing to do, server ${srv} is already shutdown${NC}"
    exit 0
fi
echo -e "${RED}WARNING Server ${srv} will be shutdown, CTRL+C to interrup the script${NC}"
sleep 5
requestIPMIAccess
getIPMIAccessUrl 

# Get bootId "power"
bootid=$(ovhapirequest method='GET' query='/1.0/dedicated/server/${srv}/boot?bootType=power' | jq .[])
echo -e "${GREEN}Power bootid is ${bootid}${NC}"
# set "power" bootId
echo -e "${GREEN}Setting IPXE bootId ${bootid} for server ${srv}${NC}"
setshutdownbootid=$(ovhapirequest method='PUT' query='/1.0/dedicated/server/${srv}' body='{\"bootId\":\"${bootid}\",\"monitoring\":false,\"noIntervention\":false}')
echo -e "${GREEN}Rebooting server ${srv}${NC}"
ovhapirequest method='POST' query='/1.0/dedicated/server/$srv/reboot'
srvpowerstate=$(ovhapirequest method='GET' query='/1.0/dedicated/server/${srv}' | jq -r .powerState)
while [ "${srvpowerstate}" != "poweroff" ]
do
    echo -e "${BYellow}Waiting for server ${srv} to be shutdown, actual state : ${srvpowerstate}${NC}"
    sleep 10
    srvpowerstate=$(ovhapirequest method='GET' query='/1.0/dedicated/server/${srv}' | jq -r .powerState)
done
echo -e "${GREEN}Server ${srv} is in state ${srvpowerstate}${NC}"
exit 0
