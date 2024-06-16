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


# Checking script usage
if [ ! ${1} ]; then
    echo "-----Missing cluster Name-----"
    echo "Usage : bash script.sh ovhcloud cluster name"
    echo "Example : script.sh cluster-nnnn.ovh.us"
    exit 1
fi

# Checking token file
if [ ! -f "$(pwd)/secret.cfg" ]; then
    echo "Can't find secret.cfg file"
    exit 1
fi

# Source token and endpoint
source $(pwd)/secret.cfg

# Checking Token
nic=$(CURL GET "/1.0/me" | jq -r .nichandle)
if [ ! ${nic} ]; then
    echo -e "${RED}Unable to fetch your nichandle${NC}"
    echo -e "${BYellow}Returned error :${NC}"
    echo "$fnret" | jq .
    if [ ! $AK ] || [ ! $CK ] || [ ! $ENDPOINT ] || [ ! $AS ]; then
        echo -e "${RED}Missing entry in secret.cfg${NC}"
        echo -e "${BYellow}Example bellow${NC}"
        echo -e "AK='*********************'\nAS='*********************'\nCK='*********************'\nENDPOINT='https://eu.api.ovh.com'"
    else
        echo -e "${RED}Check your API token and connectivity to ${ENDPOINT}${NC}"
    fi
    exit 1
fi

# Setting Variables
serviceName="${1}"
region='europe'
ovhSubsidiary='FR'
if [ "${ENDPOINT}" == "https://api.us.ovhcloud.com" ]; then 
    region='united_states'
    ovhSubsidiary='US'
fi
if [ "${ENDPOINT}" == "https://ca.api.ovh.com" ]; then 
    region='canada'
    ovhSubsidiary='CA'
fi

ram= # OPTIONAL, Possible value  "1536g",  "384g", "768g", 192g
quantity=1 # Do not change until OVHcloud fixes issue
echo -e "${GREEN}Creating Cartid${NC}"
cartId=$(curl -sS "${ENDPOINT}/1.0/order/cart" --compressed -X POST -H 'Accept: application/json' -H 'Accept-Language: en-US,en;q=0.5' -H 'Accept-Encoding: gzip, deflate, br' -H 'Content-Type: application/json;charset=utf-8' -H 'Connection: keep-alive' -H 'Referer: https://api.us.ovhcloud.com/console/' --data-raw "{\"ovhSubsidiary\":\"${ovhSubsidiary}\"}" | jq -r .cartId)
echo -e "${GREEN}Cartid :  ${cartId}\n${NC}"

# Assign a shopping cart to an logged in client
CURL POST "/1.0/order/cart/${cartId}/assign" "" | sed -e s/'null'/'Cartid assigned to your account'/g

# Getting one server part of the cluster, get serviceId, get planCode, duration and options
server=$(CURL GET "/1.0/nutanix/${serviceName}" | jq -r .targetSpec.nodes | jq -r '.[].server' | head -n 1)
datacenter=$(CURL GET "/1.0/dedicated/server/${server}" | jq -r .datacenter | grep -oE '[a-z]{3}')
echo -e "${GREEN}${quantity}new server(s) will be ordered as ${server}, part of cluster : ${serviceName}, in the datacenter ${datacenter}${NC}"
echo -e "${RED}Do you want to continue ?${NC}"
echo -e "${BYellow}Press any key to continue or CTRL+C to cancel${NC}"
read -p ""

serviceId=$(CURL GET "/1.0/nutanix/${serviceName}/serviceInfos" | jq -r .serviceId)
plancode=$(CURL GET "/1.0/services/${serviceId}/options" | jq -r "[.[] | select ( .resource.name | contains(\"$server\")) | .billing.plan.code]" | jq -r '.[]')
echo -e "${GREEN}Selected plan code :  ${plancode}${NC}"
duration=$(CURL GET "/1.0/services/${serviceId}/options" | jq -r '.[].billing.pricing.duration' | sort -u)
echo -e "${GREEN}Selected duration :  ${duration}${NC}"
serviceId=$(CURL GET "/1.0/dedicated/server/${server}/serviceInfos" | jq -r .serviceId)
options=$(CURL GET "/1.0/services/${serviceId}/options" | jq -r '.[].billing.plan.code')
#echo -e "${GREEN}Options :  ${options}${NC}\n"
# 4. POST /order/cartServiceOption/nutanix/{serviceName}
itemId=$(CURL POST "/1.0/order/cartServiceOption/nutanix/${serviceName}" "{\"cartId\": \"${cartId}\",\"duration\": \"${duration}\",\"planCode\": \"${plancode}\",\"pricingMode\": \"default\",\"quantity\": ${quantity}}" | jq -r .itemId)
echo -e "${GREEN}ItemId :  ${itemId}${NC}"
CURL POST "/1.0/order/cart/${cartId}/item/${itemId}/configuration" "{\"label\": \"dedicated_datacenter\",\"value\": \"${datacenter}\"}"
CURL POST "/1.0/order/cart/${cartId}/item/${itemId}/configuration" "{\"label\": \"region\",\"value\": \"${region}\"}"
CURL POST "/1.0/order/cart/${cartId}/item/${itemId}/configuration" "{\"label\": \"dedicated_os\",\"value\": \"none_64.en\"}"
for option in ${options[*]}; do
    if [ "$(echo $option | grep -oE 'ram')" == 'ram' ]; then
        if [ "${ram}" ]; then
            option=$(CURL GET "/1.0/order/cart/${cartId}/nutanix/options?planCode=${plancode}" | jq -r "[.[] | select ( .planCode | contains(\"ram-${ram}\")) | .planCode]" | jq -r '.[]')
        fi
        echo -e "${GREEN}${option}${NC}"
    fi
    echo -e "${GREEN}Setting option : $option${NC}\n"
    CURL POST "/1.0/order/cart/${cartId}/nutanix/options" "{\"duration\": \"${duration}\",\"itemId\": ${itemId},\"planCode\": \"${option}\",\"pricingMode\": \"default\",\"quantity\": 1}"
done
echo -e "${BYellow}Follow the link below to finish the order${NC}\n"
CURL POST "/1.0/order/cart/${cartId}/checkout" "{\"autoPayWithPreferredPaymentMethod\": false,\"waiveRetractationPeriod\": false}" | jq .url
