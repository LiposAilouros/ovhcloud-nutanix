#!/bin/bash                                                                                                                                                                                                                                                           
#set -eux
RED='\033[0;31m'
NC='\033[0m' # No Color
GREEN='\033[0;32m'        # Green
BYellow='\033[1;33m'      # Bold Yellow
set -o pipefail

CURL() {
    payload=(${@})
    METHOD=${payload[0]}
    QUERY=${ENDPOINT}${payload[1]}
    TSTAMP=$(date +%s)
    BODY=""
    if [ $METHOD != 'GET' ] || [ $METHOD != 'DELETE' ]
    then
        BODY="${payload[@]:2}"
    fi
    SHA=$(echo -n $AS+$CK+$METHOD+$QUERY+$BODY+$TSTAMP | shasum | cut -d ' ' -f 1)
    SIGNATURE="\$1\$$SHA"
    fnret=$(curl -s -X $METHOD -H "Content-type: application/json" -H "X-Ovh-Application: $AK" -H "X-Ovh-Consumer: $CK" -H "X-Ovh-Signature: $SIGNATURE" -H "X-Ovh-Timestamp: $TSTAMP" "${QUERY}" --data "${BODY}")
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
else
    echo -e "${GREEN}Api communication is OK \nYour nic is : ${nic}${NC}"
fi

