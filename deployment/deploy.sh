#!/bin/bash

# Copyright (c) 2018, WSO2 Inc. (http://wso2.com) All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e
set -o xtrace

#Download the common scripts to working directory

echo "Running deploy.sh..."
pwd

get_cmn_scripts_dwld(){
git clone https://github.com/wso2-incubator/test-integration-tests-runner.git
cp test-integration-tests-runner/intg_test_manager.py test-integration-tests-runner/intg_test_constant.py deployment/resources/
echo "=== Copied common scripts. ==="
}

get_cmn_scripts_dwld

DIR=$2
DIR1=integration
FILE1=${DIR}/infrastructure.properties
FILE2=${DIR}/testplan-props.properties
FILE3=deployment/resources/run-intg-test.py
FILE4=deployment/resources/intg_test_manager.py
FILE5=deployment/resources/intg_test_constant.py
FILE6=deployment/resources/requirements.txt
FILE7=deployment/resources/intg-test-runner.sh
FILE8=deployment/resources/intg-test-runner.bat
FILE12=deployment/resources/prod_test_constant.py

PROP_KEY=keyFileLocation      	 #pem file
PROP_OS=OS                       #OS name e.g. centos
PROP_HOST=WSO2PublicIP           #host IP
PROP_INSTANCE_ID=WSO2InstanceId  #Physical ID (Resource ID) of WSO2 EC2 Instance
PROP_PRODUCT_NAME=ProductName
PROP_PRODUCT_VERSION=ProductVersion
PROP_MGT_CONSOLE_URL=WSO2MgtConsoleURL

#----------------------------------------------------------------------
# getting data from databuckets
#----------------------------------------------------------------------
key_pem=`grep -w "$PROP_KEY" ${FILE1} ${FILE2} | cut -d'=' -f2`
os=`cat ${FILE2} | grep -w "$PROP_OS" ${FILE1} | cut -d'=' -f2`
#user=`cat ${FILE2} | grep -w "$PROP_USER" ${FILE1} ${FILE2} | cut -d'=' -f2`
instance_id=`cat ${FILE2} | grep -w "$PROP_INSTANCE_ID" ${FILE1} ${FILE2} | cut -d'=' -f2`
user=''
password=''
host=`grep -w "$PROP_HOST" ${FILE1} ${FILE2} | cut -d'=' -f2`
CONNECT_RETRY_COUNT=20

#=== FUNCTION ==================================================================
# NAME: request_ec2_password
# DESCRIPTION: Request password of Windows instance from AWS using the key file.
# PARAMETER 1: Physical-ID of the EC2 instance
#===============================================================================

request_ec2_password() {
  instance_id=$1
  echo "Retrieving password for Windows instance from AWS for instance id ${instance_id}"
  x=1;
  retry_count=$CONNECT_RETRY_COUNT;

  while [ "$password" == "" ] ; do
    #Request password from AWS
    responseJson=$(aws ec2 get-password-data --instance-id "${instance_id}" --priv-launch-key ${key_pem})

    #Validate JSON
    if [ $(echo $responseJson | python -c "import sys,json;json.loads(sys.stdin.read());print 'Valid'") == "Valid" ]; then
      password=$(python3 -c "import sys, json;print(($responseJson)['PasswordData'])")
      echo "Password received!"
    else
      echo "Invalid JSON response: $responseJson"
    fi

    if [ "$x" = "$retry_count" ]; then
      echo "Password never received for instance with id ${instance_id}. Hence skipping test execution!"
      exit
    fi

    sleep 10 # wait for 10 second before check again
    x=$((x+1))
  done
}

#=== FUNCTION ==================================================================
# NAME: wait_for_port
# DESCRIPTION: Check if the port is opened till the time-out occurs
# PARAMETER 1: Host name
# PARAMETER 2: Port number
#===============================================================================
wait_for_port() {
  host=$1
  port=$2
  x=1;
  retry_count=$CONNECT_RETRY_COUNT;
  echo "Wait port: ${1}:${2}"
  while ! nc -z $host $port; do
    sleep 2 # wait for 2 second before check again
    echo -n "."
    if [ $x = $retry_count ]; then
      echo "port never opened."
      exit 1
    fi
  x=$((x+1))
  done
}

#----------------------------------------------------------------------
# select default username and remote directory based on the OS
#----------------------------------------------------------------------
case "${os}" in
   "CentOS")
    	user=centos
        PROP_REMOTE_DIR=REMOTE_WORKSPACE_DIR_UNIX ;;
   "RHEL")
    	user=ec2-user
        PROP_REMOTE_DIR=REMOTE_WORKSPACE_DIR_UNIX ;;
   "Windows")
    	user=Administrator
        PROP_REMOTE_DIR=REMOTE_WORKSPACE_DIR_WINDOWS ;;
   "UBUNTU")
        user=ubuntu
        PROP_REMOTE_DIR=REMOTE_WORKSPACE_DIR_UNIX ;;
esac

REM_DIR=`grep -w "$PROP_REMOTE_DIR" ${FILE1} ${FILE2} | cut -d'=' -f2`

#----------------------------------------------------------------------
# wait till port 22 is opened for SSH
#----------------------------------------------------------------------
wait_for_port ${host} 22

get_product_home() {
    PRODUCT_NAME=`grep -w "$PROP_PRODUCT_NAME" ${FILE1} | cut -d'=' -f2`
    PRODUCT_VERSION=`grep -w "$PROP_PRODUCT_VERSION" ${FILE1} | cut -d'=' -f2`

    echo $REM_DIR/storage/$PRODUCT_NAME-$PRODUCT_VERSION
}
wait_for_server_startup() {
    max_attempts=100
    attempt_counter=0

    MGT_CONSOLE_URL="https://$host:9443/carbon"
    until $(curl -k --output /dev/null --silent --head --fail $MGT_CONSOLE_URL); do
       if [ ${attempt_counter} -eq ${max_attempts} ];then
        echo "Max attempts reached"
        exit 1
       fi
        printf '.'
        attempt_counter=$(($attempt_counter+1))
        sleep 5
    done
}

PRODUCT_HOME=$(get_product_home)
#----------------------------------------------------------------------
# execute commands based on the OS of the instance
# Steps followed;
# 1. SSH and make the directory.
# 2. Copy necessary files to the instance.
# 3. Execute scripts at the instance.
# 4. Retrieve reports from the instance.
#----------------------------------------------------------------------
if [ "${os}" = "Windows" ]; then
  echo "Waiting 4 minutes till Windows instance is configured. "
  sleep 4m #wait 4 minutes till Windows instance is configured and able to receive password using key file.
  set +o xtrace #avoid printing sensitive data in the next commands
  request_ec2_password $instance_id
  REM_DIR=$(echo "$REM_DIR" | sed 's/\\//g')
  echo "Copying files to ${REM_DIR}.."
  sshpass -p "${password}" scp -q -o StrictHostKeyChecking=no ${FILE1} ${user}@${host}:${REM_DIR}
  sshpass -p "${password}" scp -q -o StrictHostKeyChecking=no ${FILE2} ${user}@${host}:${REM_DIR}
  sshpass -p "${password}" scp -q -o StrictHostKeyChecking=no ${FILE3} ${user}@${host}:${REM_DIR}
  sshpass -p "${password}" scp -q -o StrictHostKeyChecking=no ${FILE4} ${user}@${host}:${REM_DIR}
  sshpass -p "${password}" scp -q -o StrictHostKeyChecking=no ${FILE5} ${user}@${host}:${REM_DIR}
  sshpass -p "${password}" scp -q -o StrictHostKeyChecking=no ${FILE6} ${user}@${host}:${REM_DIR}
  sshpass -p "${password}" scp -q -o StrictHostKeyChecking=no ${FILE8} ${user}@${host}:${REM_DIR}
  sshpass -p "${password}" scp -q -o StrictHostKeyChecking=no ${FILE12} ${user}@${host}:${REM_DIR}
  [ -d ${DIR1} ] && sshpass -p "${password}" scp -q -o StrictHostKeyChecking=no -r ${DIR1} ${user}@${host}:${REM_DIR}

  echo "=== Files copied successfully ==="
  echo "Execution begins.. "

  set +e #avoid exiting before files are copied from remote server

  sshpass -p "${password}" ssh -o StrictHostKeyChecking=no ${user}@${host} "${REM_DIR}/${FILE8}" ${REM_DIR}
  sshpass -p "${password}" ssh -o StrictHostKeyChecking=no ${user}@${host} "${PRODUCT_HOME}/bin/integrator.bat"

else
  #for all UNIX instances
  ssh -o StrictHostKeyChecking=no -i ${key_pem} ${user}@${host} mkdir -p ${REM_DIR}
  scp -o StrictHostKeyChecking=no -i ${key_pem} ${FILE1} ${user}@${host}:${REM_DIR}
  scp -o StrictHostKeyChecking=no -i ${key_pem} ${FILE2} ${user}@${host}:${REM_DIR}
  scp -o StrictHostKeyChecking=no -i ${key_pem} ${FILE3} ${user}@${host}:${REM_DIR}
  scp -o StrictHostKeyChecking=no -i ${key_pem} ${FILE4} ${user}@${host}:${REM_DIR}
  scp -o StrictHostKeyChecking=no -i ${key_pem} ${FILE5} ${user}@${host}:${REM_DIR}
  scp -o StrictHostKeyChecking=no -i ${key_pem} ${FILE6} ${user}@${host}:${REM_DIR}
  scp -o StrictHostKeyChecking=no -i ${key_pem} ${FILE7} ${user}@${host}:${REM_DIR}
  scp -o StrictHostKeyChecking=no -i ${key_pem} ${FILE12} ${user}@${host}:${REM_DIR}
  [ -d ${DIR1} ] && scp -o StrictHostKeyChecking=no -i ${key_pem} -r ${DIR1} ${user}@${host}:${REM_DIR}

  echo "=== Files copied successfully ==="

  set +e #avoid exiting before files are copied from remote server

  ssh -o StrictHostKeyChecking=no -i ${key_pem} ${user}@${host} bash ${REM_DIR}/intg-test-runner.sh --wd ${REM_DIR}
  ssh -o StrictHostKeyChecking=no -i ${key_pem} ${user}@${host} bash ${PRODUCT_HOME}/bin/integrator.sh start

fi

wait_for_server_startup
##script ends
