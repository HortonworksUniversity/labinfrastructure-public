#!/bin/bash  
#set -x 
############################################################################
# This script, unlike most others is using aws cli in addition to ec2 cli
## This Jenkins job uses ec2 + aws cli commands. 
## For ec2, the job build needs to include keys: AWS_ACCESS_KEY & AWS_SECRET_KEY
## For aws, the job build needs to include keys: AWS_ACCESS_KEY_ID & AWS_SECRET_ACCESS_KEY
## The above keys are provided via jenkins gui job config 
############################################################################

export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_KEY

export EC2_HOME=/var/lib/jenkins/workspace/ec2-api-tools/
export JAVA_HOME=/usr/
PATH=$PATH:$EC2_HOME/bin
export AWS_CLI_HOME=/usr/local/aws
PATH=$PATH:$AWS_CLI_HOME/bin

# 20171003 added 2 extra AMIs: 
# AMI2: Optional MIT-KDC for xrealm auth
# AMI3: Optional WinAD for xrealm auth 

echo $LOCATION

if [[ "$LOCATION" == "US West" ]]; then
	export AWS_DEFAULT_REGION=us-west-2
        export EC2_URL=https://ec2.us-west-2.amazonaws.com
	      export AMI=ami-0e3fde6e
        export AMI2=ami-b35346ca
        export AMI3=ami-f8574281


elif [[ "$LOCATION" == "Ireland" ]]; then
	export AWS_DEFAULT_REGION=eu-west-1
	export EC2_URL=https://ec2.eu-west-1.amazonaws.com
	export AMI=ami-ab3cbdd8
  export AMI2=ami-2bc12d52
  export AMI3=ami-2ec12d57

elif [[ "$LOCATION" == "Frankfurt" ]]; then
        export EC2_URL=https://ec2.eu-central-1.amazonaws.com
        export AMI=ami-fa549295
        export AMI2=ami-ca46f4a5
        export AMI3=ami-b04af8df
        export AWS_DEFAULT_REGION=eu-central-1

elif [[ "$LOCATION" == "Singapore" ]]; then
	export AWS_DEFAULT_REGION=ap-southeast-1
	export EC2_URL=https://ec2.ap-southeast-1.amazonaws.com
	export AMI=ami-30fa2c53
  export AMI2=ami-d78bf7b4
  export AMI3=ami-438af620

elif [[ "$LOCATION" == "Seoul" ]]; then
        export EC2_URL=https://ec2.ap-northeast-2.amazonaws.com
        export AMI=ami-0270a66c
        export AMI2=ami-7f09d311
        export AMI3=ami-7e09d310
        export AWS_DEFAULT_REGION=ap-northeast-2

elif [[ "$LOCATION" == "Sydney" ]]; then
        export AWS_DEFAULT_REGION=ap-southeast-2
        export EC2_URL=https://ec2.ap-southeast-2.amazonaws.com
        export AMI=ami-80d3c8e3
        export AMI2=ami-dba447b9
        export AMI3=ami-b7aa49d5

elif [[ "$LOCATION" == "Mumbai" ]]; then
        export EC2_URL=https://ec2.ap-south-1.amazonaws.com
        export AMI=ami-e6f2b189
        export AMI2=ami-9cf3b0f3
        export AMI3=ami-e7f2b188
        export SUBNET=subnet-3153b558
        export AWS_DEFAULT_REGION=ap-south-1

else
        export AWS_DEFAULT_REGION=us-west-2
        export EC2_URL=https://ec2.us-west-2.amazonaws.com
        export AMI=ami-0e3fde6e
        export AMI2=mi-b35346ca
        export AMI3=ami-f8574281
        export SUBNET=subnet-02edac67
fi

export lab_prefix=$CLUSTER_TAG"-"
export lab_first=$FIRST_CLUSTER_LABEL
export lab_count=$NO_OF_VMs
export lab_batch=$NO_OF_ADDTL_NODES

if [[ $SEC_GROUP ]]; then
  
  SEC_GROUP_VERIFY=`aws ec2 describe-security-groups --region $AWS_DEFAULT_REGION --group-ids $SEC_GROUP | jq -r '.SecurityGroups[] | .GroupId'`
  
  if [[ "$SEC_GROUP" == "$SEC_GROUP_VERIFY" ]]; then
    echo "$SEC_GROUP is security group"
  else
    echo "Problem finding security group in region $AWS_DEFAULT_REGION"
  exit 1
  fi
fi

if [[ $SUBNET ]]; then
  echo "$SUBNET is SUBNET group"
else
  echo "Problem finding SUBNET group"
  exit 1
fi

echo adding $SEC_GROUP to $SEC_GROUP to allow intra-cluster traffic
aws ec2 authorize-security-group-ingress --region $AWS_DEFAULT_REGION --group-id $SEC_GROUP --protocol all --port -1 --source-group $SEC_GROUP



### {"ParameterKey":"AmbariVersion","ParameterValue":"2.5.0.3"},
export cfn_parameters='
[
{"ParameterKey":"KeyName","ParameterValue":"training-keypair"},
{"ParameterKey":"AmbariServices","ParameterValue":"HDFS MAPREDUCE2 PIG YARN HIVE HBASE TEZ AMBARI_INFRA SLIDER ZOOKEEPER"},
{"ParameterKey":"HDPStack","ParameterValue":"2.6"},
{"ParameterKey":"AmbariVersion","ParameterValue":"2.5.2.0"},
{"ParameterKey":"AdditionalInstanceCount","ParameterValue":"'$NO_OF_ADDTL_NODES'"},
{"ParameterKey":"SubnetId","ParameterValue":"'$SUBNET'"},
{"ParameterKey":"SecurityGroups","ParameterValue":"'$SEC_GROUP'"},
{"ParameterKey":"InstanceType","ParameterValue":"'$INSTANCE_TYPE'"},
{"ParameterKey":"DeployCluster","ParameterValue":"'$DEPLOY_CLUSTER'"}
]
'

echo $cfn_parameters
## next line to disable ROLLBACK (auto-delete on error) 
export cfn_switches="--disable-rollback"

##########################
# Function to start the EC2 instances
###########################
function startEC2 {
  echo ""
  echo "###############################################################################################"
  echo "Starting $NO_OF_VMs clusters for training: $CLUSTER_TAG"
  echo "###############################################################################################"
  echo ""

  int_hostname=(1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 )
  ext_hostname=(1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 )

###Creating new instances
  echo "1. Creating new clusters in $LOCATION.."
  echo ""

#create cloudformation template instances 
echo_file=`./clusters-create.sh`
#echo $echo_file

# create win AD Server instance

if [[ "$ADD_AD_SERVER" == "true" ]] ; then
   echo "CREATING AD INSTANCE"
   my_instance_ad=`ec2run $AMI -s $SUBNET -k training-keypair -g $SEC_GROUP --instance-type m3.xlarge -n 1 | grep INSTANCE | cut -f2`
   AD_SERVER_NAME=$CLUSTER_TAG"-WIN-AD-SERVER"
   ec2addtag $my_instance_ad --url $EC2_URL --tag 'Name'="${AD_SERVER_NAME}"
fi

if [[ "$ADD_XR_SERVER" == "true" ]] ; then
   echo "CREATING CROSS-REALM AUTH MIT-KDC INSTANCE"
   my_instance_mit=`ec2run $AMI2 -s $SUBNET -k training-keypair -g $SEC_GROUP --instance-type m3.xlarge -n 1 | grep INSTANCE | cut -f2`
   AD_SERVER_NAME=$CLUSTER_TAG"-MIT-KDC-XREALM"
   ec2addtag $my_instance_mit --url $EC2_URL --tag 'Name'="${AD_SERVER_NAME}"
fi

if [[ "$ADD_XR_SERVER" == "true" ]] ; then
   echo "CREATING CROSS-REALM AUTH AD INSTANCE"
   my_instance_adx=`ec2run $AMI3 -s $SUBNET -k training-keypair -g $SEC_GROUP --instance-type m3.xlarge -n 1 | grep INSTANCE | cut -f2`
   AD_SERVER_NAME=$CLUSTER_TAG"-AD-XREALM"
   ec2addtag $my_instance_adx --url $EC2_URL --tag 'Name'="${AD_SERVER_NAME}"
fi


}


############################################################
# Function to collect cluster(s) details 
############################################################
function collectClusterInfo {

my_instances=""

for (( i=1; i<=1; ++i )); do
  LONG_CLUSTER_TAG=$CLUSTER_TAG"-"$i
  FLAG=""
    while [ "$FLAG" != "CREATE_COMPLETE" ]; do
      sleep 15s	
      FLAG=`aws cloudformation list-stack-resources --stack-name $LONG_CLUSTER_TAG --output text | grep AdditionalNodes | cut -f5`
    done

  ### get instance ids
  sleep 10s
  my_instances+=`aws cloudformation describe-stack-resource --stack-name $LONG_CLUSTER_TAG --logical-resource-id AmbariNode --output json | grep PhysicalResourceId | awk -F':' '{print $2}' | sed 's|[ "]||g'`
  my_instances+=`aws autoscaling describe-auto-scaling-groups --no-paginate --output text | grep $LONG_CLUSTER_TAG | grep INSTANCES | cut -f4`
  my_instances=`echo "$my_instances" | tr '\n' ','`

done
my_instances=`echo "$my_instances" | sed 's/,$//'`

echo -e "\n2. List of newly created Instances:"
echo "$my_instances" | sed 's/,/\n/g'
echo ""

##Identifying Internal Hostname for the each instance
  echo "3. Identifying Internal Hostname for the each instance..."
  echo ""

  count1=0
  for cur_ins in $my_instances
  do
    int_hostname[$count1]=`ec2din -region $AWS_DEFAULT_REGION -F "instance-id=$cur_ins" | grep INSTANCE | cut -f5`
    ((count1 = $count1 +1 ))
  done

  echo -e "List of internal Hostname :\n"
  echo -e "${int_hostname[@]:0:$NO_OF_VMs}" | sed 's/ /\n/g'       
  echo ""
  echo ""

### Sorting Internal Hostname in alphabatical order
sorted_int_hostname=`echo ${int_hostname[@]:0:$NO_OF_VMs} | sed 's/ /\n/g'`
sorted_int_hostname=`echo $sorted_int_hostname | sed 's/.$//'` 

 

OIFS=$IFS
IFS=",";
my_instances2=($my_instances)
IFS=$OIFS;

   for ((i=0; i<${#my_instances2[@]}; ++i)); do
   temp_ext_hostname=`ec2din -region $AWS_DEFAULT_REGION -F "instance-id=${my_instances2[$i]}" | grep INSTANCE | cut -f17`;
   sorted_ext_hostname+=$(echo "$temp_ext_hostname :")
   sleep 3s
   done 	

   echo -e "5. List of EC2 IP Addresses:\n" 
   echo $sorted_ext_hostname | sed 's/:/\n/g'
   echo ""
   echo ""


for ((i=0; i<${#my_instances2[@]}; ++i)); do
   temp_stack_name=`ec2din -region $AWS_DEFAULT_REGION -F "instance-id=${my_instances2[$i]}" | grep aws:cloudformation:stack-name | cut -f5`;
   temp_logical_id=`ec2din -region $AWS_DEFAULT_REGION -F "instance-id=${my_instances2[$i]}" | grep aws:cloudformation:logical-id | cut -f5`;


   if [[ "$temp_logical_id" == "AmbariNode" ]] ; then
      temp_logical_id="${temp_logical_id}-----";
   fi

#20171005 Changing from IPs to DNS as per Kiser's request 
   temp_public_ip=`ec2din -region $AWS_DEFAULT_REGION -F "instance-id=${my_instances2[$i]}" | grep INSTANCE | cut -f4`;
   temp_private_ip=`ec2din -region $AWS_DEFAULT_REGION -F "instance-id=${my_instances2[$i]}" | grep INSTANCE | cut -f5`;   
   final_hosts+=$(echo "${my_instances2[$i]} : $temp_stack_name : $temp_logical_id : $temp_public_ip / $temp_private_ip | ");
done

echo -e "6. Final List of Host for email:\n"
final_hosts=`echo $final_hosts | sed 's/ | /\n/g' | cut -d':' -f2-4 | sed 's/|//' | sort -k 1`

if [[ "$ADD_AD_SERVER" == "true" ]] ; then
    temp_AD_ip=`ec2din -region $AWS_DEFAULT_REGION -F "instance-id=${my_instance_ad}" | grep INSTANCE | cut -f4`;
    temp_private_AD_ip=`ec2din -region $AWS_DEFAULT_REGION -F "instance-id=${my_instance_ad}" | grep INSTANCE | cut -f5`;
    final_hosts+=$(echo -e "\n ${CLUSTER_TAG}     : WIN AD SERVER   : ${temp_AD_ip} / ${temp_private_AD_ip} ");
fi

if [[ "$ADD_XR_SERVER" == "true" ]] ; then
    temp_MIT_ip=`ec2din -region $AWS_DEFAULT_REGION -F "instance-id=${my_instance_mit}" | grep INSTANCE | cut -f4`;
    temp_private_MIT_ip=`ec2din -region $AWS_DEFAULT_REGION -F "instance-id=${my_instance_mit}" | grep INSTANCE | cut -f5`;
    final_hosts+=$(echo -e "\n ${CLUSTER_TAG}     : MIT-KDC-XREALM  : ${temp_MIT_ip} / ${temp_private_MIT_ip} ");
    temp_ADX_ip=`ec2din -region $AWS_DEFAULT_REGION -F "instance-id=${my_instance_adx}" | grep INSTANCE | cut -f4`;
    temp_private_ADX_ip=`ec2din -region $AWS_DEFAULT_REGION -F "instance-id=${my_instance_adx}" | grep INSTANCE | cut -f5`;
    final_hosts+=$(echo -e "\n ${CLUSTER_TAG}     : AD-XREALM       : ${temp_ADX_ip} / ${temp_private_ADX_ip} ");
fi

echo "$final_hosts"

}


###########################
# Begin execution
###########################
startEC2
collectClusterInfo


