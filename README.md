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

https://api.us.ovhcloud.com/createToken/ for US

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
Use getnutanixclusterdetails script

```bash
./getnutanixclusterdetails.sh <cluster name>
```
You can also "pipe" with jq to fetch specific parameter

Cluster parameters 

```bash
./getnutanixclusterdetails.sh <cluster name> | jq .targetSpec
```
