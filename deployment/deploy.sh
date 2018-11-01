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

echo "Running deploy.sh..."
pwd

DIR=$2
DIR1=integration
FILE1=${DIR}/infrastructure.properties
FILE2=${DIR}/testplan-props.properties

host="https"`grep -w "MgtConsoleUrl" ${FILE1} ${FILE2} | cut -d'=' -f2 | cut -d'\' -f2`

CONNECT_RETRY_COUNT=20

##script ends

echo "waiting for product in $host"
wait_for_server_startup() {
    max_attempts=100
    attempt_counter=0

    MGT_CONSOLE_URL=$host
    until $(curl -k --output /dev/null --silent --head --fail $MGT_CONSOLE_URL); do
       if [ ${attempt_counter} -eq ${max_attempts} ];then
        echo "Max attempts reached"
        exit 1
       fi
        printf '.'
        attempt_counter=$(($attempt_counter+1))
        sleep 10
    done
}

wait_for_server_startup

