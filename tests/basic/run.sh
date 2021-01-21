#!/bin/sh
#
# Copyright 2020 PingCAP, Inc. Licensed under Apache-2.0.

set -eu
cur=$(cd `dirname $0`; pwd)

DB_NAME="basic"
TABLE_NAME="t"
SEQUENCE_NAME="s"

# Test for simple case.
run_sql "drop database if exists \`$DB_NAME\`;"
run_sql "create database \`$DB_NAME\`;"
run_sql "create table \`$DB_NAME\`.\`$TABLE_NAME\` (a int);"
run_sql "insert into \`$DB_NAME\`.\`$TABLE_NAME\` values (1), (2);"

run_dumpling -f "$DB_NAME.$TABLE_NAME"

cnt=`grep -w "(.*)" ${DUMPLING_OUTPUT_DIR}/${DB_NAME}.${TABLE_NAME}.000000000.sql|wc -l`
echo "records count is ${cnt}"
[ "$cnt" = 2 ]

# Test for simple WHERE case.
run_sql "drop database if exists \`$DB_NAME\`;"
run_sql "create database \`$DB_NAME\`;"
run_sql "create table \`$DB_NAME\`.\`$TABLE_NAME\` (a int);"

seq 10 | xargs -I_ run_sql "insert into \`$DB_NAME\`.\`$TABLE_NAME\` values (_);"

run_dumpling --where "a >= 3 and a <= 9" -f "$DB_NAME.$TABLE_NAME"

actual=$(grep -w "(.*)" ${DUMPLING_OUTPUT_DIR}/${DB_NAME}.${TABLE_NAME}.000000000.sql | cut -c2-2)
expected=$(seq 3 9)
echo "expected ${expected}, actual ${actual}"
[ "$actual" = "$expected" ]

export DUMPLING_TEST_PORT=4000
# Test for --sql option.
run_sql "drop database if exists \`$DB_NAME\`;"
run_sql "create database \`$DB_NAME\`;"
run_sql "create sequence \`$DB_NAME\`.\`$SEQUENCE_NAME\` increment by 1;"

run_dumpling --sql "select nextval(\`$DB_NAME\`.\`$SEQUENCE_NAME\`)"

actual=$(grep -w "(.*)[,|;]" ${DUMPLING_OUTPUT_DIR}/result.000000000.sql | cut -c2-2)
echo "expected 1, actual ${actual}"
[ "$actual" = 1 ]

run_dumpling --sql "select nextval(\`$DB_NAME\`.\`$SEQUENCE_NAME\`)"

actual=$(grep -w "(.*)[,|;]" ${DUMPLING_OUTPUT_DIR}/result.000000000.sql | cut -c2-2)
echo "expected 2, actual ${actual}"
[ "$actual" = 2 ]

# Test for tidb_mem_quota_query configuration
export GO_FAILPOINTS="github.com/pingcap/dumpling/v4/export/PrintTiDBMemQuotaQuery=1*return"
run_dumpling > ${DUMPLING_OUTPUT_DIR}/dumpling.log
actual=`grep -w "tidb_mem_quota_query == 1073741824" ${DUMPLING_OUTPUT_DIR}/dumpling.log|wc -l`
echo "expected 1, actual ${actual}"
[ "$actual" = 1 ]

export GO_FAILPOINTS=""

set +e
# Test for wrong sql causing panic problem: https://github.com/pingcap/dumpling/pull/234#issuecomment-759996695
run_dumpling --sql "test" >> ${DUMPLING_OUTPUT_DIR}/dumpling.log 2>> ${DUMPLING_OUTPUT_DIR}/dumpling.err
set -e

# check stderr, should not contain panic info
actual=`grep -w "panic" ${DUMPLING_OUTPUT_DIR}/dumpling.err|wc -l`
echo "expected panic 0, actual ${actual}"
[ "$actual" = 0 ]

# check stdout, should contain mysql error log
actual=`grep -w "Error 1064: You have an error in your SQL syntax" ${DUMPLING_OUTPUT_DIR}/dumpling.log|wc -l`
echo "expect contain Error 1064, actual ${actual}"
[ "$actual" -ge 1 ]
