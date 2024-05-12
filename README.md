# OVHcloud Nutanix Scripts
Some tools in order to manage nutanix cluster on OVHcloud via API.

# Disclaimer
This bash tools are personal.

Use it in lab, fork, customize and enjoy.

# Used configuration 
Script are used on MacOS and Ubuntu.

IMPORTANT : you need to install JQ https://jqlang.github.io/jq/ (1.6 on my Ubuntu laptop as I'm writing this file)

# OVHcloud API Scripts

## Generate Token for OVHcloud API
You need to generate a token in order to be able to use ovhcloud API for script who uses this API.

https://eu.api.ovh.com/createToken/ for EU

Documentation avalaible here : https://help.ovhcloud.com/csm/fr-api-getting-started-ovhcloud-api?id=kb_article_view&sysparm_article=KB0042789#utilisation-avancee-coupler-les-api-ovhcloud-avec-une-application

https://ca.api.ovh.com/createToken/ for CA

Documentation avalaible here : https://help.ovhcloud.com/csm/en-ca-api-getting-started-ovhcloud-api?id=kb_article_view&sysparm_article=KB0029722#advanced-usage-pair-ovhcloud-apis-with-an-application

https://us.ovhcloud.com/auth/api/createToken for US

Once generated use secret.cfg.template[REGION] to save your acces token and save file to secret.cfg.

## Test your Token
Use checkapi script.
```bash
./checkapi.sh
```
## Shutdown a server
This script will be used for scale down a cluster, you need first to shutdown the server to remove.
Use shutdownserver script.
```bash
./shutdownserver.sh <server name>
```
## Boot server on Hard Drive
Use bootserveronhdd script.
WARNING : server will reboot

```bash
./bootserveronhdd.sh <server name>
```
## Get cluster details
Use getnutanixclusterdetails script to view details about a cluster

```bash
./getnutanixclusterdetails.sh <cluster name>
```
You can also "pipe" with jq to fetch specific parameter

Cluster parameters 

```bash
./getnutanixclusterdetails.sh <cluster name> | jq .targetSpec
```

## Order new node

Order a new server for your cluster.
Server will be the same as the first in the cluster, same reference.
You could set ram parameter in the script to change quantity of ram.
Don't change "quantity parameter" => there is some dev in progress on OVHcloud side.

For now you can only order in FR, US, CA.

```bash
./orderscaleupserver.sh <cluster name>
```


## Scale up 

Work in progress
For now you can only scale up one node. If you have more than one node and you want to use this script, you must wait that the first node have been deployed before sacle up again.

Multi scale up is allowed on OVHcloud side but not implemented.

## Interconnect clusters

This script interconnect two Nutanix clusters Provided by OVHcloud across the same vRack.
Vrack are cross datacenters, please check documentation and availability https://www.ovhcloud.com/en-ie/network/vrack/

```bash
./interconnectvrackclusters.sh clusterdestination='cluster-xxxx.nutanix.ovh.xx' clusterdestinationpassword='12345' clustersource='cluster-xxxx.nutanix.ovh.xx' clustersourcepassword='P@55w0rd'
```


