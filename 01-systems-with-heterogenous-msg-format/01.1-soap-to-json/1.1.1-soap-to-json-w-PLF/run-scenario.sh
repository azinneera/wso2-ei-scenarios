#!/bin/bash
#This script clones the scenario-tests repository and execute the tests.

set -o xtrace
repo='https://github.com/yasassri/product-ei-scenario-tests.git'
TEST_DIR='product-ei-scenario-tests'
DIR=$2
export DATA_BUCKET_LOCATION=$DIR

git clone $repo
cd $TEST_DIR
mvn clean install

echo "Copying surefire-reports to data bucket"

cp -r integration/mediation-tests/tests-service/target/surefire-reports ${DIR}
ls ${DIR}
