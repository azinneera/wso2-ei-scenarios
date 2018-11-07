#!/bin/bash
set -o xtrace

echo "==============================================================="
export PRODUCT_HOME="/opt/testgrid/test-product"
mkdir -p $PRODUCT_HOME/repository/logs/
echo "Hello World! 1" > $PRODUCT_HOME/repository/logs/wso2carbon.log
curl https://s3.amazonaws.com//aws-cloudwatch/downloads/latest/awslogs-agent-setup.py -O
chmod +x ./awslogs-agent-setup.py
curl https://raw.githubusercontent.com/azinneera/wso2-ei-scenarios/outputs-fix/cloudwatch-agent.config -O
PYTHON=$(which python3)
python --version
python3 --version
python3 awslogs-agent-setup.py -n -r us-east-1 -c cloudwatch-agent.config
                    
echo "Hello World! 2" >> $PRODUCT_HOME/repository/logs/wso2carbon.log
echo "==============================================================="
