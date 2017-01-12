# export AWS_DEFAULT_PROFILE=vaftl
SECONDS=0

## Global Settings
BUCKET_NAME="nxt-vms"
VPC_NAME="NXT"
SUBNET_NAME="NXT"
SECURITYGROUP_NAME="NXT"
SECURITYGROUP_DESCRIPTION="NXT"
KEYPAIR_NAME="PB1"
ROLE_NAME="nxt-deploy"
POLICY_NAME="nxt-deploy"

## VM Settings
## All arrays must have the same number of elements !!!
## OVA image names
VM_FILE=(
	"NXT_DB.ova"
	"NXT_APP.ova"
)
## VM image names
VM_NAME=(
	"NXT.DB"
	"NXT.APP"
)
VM_IP=(
	"10.1.2.233"
	"10.1.2.236"
)
VM_INSTANCE_TYPE=(
	"m3.xlarge"
	"m3.medium"
)

if [ "${#VM_FILE[@]}" = 0 ] || [ "${#VM_FILE[@]}" != "${#VM_NAME[@]}" ] || [ "${#VM_FILE[@]}" != "${#VM_IP[@]}" ] || [ "${#VM_FILE[@]}" != "${#VM_INSTANCE_TYPE[@]}" ]; then
	echo "ERROR: Script configuration error - VM_* arrays not configured corectly"
	exit
fi

## Create bucket
BUCKET=$( aws s3api list-buckets --query 'Buckets[].Name' | grep '"'${BUCKET_NAME}'"' | sed -e 's/\s*\"//' -e 's/\s*\"$//' | sed -e 's/\",//' -e 's/\",$//' )
if [ "${BUCKET}" == "" ] || [ ${BUCKET} != ${BUCKET_NAME} ]; then
	aws s3 mb s3://${BUCKET_NAME}
else
	echo "Bucket ${BUCKET_NAME} already exists"
fi

## Remove old vm images from S3
# echo ${VM_FILE[$key]} - ${VM_NAME[$key]}
# for name in "${!VM_FILE[@]}"; do
# 	aws s3 rm s3://${BUCKET_NAME}/${VM_FILE[$name]}
# done

## Upload vm images to S3
# for name in "${!VM_FILE[@]}"; do
# 	aws s3 cp "${VM_FILE[$name]}" s3://${BUCKET_NAME}
# done
## TODO: wait until upload is done

## Create $ROLE_NAME role
## TODO: verify if role already exists and get ID
# aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document file://trust-policy.json
## Create role policy
## TODO: verify if policy already exists and get ID
# aws iam put-role-policy --role-name $ROLE_NAME --policy-name $POLICY_NAME --policy-document file://role-policy.json

## Delete old images from EC2
for name in "${!VM_NAME[@]}"; do
	IMAGEID=$( aws ec2 describe-images --filters "Name=tag-key,Values=Name,Name=tag-value,Values=${VM_NAME[$name]}" | jq '.Images[0].ImageId' | sed -e 's/^"//' -e 's/"$//' )

	if [ "${IMAGEID}" != "" ]; then
		echo "Deregistering image-id ${IMAGEID}"
		aws ec2 deregister-image --image-id "${IMAGEID}"
	fi
done

echo ""

## Import images from S3 to EC2 AMIs
declare -A IMPORTIDS
i=0
for name in "${!VM_FILE[@]}"; do
	fname=${VM_FILE[$name]}

	IMPORTIDS["${fname}"]=$( aws ec2 import-image --cli-input-json '{"DiskContainers": [{"Description": "NXT AWS Deploy Task #'${i}'", "UserBucket": {"S3Bucket": "nxt-vms", "S3Key": "'${fname}'" }}]}' | jq '.ImportTaskId' | sed -e 's/^"//' -e 's/"$//' )
	((i++))
	echo "IMPORTID for ${VM_NAME[$name]} ($fname): ${IMPORTIDS[$fname]}"

	IMPORT_TASK_IDS=${IMPORT_TASK_IDS}" "${IMPORTIDS[${fname}]}
done

unset i

## Wait until import is done
echo "IMPORT_TASK_IDS: ${IMPORT_TASK_IDS}"
echo "===================================="
echo "Waiting import-image-tasks to finish"
sc=0
start=$SECONDS
while [ $(aws ec2 describe-import-image-tasks --import-task-ids ${IMPORT_TASK_IDS} | jq 'contains({"ImportImageTasks": [{"Status": "active"}]})') == true ]; do
	if [[ $sc != 0 ]] && ! (( $sc % 36 )); then echo ""; fi
	echo -n "."
	sleep 10;
	((sc++))
	sleep 10;
done
echo ""
duration=$(($SECONDS - $start))
echo "Import-image-tasks finished after $(($duration / 60)) minutes and $(($duration % 60)) seconds"
echo "===================================="

unset sc

## Add tags to AMIs
for name in "${!VM_FILE[@]}"; do
	fname=${VM_FILE[$name]}

	IMPORT_ID=$(aws ec2 describe-images --filters "Name=name,Values=${IMPORTIDS[${fname}]}" | jq '.Images[0].ImageId' | sed -e 's/^"//' -e 's/"$//' )
	aws ec2 create-tags --resources $IMPORT_ID --tags Key="Name",Value="${VM_NAME[$name]}"

	echo "Creating tag for AMI (${IMPORTIDS[${fname}]})"
done

## Create VPC
VPCID=$( aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${VPC_NAME}" | jq '.Vpcs[0].VpcId' | sed -e 's/^\"//' -e 's/\"$//' )
if [ "${VPCID}" == "" ]; then
	VPCID=$( aws ec2 create-vpc --cidr-block 10.1.0.0/16 | jq '.Vpc.VpcId' | sed -e 's/^\"//' -e 's/\"$//' )
	echo "Creating VPC ({$VPC_NAME})"
fi
echo VPCID=${VPCID}
aws ec2 create-tags --resources ${VPCID} --tags Key="Name",Value="${VPC_NAME}" | sed -e 's/^\"//' -e 's/\"$//'

## Create subnet
SUBNETID=$( aws ec2 describe-subnets --filters "Name=tag:Name,Values=${SUBNET_NAME}" | jq '.Subnets[0].SubnetId' | sed -e 's/^\"//' -e 's/\"$//' )
if [ "${SUBNETID}" == "" ]; then
	SUBNETID=$( aws ec2 create-subnet --vpc-id ${VPCID} --cidr-block 10.1.0.0/16 | jq '.Subnet.SubnetId' | sed -e 's/^\"//' -e 's/\"$//' )
	echo "Creating Subnet (${SUBNET_NAME})"
fi
echo SUBNETID=${SUBNETID}
aws ec2 create-tags --resources ${SUBNETID} --tags Key="Name",Value="${SUBNET_NAME}"
aws ec2 modify-subnet-attribute --subnet-id ${SUBNETID} --map-public-ip-on-launch

## Create internet gateway
GATEWAYID=$( aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=${VPCID},Name=tag:Name,Values=${VPC_NAME}" | jq '.InternetGateways[] | .InternetGatewayId' | sed -e 's/^\"//' -e 's/\"$//' )
if [ "${GATEWAYID}" == "" ]; then
	GATEWAYID=$( aws ec2 create-internet-gateway | jq '.InternetGateway.InternetGatewayId' | sed -e 's/^\"//' -e 's/\"$//' )
	echo "Creating internet gateway"
fi
echo GATEWAYID=${GATEWAYID}
aws ec2 create-tags --resources ${GATEWAYID} --tags Key="Name",Value="${SUBNET_NAME}"
## Attach internet gateway
if [ $(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=${VPCID},Name=internet-gateway-id,Values=${GATEWAYID}" | jq '.InternetGateways | contains([{"Attachments": [{"State": "available"}]}])') != true ]; then
	aws ec2 attach-internet-gateway --internet-gateway-id ${GATEWAYID} --vpc-id ${VPCID}
fi

## Create route to internet gateway
ROUTETABLEID=$( aws ec2 describe-route-tables --filters "Name=vpc-id,Values=${VPCID}" | jq '.RouteTables[0].RouteTableId' | sed -e 's/^\"//' -e 's/\"$//' )
echo ROUTETABLEID=${ROUTETABLEID}
aws ec2 create-route --route-table-id ${ROUTETABLEID} --destination-cidr-block "0.0.0.0/0" --gateway-id ${GATEWAYID} > /dev/null

## Create security group
GROUPID=$( aws ec2 describe-security-groups --filters "Name=group-name,Values=${SECURITYGROUP_NAME},Name=vpc-id,Values=${VPCID},Name=description,Values=${SECURITYGROUP_DESCRIPTION}" | jq '.SecurityGroups[0].GroupId' | sed -e 's/^\"//' -e 's/\"$//' )
if [ "${GROUPID}" == "" ]; then
	GROUPID=$( aws ec2 create-security-group --group-name "${SECURITYGROUP_NAME}" --description "${SECURITYGROUP_DESCRIPTION}" --vpc-id ${VPCID} | jq '.GroupId' | sed -e 's/^\"//' -e 's/\"$//' )
fi
echo GROUPID=$GROUPID

## Create inbound rules
echo "Create inbound rules"
aws ec2 authorize-security-group-ingress --group-id ${GROUPID} --ip-permissions '[{"FromPort": 0, "ToPort": 65535, "IpRanges": [{"CidrIp": "10.1.0.0/16"}], "IpProtocol": "tcp"},{"FromPort": 22, "ToPort": 22, "IpRanges": [{"CidrIp": "0.0.0.0/0"}], "IpProtocol": "tcp"},{"FromPort": 80, "ToPort": 80, "IpRanges": [{"CidrIp": "0.0.0.0/0"}], "IpProtocol": "tcp"},{"FromPort": 443, "ToPort": 443, "IpRanges": [{"CidrIp": "0.0.0.0/0"}], "IpProtocol": "tcp"}]'

## Create outbound rules
# echo "Create outbound rules"
# aws ec2 authorize-security-group-egress --group-id ${GROUPID} --ip-permissions '[{"IpProtocol": "-1", "IpRanges": [{"CidrIp": "10.1.0.0/16"}]}]'
# aws ec2 revoke-security-group-egress --group-id ${GROUPID} --ip-permissions '[{"IpProtocol": "-1", "IpRanges": [{"CidrIp": "0.0.0.0/0"}]}]'

## Create key pair
# echo "Create key pair (${KEYPAIR_NAME})"
# KEYPAIR=$( aws ec2 describe-key-pairs --filter "Name=key-name,Values=${KEYPAIR_NAME}" | jq '.KeyPairs[0].KeyName' | sed -e 's/^\"//' -e 's/\"$//' )
# if [ "${KEYPAIR}" == "" ]; then
# 	aws ec2 create-key-pair --key-name "${KEYPAIR_NAME}"
# fi

## Create instances
declare -A INSTANCES
for name in "${!VM_FILE[@]}"; do
	fname=${VM_FILE[$name]}

	echo "Creating instance ${VM_NAME[$name]} of type ${VM_INSTANCE_TYPE[$name]} with private IP ${VM_IP[$name]}"

	IMAGEID=$(aws ec2 describe-images --filters "Name=name,Values=${IMPORTIDS[${fname}]}" | jq '.Images[0].ImageId' | sed -e 's/^"//' -e 's/"$//' )
	INSTANCEID=$( aws ec2 run-instances --image-id ${IMAGEID} --key-name "${KEYPAIR_NAME}" --security-group-ids ${GROUPID} --instance-type ${VM_INSTANCE_TYPE[$name]} --subnet-id ${SUBNETID} --private-ip-address ${VM_IP[$name]} --associate-public-ip-address | jq '.Instances[0].InstanceId' | sed -e 's/^\"//' -e 's/\"$//' )

	echo INSTANCEID=${INSTANCEID}

	aws ec2 create-tags --resources ${INSTANCEID} --tags Key="Name",Value="${VM_NAME[$name]}"

	INSTANCES[${name}]=$INSTANCEID
done

## Get Public IPs
sleep 30
echo ""
for name in "${!VM_FILE[@]}"; do
	PUBIP=$( aws ec2 describe-instances --instance-ids ${INSTANCES[$name]} --query "Reservations[0].Instances[0].PublicIpAddress" --output=text )
	echo "Instance ${VM_FILE[$name]} got Public IP ${PUBIP}"
done

echo ""
echo "Script finished. Total execution time: $(($SECONDS / 60)) minutes and $(($SECONDS % 60)) seconds"
echo ""