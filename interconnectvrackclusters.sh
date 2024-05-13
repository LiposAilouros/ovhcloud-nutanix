#/bin/bash
#set -eux # Debug purpose

# --------------------------------------------------------
#                   Christmas three
# --------------------------------------------------------
RED='\033[0;31m'
NC='\033[0m'                # No Color
GREEN='\033[0;32m'          # Green
BGREEN='\033[1;32m'         # Green
BLUE='\033[0;34m'           # Blue
BYellow='\033[1;33m'        # Bold Yellow
BPurple='\033[1;35m'        # Bold Purple
# TODO create container on both clusters "storageprod" migrate vm on source on this storage except cvm prismcentral(?)

clusterdestination=''
clusterdestinationpassword=''
clustersource=''
clustersourcepassword=''


# functions

print_help() {                                                                                                                                                               
    #echo "Utilisation: $0 -s server_name -u utilisateur -p mot_de_passe -x action1 -z action2"
    echo -e "${BYellow}********************************************************************************************************${NC}"
    echo -e "${BYellow}Usage : $0 clusterdestination='cluster-xxxx.nutanix.ovh.xx' clusterdestinationpassword='' clustersource='cluster-xxxx.nutanix.ovh.xx' clustersourcepassword=''${NC}"
    echo -e "${BYellow}********************************************************************************************************${NC}"
}

CURLOVHAPI() {
    # curl ovhapi 
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

CURLNTNXAPI() {
    eval ${@}
    if [ ${method} == "GET" ] || [ ${method} == "DELETE" ]
        then
            curl -sS -k -H Accept:application/json -H Content-Type:application/json -u "${user}:${password}" -X ${method} https://"${cluster}":9440/${query}
        else
            curl -sS -k -H Accept:application/json -H Content-Type:application/json -u "${user}:${password}" -X ${method} https://"${cluster}":9440/${query} -d ${body}
    fi
}

SSH() {
    payload=(${@})
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $DIR/keytmp ${payload[@]:0}
}

GetAttr() {
    attribute="$1"
    metadataFile="$2"
    jq -r ".${attribute} // empty" "${metadataFile}" 2>/dev/null
}

poweroffvm()
{
    eval ${@}
    # Get OVHgateway VM uuid
    vmuuid=$(CURLNTNXAPI cluster="${cluster}" user="${user}" password="${password}" method="POST" query="api/nutanix/v3/vms/list" body="{}" | jq -r "[.entities[] | select( .spec.name | contains(\"${vmname}\")) | .metadata.uuid][0]")
    echo $vmuuid
    CURLNTNXAPI cluster="${cluster}" user="${user}" password="${password}" method="POST" query="api/nutanix/v3/vms/${vmuuid}/acpi_shutdown" body="{}"
}

connectAZ() {
    eval ${@}
    fnret=$(CURLNTNXAPI cluster="${cluster}" user="${user}" password="${password}" method="POST" query="api/nutanix/v3/cloud_trusts" body='{\"spec\":{\"name\":\"\",\"resources\":{\"url\":\"${distantpcip}\",\"username\":\"${user}\",\"password\":\"${distantpcpassword}\",\"cloud_type\":\"ONPREM_CLOUD\"},\"description\":\"\"},\"metadata\":{\"kind\":\"cloud_trust\"},\"api_version\":\"3.1.0\"}')
    if [ "$(echo ${fnret} | jq -r '.state')" == "ERROR" ]; then
        echo -e "${RED}Cannot create AZ\n${fnret}"
        exit 1
    fi

}

GETVRACKTASKSTATUS() {
    vracktaskid=${1}
    echo -e "${BYellow}GET /1.0/vrack/${vrack}/task/${vracktaskid}${NC}"
    vracktask=$(CURLOVHAPI GET "/1.0/vrack/${vrack}/task/${vracktaskid}")
    echo "${vracktask}" | jq .
    vracktaskstatus=$(echo "${vracktask}" | jq -r .status)
    echo -e "${RED}task status : $vracktaskstatus ${NC}"
    until [ "${vracktaskstatus}" = "done" ] || [ "${vracktaskstatus}" = "null" ]
    do
        echo -e "${BYellow}GET /1.0/vrack/${vrack}/task/${vracktaskid}${NC}"
        vracktaskstatus=$(CURLOVHAPI GET "/1.0/vrack/${vrack}/task/${vracktaskid}" | jq -r .status)
        echo -e "${GREEN}Waiting for task $(echo "${vracktask}" | jq -r .function) to be done, task status : $vracktaskstatus ${NC}" | sed -e s/null/done/g
        sleep 5
    done
    echo -e "${RED}${NC}"
}

GETIPLBTASKSTATUS() {
    taskid=${1}
    echo -e "${BYellow}GET /1.0/ipLoadbalancing/${iplb}/task/${taskid}${NC}"
    task=$(CURLOVHAPI GET "/1.0/ipLoadbalancing/${iplb}/task/${taskid}")
    echo "${task}" | jq .
    taskstatus=$(echo "${task}" | jq -r .status)
    echo -e "${RED}task status : $taskstatus ${NC}"
    until [ "${taskstatus}" = "done" ] || [ "${taskstatus}" = "null" ]
    do
        echo -e "${GREEN}Waiting for task $(echo "${task}" | jq -r .action) to be done${NC}"
        taskstatus=$(CURLOVHAPI GET "/1.0/ipLoadbalancing/${iplb}/task/${taskid}" | jq -r .status)
        echo -e "${RED}task status : $taskstatus ${NC}" | sed -e s/null/done/g
        sleep 5
    done
    echo -e "${RED}${NC}"
}

cleanVrack () {
    eval ${@}
    encodedipfo=$(echo "${ipfo}" | sed -e s/'\/'/%2F/g)
    echo -e "${BLUE}Cleaning vRack : ${vrack}${NC}"
    echo -e "${BGREEN}Cleaning vRack ${vrack} from Servers${NC}"
    echo -e "${GREEN} Server(s) in vRack ${vrack} : $(CURLOVHAPI GET "/1.0/vrack/${vrack}/dedicatedServerInterfaceDetails" | jq -r .[])${NC}"
    echo -e "${BYellow}GET /1.0/vrack/${vrack}/dedicatedServerInterfaceDetails | jq -r .[]${NC}"
    dedicatedServerInterfaceDetails=$(CURLOVHAPI GET "/1.0/vrack/${vrack}/dedicatedServerInterfaceDetails"| jq -r .[])
    #echo -e "${BPurple}InterfaceDetails : ${dedicatedServerInterfaceDetails}${NC}"
    dedicatedServerInterfaces=$(echo ${dedicatedServerInterfaceDetails} | jq -r .dedicatedServerInterface)
    #echo -e "${BPurple}Server Interface : ${dedicatedServerInterfaces}${NC}"
    for dedicatedServerInterface in ${dedicatedServerInterfaces[@]}
    do
        #echo "${dedicatedServerInterface}"
        echo -e "${BYellow}DELETE /1.0/vrack/${vrack}/dedicatedServerInterface/${dedicatedServerInterface}${NC}"
        vracktask=$(CURLOVHAPI DELETE "/1.0/vrack/${vrack}/dedicatedServerInterface/${dedicatedServerInterface}")
        #echo -e "${BPurple}${vracktask}${NC}"
        vracktaskid=$(echo "${vracktask}" | jq -r .id)
        if [ "${vracktaskid}" ]
        then
            GETVRACKTASKSTATUS "${vracktaskid}"
            echo -e "${GREEN}Server removed from vRack ${vrack} ${NC}"
        else
            echo -e "${RED} Cannot remove Server from vRack ${vrack} ${NC}"
            echo $vracktask
        fi
    done
    ##### clean vRack IPLB #####
    echo -e "${BGREEN}Cleaning IPLB from vRack ${vrack}${NC}"
    echo -e "${BYellow}DELETE /1.0/vrack/${vrack}/ipLoadbalancing/${iplb}${NC}"
    vracktask=$(CURLOVHAPI DELETE "/1.0/vrack/${vrack}/ipLoadbalancing/${iplb}")
    #echo -e "${BPurple}${vracktask}${NC}"
    vracktaskid=$(echo "${vracktask}" | jq -r .id)
    if [ "${vracktaskid}" ]
    then
        GETVRACKTASKSTATUS "${vracktaskid}"
        echo -e "${GREEN}ipLoadbalancing ${iplb} removed from vRack ${vrack}${NC}"
    else
        echo -e "${RED}Cannot remove ipLoadbalancing ${iplb} from vRack ${vrack}${NC}"
    fi
    ##### clean vRack IPFO #####
    echo -e "${BGREEN}Cleaning vRack ${vrack} from IPFO${NC}"
    echo -e "${BYellow}DELETE /1.0/vrack/${vrack}/ip/${encodedipfo}${NC}"
    vracktask=$(CURLOVHAPI DELETE "/1.0/vrack/${vrack}/ip/${encodedipfo}")
    #echo -e "${BPurple}${vracktask}${NC}"
    vracktaskid=$(echo "${vracktask}" | jq -r .id)
    GETVRACKTASKSTATUS "${vracktaskid}"
    echo -e "${GREEN}ip ${ipfo} removed from vRack ${vrack}${NC}"
}

addServersToVrack () {
    payload=(${@})
    VRACK=$1
    vrack=$1 # quickfix
    SERVERS="${payload[@]:1}"
    echo ${SERVERS[@]}
    echo -e "${BLUE}****function: addServersToVrack***${NC}"
    for server in ${SERVERS[@]}
    do
        echo -e "${BGREEN}Adding ${server} to vRack : ${VRACK} ${NC}"
        echo -e "${BYellow}GET /1.0/vrack/${VRACK}/allowedServices?serviceFamily=dedicatedServerInterface${NC}"
        alloweddedicatedServerInterface=$(CURLOVHAPI GET "/1.0/vrack/${VRACK}/allowedServices?serviceFamily=dedicatedServerInterface")
        dedicatedServerInterface=$(echo ${alloweddedicatedServerInterface} | jq -r ".dedicatedServerInterface[] | select( .dedicatedServer==\"${server}\") .dedicatedServerInterface")
        #echo -e "${RED}$server : $dedicatedServerInterface${NC}"
        if [ $dedicatedServerInterface ]
        then
            echo -e "${BYellow}POST /1.0/vrack/${VRACK}/dedicatedServerInterface {\"dedicatedServerInterface\": \"${dedicatedServerInterface}\"}${NC}"
            vracktaskid=$(CURLOVHAPI POST "/1.0/vrack/${VRACK}/dedicatedServerInterface" "{\"dedicatedServerInterface\": \"${dedicatedServerInterface}\"}" | jq -r .id)
            GETVRACKTASKSTATUS "${vracktaskid}"
            echo -e "${GREEN}${server} added to vRack ${VRACK}${NC}"
        else
            echo -e "${BYellow}${NC}"
            echo -e "${RED}Can't add ${server} to vRack ${VRACK}${NC}"
            # checking if vrack aggregation is enable for server
            echo -e "${BYellow}GET /1.0/dedicated/server/${server}/virtualNetworkInterface?enabled=true&mode=vrack_aggregation${NC}"
            uuid=$(CURLOVHAPI GET "/1.0/dedicated/server/${server}/virtualNetworkInterface?enabled=true&mode=vrack_aggregation" | jq -r .[])
            if [ "${uuid}" ]
                then
                    echo -e "${BYellow}GET /1.0/dedicated/server/${server}/virtualNetworkInterface/${uuid}${NC}"
                    serversvrack=$(CURLOVHAPI GET "/1.0/dedicated/server/${server}/virtualNetworkInterface/${uuid}" | jq -r .vrack)
                    echo -e "${RED}Server ${server} is already in vRack ${serversvrack}${NC}"
                else
                    echo -e "${RED}Can't find root cause check api response${NC}"
                    echo ${alloweddedicatedServerInterface} | jq .
                    exit
            fi
    fi

    done
}

attachIpfoToVrack () {
    eval ${@}
    encodedipfo=$(echo "${ipfo}" | sed -e s/'\/'/%2F/g)
    #echo -e "${BLUE}function: attachIpfoToVrack${NC}"
    echo -e "${BGREEN}Adding ${ipfo} to vRack : ${vrack}${NC}"
    echo -e "${BYellow}POST /1.0/vrack/${vrack}/ip { \"block\": \"${ipfo}\" }${NC}"
    vracktaskid=$(CURLOVHAPI POST "/1.0/vrack/${vrack}/ip" "{ \"block\": \"${ipfo}\" }" | jq -r .id)
    GETVRACKTASKSTATUS "${vracktaskid}"
    echo -e "${BYellow}GET /1.0/vrack/${vrack}/ip/${encodedipfo}/availableZone${NC}"
    zone=$(CURLOVHAPI GET "/1.0/vrack/${vrack}/ip/${encodedipfo}/availableZone" | jq -r .[])
    echo -e "${BYellow}POST /1.0/vrack/${vrack}/ip/${encodedipfo}/announceInZone { \"zone\": \"${zone}\" }${NC}"
    vracktaskid=$(CURLOVHAPI POST "/1.0/vrack/${vrack}/ip/${encodedipfo}/announceInZone" "{ \"zone\": \"${zone}\" }" | jq -r .id)
    GETVRACKTASKSTATUS "${vracktaskid}"
}

attachIplbToVrack () {
    eval ${@}
    #echo -e "${BLUE}####function: addIpLoadBalancerToVrack####${NC}"
    echo -e "${BGREEN}Adding ${iplb} to vRack : ${vrack} ${NC}"
    echo -e "${BYellow}${NC}"
    echo -e "${BYellow}POST /1.0/vrack/${vrack}/ipLoadbalancing { \"ipLoadbalancing\": \"${iplb}\" }${NC}"
    vracktaskid=$(CURLOVHAPI POST "/1.0/vrack/${vrack}/ipLoadbalancing" "{ \"ipLoadbalancing\": \"${iplb}\" }" | jq -r .id)
    GETVRACKTASKSTATUS "${vracktaskid}"
}

getIplbPrivateNetworkNatip () {
    eval ${@}
    #CURLOVHAPI GET "/1.0/ipLoadbalancing/${iplb}/vrack/network" | jq -r '.[]'
    iplbcallid=$(CURLOVHAPI GET "/1.0/ipLoadbalancing/${iplb}/vrack/network" | jq -r '.[]' )
    #CURLOVHAPI GET "/1.0/ipLoadbalancing/${iplb}/vrack/network/$iplbcallid" | jq -r '.[]'
    if [ "${iplbcallid}" ]; then
        natip=$(CURLOVHAPI GET "/1.0/ipLoadbalancing/${iplb}/vrack/network/$iplbcallid" | jq -r '.natIp')
        natipbase=$(ipcalc -b ${natip} | grep Address | /usr/bin/grep -oE '[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.')
        natipbroadcastlastdigit=$(ipcalc -b ${natip} | grep Broadcast | /usr/bin/grep -oE '[0-9]{1,3}' | tail -n 1)
        natip="${natipbase}$((natipbroadcastlastdigit + 1))/27"
    else
        natipbase=$(echo "${gatewayCidr}" | /usr/bin/grep -oE '[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.' | head -n 1)
        natip="${natipbase}128/27"
    fi
    #echo $natip
}

setupIplbPrivateNetwork () {
    eval ${@}
    #echo -e "${BLUE}####function: setupIplbConfigurationWithVrack####${NC}"
    echo -e "${BGREEN}dding private network${NC}"
    echo -e "${BYellow}POST /1.0/ipLoadbalancing/${iplb}/vrack/network {\"displayName\": \"nutanix2\", \"natIp\": \"${natip}\", \"subnet\": \"${subnet}\", \"vlan\": \"${vlan}\"}${NC}"
    iplbcall=$(CURLOVHAPI POST "/1.0/ipLoadbalancing/${iplb}/vrack/network" "{ \"displayName\": \"nutanix2\", \"natIp\": \"${natip}\", \"subnet\": \"${subnet}\", \"vlan\": \"${vlan}\"}")
    #echo -e "${BPurple}${iplbcall}${NC}"
    iplbcallid=$(CURLOVHAPI GET "/1.0/ipLoadbalancing/${iplb}/vrack/network" | jq -r '.[]' )
    vrackNetworkId=$(echo ${iplbcall} | jq .vrackNetworkId)
    tcpfarmid=$(CURLOVHAPI GET "/1.0/ipLoadbalancing/${iplb}/tcp/farm" | jq -r '.[]' )
    #echo $tcpfarmid
    sleep 15
    echo -e "${BGREEN}Updating Farm${NC}"
    echo -e "${BYellow}POST /1.0/ipLoadbalancing/${iplb}/vrack/network/${iplbcallid}/updateFarmId {\"farmId\":[\"${tcpfarmid}\"]} ${NC}"
    iplbcall=$(CURLOVHAPI POST "/1.0/ipLoadbalancing/${iplb}/vrack/network/${iplbcallid}/updateFarmId" "{\"farmId\":[\"${tcpfarmid}\"]}")
    #echo -e "${BPurple}${iplbcall}${NC}"
    vrackNetworkId=$(echo ${iplbcall} | jq .vrackNetworkId)
    echo -e "${BGREEN}Refresh IPLB${NC}"
    echo -e "${BYellow}POST /1.0/ipLoadbalancing/${iplb}/refresh${NC}"
    iplbcall=$(CURLOVHAPI POST "/1.0/ipLoadbalancing/${iplb}/refresh" "")
    #echo -e "${BPurple}${iplbcall}${NC}"
    taskid=$(echo "${iplbcall}" | jq .id)
    GETIPLBTASKSTATUS "${taskid}"
}

cleanIplbPrivateNetwork () {
    eval ${@}
    echo -e "${BGREEN}####Deleting Private Network####${NC}"
    echo -e "${BYellow}GET /1.0/ipLoadbalancing/${iplb}/vrack/network${NC}"
    iplbcallid=$(CURLOVHAPI GET "/1.0/ipLoadbalancing/${iplb}/vrack/network" | jq -r '.[]' )
    echo -e "${BPurple}${iplbcallid}${NC}"
    if [ "${iplbcallid}" ]
        then
            echo -e "${BYellow}POST /1.0/ipLoadbalancing/${iplb}/vrack/network/${iplbcallid}/updateFarmId {\"farmId\":[]}${NC}"
            iplbcall=$(CURLOVHAPI "POST" "/1.0/ipLoadbalancing/${iplb}/vrack/network/${iplbcallid}/updateFarmId" "{\"farmId\":[]}")
            #echo -e "${BPurple}${iplbcall}${NC}"
            sleep 10
            iplbcall=$(CURLOVHAPI POST "/1.0/ipLoadbalancing/${iplb}/refresh" "")
            echo -e "${BPurple}${iplbcall}${NC}"
            taskid=$(echo "${iplbcall}" | jq .id)
            GETIPLBTASKSTATUS "${taskid}"
            echo -e "${BPurple}${iplbcall}${NC}" | sed -e s/"null"/"done"/g
            echo -e "${BYellow}DELETE /1.0/ipLoadbalancing/${iplb}/vrack/network/${iplbcallid}${NC}"
            iplbcall=$(CURLOVHAPI DELETE /1.0/ipLoadbalancing/${iplb}/vrack/network/${iplbcallid})
            iplbcallid=$(echo "${iplbcall}" | jq -r .id)
            #GETIPLBTASKSTATUS "${iplbcallid}"
            echo -e "${BPurple}${iplbcall}${NC}" | sed -e s/"null"/"done"/g
        else
            echo "nothing to delete"
    fi
}


# *****************main****************

# Test jq/ipcalc installation
if [ ! $(which jq) ] || [ ! $(which ipcalc) ]; then
    echo -e "${RED}jq binary or ipcal not found, try to install it${NC}"
    exit 1
fi

# Checking token file
if [ ! -f "$(pwd)/secret.cfg" ]; then
    echo -e "${RED}Can't find $(pwd)/secret.cfg file${NC}"
    exit 1
fi

# Source token and endpoint
source $(pwd)/secret.cfg

# Checking Token
echo -e "${GREEN}Checking OVHcloud API${NC}"
nic=$(CURLOVHAPI GET "/1.0/me" | jq -r .nichandle)
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

# getting variables in command line
eval ${@}
if [ ! ${clusterdestination} ] || [ ! ${clusterdestinationpassword} ] || [ ! ${clustersource} ] || [ ! ${clustersourcepassword} ]; then
    print_help
    exit 1
fi

# check nutanix API
echo -e "${GREEN}Checking Nutanix API"
curl -s https://${clustersource}:9440
if [ "$?" != 0 ];then
    echo -e "${RED}Check connectivity for cluster : ${clustersource}"
    exit 1
fi
curl -s https://${clusterdestination}:9440
if [ "$?" != 0 ];then
    echo -e "${RED}Check connectivity for cluster : ${clusterdestination}"
    exit 1
fi

statussource=$(CURLNTNXAPI cluster="${clustersource}" user="admin" password="${clustersourcepassword}" method="POST" query="api/nutanix/v3/clusters/list" body="{}" | jq -r '.state')
statusdestination=$(CURLNTNXAPI cluster="${clusterdestination}" user="admin" password="${clusterdestinationpassword}" method="POST" query="api/nutanix/v3/clusters/list" body="{}" | jq -r '.state')
if [ ${statussource} != 'null' ] || [ ${statusdestination} != 'null' ]; then
    echo -e "${RED}Unable to fetch all clusters\nCheck admin password and connectivity${NC}"
    echo -e "${RED}API status ${clustersource} cluster : $(echo ${statussource} | sed -e s/null/OK/g)${RED}"
    echo -e "${RED}API status ${clusterdestination} cluster : $(echo ${statusdestination} | sed -e s/null/OK/g)${RED}"
    exit 1
fi

# Check if cluster exist in API
if [ "$(CURLOVHAPI GET "/1.0/nutanix/${clusterdestination}" | jq .serviceName)" == 'null' ]; then
    echo -e "${RED}Cluster ${clusterdestination} not found in OVHcloud API${NC}"
    exit 1
fi
if [ $(CURLOVHAPI GET "/1.0/nutanix/${clustersource}" | jq .serviceName) == 'null' ]; then
    echo -e "${RED}Cluster ${clustersource} not found in OVHcloud API${NC}"
    exit 1
fi

# Fetching variables from api
CURLOVHAPI GET "/1.0/nutanix/${clusterdestination}" | jq .targetSpec > "$(pwd)/${clusterdestination}.json" || $(echo -e "${RED}Cannot create local file check acl directory${NC}" && exit 1)
CURLOVHAPI GET "/1.0/nutanix/${clustersource}" | jq .targetSpec > "$(pwd)/${clustersource}.json" || $(echo -e "${RED}Cannot create local file check acl directory${NC}" && exit 1)
vrackdestination="$(GetAttr vrack ${clusterdestination}.json)"
vracksource="$(GetAttr vrack ${clustersource}.json)"
iplbdestination="$(GetAttr iplb ${clusterdestination}.json)"
iplbsource="$(GetAttr iplb ${clustersource}.json)"
ipfodestination="$(GetAttr ipfo ${clusterdestination}.json)"
ipfodestinationencoded=$(echo "${ipfodestination}" | sed -e s/'\/'/%2F/g)
ipfosource="$(GetAttr ipfo ${clustersource}.json)"
ipfosourceencoded=$(echo "${ipfosource}" | sed -e s/'\/'/%2F/g)
ipgwsource=$(ipcalc -b ${ipfosource} | grep HostMin | /usr/bin/grep -oE '[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}')
ipgwdestination=$(ipcalc -b ${ipfodestination} | grep HostMin | /usr/bin/grep -oE '[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}')
hostssource="$(GetAttr nodes[].server ${clustersource}.json)"
hostsipsource="$(GetAttr nodes[].ahvIp ${clustersource}.json)"
cvmsipsource="$(GetAttr nodes[].cvmIp ${clustersource}.json)"
hostsdestination="$(GetAttr nodes[].server ${clusterdestination}.json)"
hostsipdestination="$(GetAttr nodes[].ahvIp ${clusterdestination}.json)"
cvmsipdestination="$(GetAttr nodes[].cvmIp ${clusterdestination}.json)"
vlandestination="$(GetAttr infraVlanNumber ${clusterdestination}.json)"
vlansource="$(GetAttr infraVlanNumber ${clustersource}.json)"
gatewayCidrdestination="$(GetAttr gatewayCidr ${clusterdestination}.json)"
gatewayCidrsource="$(GetAttr gatewayCidr ${clustersource}.json)"
pcsource="$(GetAttr prismCentral.vip ${clustersource}.json)"
pcdestination="$(GetAttr prismCentral.vip ${clusterdestination}.json)"

# 0 - check if gateways ip match, vlan macth, node and cvm are different ...TODO
# https://help.ovhcloud.com/csm/fr-nutanix-vrack-interconnection?id=kb_article_view&sysparm_article=KB0045157
# Before connecting the two clusters, ensure that they use different IP addresses (except for the gateway) on the same IP address range.

if [ ${gatewayCidrdestination} != ${gatewayCidrsource} ] || [ ${vlandestination} != ${vlansource} ]; then
    echo -e "${RED}Private gateway ou vlan mismatch between clusters\nGateway ${clustersource} : ${gatewayCidrsource}, Gateway ${clusterdestination} : ${gatewayCidrdestination}\nVlan ${clustersource} : ${vlansource}, Vlan ${clusterdestination} : ${vlandestination}${NC}"
    exit 1
fi

subnet=$(ipcalc -b ${gatewayCidrsource} | grep Network | grep -oE '[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}/[0-9]{2}')

# compare hostip between clusters
for hostipdestination in ${hostsipdestination[@]}; do
    for hostipsource in ${hostsipsource[@]};do
        if [ $hostipsource == $hostipdestination ]; then
            echo "Erreur some hosts ip are the same in both clusters"
            exit 1
        fi
    done
done

# compare host ip destination and cvms ip source
for hostipdestination in ${hostsipdestination[@]}; do
    for cvmipsource in ${cvmsipsource[@]};do                                                                                                                                                                     
        if [ $cvmipsource == $hostipdestination ]; then
            echo "Erreur some hosts ip are in both clusters"
            exit 1
        fi
    done
done

# compare cvms between clusters
for cvmipdestination in ${cvmsipdestination[@]}; do
    for cvmipsource in ${cvmsipsource[@]};do
        if [ $cvmipsource == $cvmipdestination ]; then
            echo "Erreur some cvm ip are in both clusters"
            exit 1
        fi
    done
done

# compare cvm ip destination and host ip source
for cvmipdestination in ${cvmsipdestination[@]}; do
    for hostipsource in ${hostsipsource[@]};do
        if [ $hostipsource == $cvmipdestination ]; then
            echo "Erreur some cvm ip are in both clusters"
            exit 1
        fi
    done
done

# 1- Shutting down the OVHgateway virtual machine.
# https://help.ovhcloud.com/csm/en-ie-nutanix-vrack-interconnection?id=kb_article_view&sysparm_article=KB0045151#shutting-down-the-ovhgateway-virtual-machine

echo -e "${GREEN}Shutting down gateway on cluster${clustersource}${NC}"
#poweroffvm cluster="${clustersource}" user="admin" password="${clustersourcepassword}" vmname="gateway-cluster-1179"
poweroffvm cluster="${clusterdestination}" user="admin" password="${clusterdestinationpassword}" vmname="OVHgateway"


# 2- Configuring vRacks
# This operation involves deleting the vRack assignment in Roubaix and then extending the vRack from Gravelines to Roubaix. You can modify the vRack via the OVHcloud Control Panel.
# https://help.ovhcloud.com/csm/en-ie-nutanix-vrack-interconnection?id=kb_article_view&sysparm_article=KB0045151#configuring-vracks

# Deleting source vRack elements.
echo -e "${GREEN}Deleting items in vRack ${vracksource}from ${clustersource}${NC}"
cleanVrack vrack="${vracksource}" iplb="${iplbsource}" ipfo="${ipfosource}" 


# Adding deleted items from the source vRack into the destination vRack
# https://help.ovhcloud.com/csm/en-ie-nutanix-vrack-interconnection?id=kb_article_view&sysparm_article=KB0045151#adding-deleted-items-from-the-roubaix-vrack-into-the-gravelines-vrack
echo -e "${GREEN}Adding servers in vRack ${vrackdestination}${NC}"
addServersToVrack "${vrackdestination}" "${hostssource[@]}"
echo -e "${GREEN}Adding ipfo : ${ipfosource} in vRack ${vrackdestination}${NC}"
attachIpfoToVrack ipfo="${ipfosource}" vrack="${vrackdestination}"

# Modifying the source Load Balancer
# https://help.ovhcloud.com/csm/en-ie-nutanix-vrack-interconnection?id=kb_article_view&sysparm_article=KB0045151#modifying-the-roubaix-load-balancer
echo -e "${GREEN}Modifying the source Load Balancer${NC}"
cleanIplbPrivateNetwork iplb="${iplbsource}"
attachIplbToVrack vrack="${vrackdestination}" iplb="${iplbsource}"
getIplbPrivateNetworkNatip iplb="${iplbdestination}"
setupIplbPrivateNetwork iplb="${iplbsource}" vlan=${vlansource} subnet=${subnet} natip="${natip}"

echo -e "${GREEN}Setup Done\n${NC}"
echo -e "${RED}Don't forget to change one of Data Service Ip in prism element\n${NC}"
echo -e "${GREEN}In some case, You'll need to restart both Prismcentral, check with LCM, if it's doesn't work => restart${NC}"
exit

# Leap 
dataserviceipsource=$(CURLNTNXAPI cluster="${clustersource}" user="admin" password="${clustersourcepassword}" method="POST" request="/api/nutanix/v3/clusters/list" body="{}" | jq -r '.entities[].status.resources.network.external_data_services_ip' | head -1)
dataserviceipdestination=$(CURLNTNXAPI cluster="${clusterdestination}" user="admin" password="${clusterdestinationpassword}" method="POST" request="/api/nutanix/v3/clusters/list" body="{}" | jq -r '.entities[].status.resources.network.external_data_services_ip' | head -1)

connectAZ cluster="${clusterdestination}" user="admin" password="${clusterdestinationpassword}" distantpcip="${pcsource}" distantpcpassword="${clustersourcepassword}"
exit

