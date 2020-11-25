#!/bin/bash

#version 1.05
#CHANGELOG
#
# 2020/11/05
# - Fixed a bug on array comparison with tables with special characters in compare_schema()
# - Added "cluster" to the exclusion list in get_master_dbs
# 2020/10/01
# - Now uses either memsql or mysql client
# - LEAFUSER and LEAFPASS set to USER and PASS if not specified as parameters
# - Fixed typo

# Usage info
show_help() {
cat << EOF
Usage: ${0##*/} [-?] [-v] [-u MASTERUSER] [-p MASTERPASS] [-h MASTERHOST] [-d DATABASE]...
Check tables and schemas across aggregators and leafs for consistency
We assume that Leaf User/Password is consistent across Leaves

    -?,--help       display this help and exit
    -h,--hostname   the master aggregator hostname, defaults to 127.0.0.1
    -lu,--leafuser  the user for the leafs, defaults to --user
    -lp,--leafpass  the password for the leafs, defaults to --pass
    -d,--database   run the consistency check only against specified db
    -p,--password   the password for the master aggregator if necessary
    -P,--port       the port for the master aggregator, defaults to 3306
    -u,--user       the user for the master aggregator, defaults to cur user
    -v              verbose mode. Can be used multiple times for increased
                    verbosity.
EOF
}

################################
# Initialize our own variables #
################################

USER=$(whoami)
PASS=${MYSQL_PWD}
HOST="127.0.0.1"
PORT=3306
verbose=0
S_DATABASE=""

MYSQL=$(which memsql)
hash "$MYSQL" 2>/dev/null || { echo >&2 "MemSQL client not found. Looking for MySQL client instead..."; MYSQL=$(which mysql); } 
hash "$MYSQL" 2>/dev/null || { echo >&2 "MemSQL or MySQL client required but not found in the path. Either install one of the clients or make sure your PATH variable includes it. Aborting."; exit 1; }


while :; do
    case $1 in
        -\?|--help)
            show_help
            exit
            ;;
        -h?*)
            HOST=${1:2}
            ;;
        -h|--hostname)       # Takes an option argument, ensuring it has been specified.
            if [ -n "$2" ]; then
                HOST=$2
                shift
            else
                printf 'ERROR: "--hostname" requires a non-empty argument.\n' >&2
                exit 1
            fi
            ;;
        --hostname=?*)
            HOST=${1#*=}
            ;;
        --hostname=)
            printf 'ERROR: "--hostname" requires a non-empty argument.\n' >&2
            exit 1
            ;;
        -d|--database)
            if [ -n "$2" ]; then
                S_DATABASE=$2
                shift
            else
                printf 'ERROR: "--database" requires a non-empty argument.\n' >&2
                exit 1
            fi
            ;;
        --database=?*)
            S_DATABASE=${1#*=}
            ;;
        --database=)
            printf 'ERROR: "--database" requires a non-empty argument.\n' >&2
            exit 1
            ;;
        -lu?*)
            LEAFUSER=${1:3}
            ;;
        -lu|--leafuser)
            if [ -n "$2" ]; then
                LEAFUSER=$2
                shift
            else
                printf 'ERROR: "--leafuser" requires a non-empty argument.\n' >&2
                exit 1
            fi
            ;;
        --leafuser=?*)
            LEAFUSER=${1#*=}
            ;;
        --leafuser=)
            printf 'ERROR: "--leafuser" requires a non-empty argument.\n' >&2
            exit 1
            ;;
        -lp?*)
            LEAFPASS=${1:3}
            ;;
        -lp|--leafpass)
            if [ -n "$2" ]; then
                LEAFPASS=$2
                shift
            else
                printf 'ERROR: "--leafpass" requires a non-empty argument.\n' >&2
                exit 1
            fi
            ;;
        --leafpass=?*)
            LEAFPASS=${1#*=}
            ;;
        --leafpass=)
            printf 'ERROR: "--leafpass" requires a non-empty argument.\n' >&2
            exit 1
            ;;
        -p?*)
            PASS=${1:2}
            ;;
        -p|--password)
            if [ -n "$2" ]; then
                PASS=$2
                shift
            else
                printf 'ERROR: "--password" requires a non-empty argument.\n' >&2
                exit 1
            fi
            ;;
        --password=?*)
            PASS=${1#*=}
            ;;
        --password=)
            printf 'ERROR: "--password" requires a non-empty argument.\n' >&2
            exit 1
            ;;
        -P|--port)
            if [ -n "$2" ]; then
                PORT=$2
                shift
            else
                printf 'ERROR: "--port" requires a non-empty argument.\n' >&2
                exit 1
            fi
            ;;
        --port=?*)
            PORT=${1#*=}
            ;;
        --port=)
            printf 'ERROR: "--port" requires a non-empty argument.\n' >&2
            exit 1
            ;;
        -u?*)
            USER=${1:2}
            ;;
        -u|--user)
            if [ -n "$2" ]; then
                USER=$2
                shift
            else
                printf 'ERROR: "--user" requires a non-empty argument.\n' >&2
                exit 1
            fi
            ;;
        --user=?*)
            USER=${1#*=}
            ;;
        --user=)
            printf 'ERROR: "--user" requires a non-empty argument.\n' >&2
            exit 1
            ;;

        -v|--verbose)
            verbose=$((verbose + 1)) # Each -v argument adds 1 to verbosity.
            ;;
        --)              # End of all options.
            shift
            break
            ;;
        -?*)
            printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2
            ;;
        *)               # Default case: If no more options then break out of the loop.
            break
    esac

    shift
done

# If LEAFUSER not specified in the command line, set it to USER
if [ -z $LEAFUSER ]; then LEAFUSER=${USER}; fi

# If LEAFPASS not specified in the command line, set it to PASS
if [ -z $LEAFPASS ]; then LEAFPASS=${PASS}; fi

if [[ $verbose -gt 1 ]]; then
  echo "Variables:
USER=${USER}
PASS=${PASS}
HOST=${HOST}
PORT=${PORT}
LEAFUSER=${LEAFUSER}
LEAFPASS=${LEAFPASS}
DATABASE=${S_DATABASE}
VERBOSE=${verbose}
"
fi

#################
# The Functions #
#################

function mysql_master_query {

  query=${1}

  MYSQL_PWD="${PASS}" ${MYSQL} -N --user="${USER}" --host="${HOST}" --port="${PORT}" -e "${query}"

}

function mysql_leaf_query {

  local host=${1}
  local port=${2}
  local query=${3}

  MYSQL_PWD="${LEAFPASS}" ${MYSQL} -N --user="${LEAFUSER}" --host="${host}" --port="${port}" -e "${query}"
}

function memsql_version {

  local host=${1}
  local port=${2}

  version=$(mysql_leaf_query $host $port "show variables like 'memsql_version'")
  if [[ $verbose -gt 0 ]]; then echo "${version} on ${host}:${port}"; fi
}

function get_master_dbs {

  dbs=()
  if [ -z "$S_DATABASE" ]
    then
      if [[ $verbose -gt 0 ]]; then echo "Single database not specified. Running for all"; fi
      if [[ $verbose -gt 0 ]]; then echo "Getting databases from master"; fi
      while IFS="$( echo -e '\t' )" read database; do

      if [[ $verbose -gt 0 ]]; then echo "Found database: ${database}"; fi
      dbs+=("${database}")

      done < <(mysql_master_query "select schema_name from information_schema.schemata where schema_name not in ('information_schema', 'memsql', 'sharding','cluster')")

    else
      if [[ $verbose -gt 0 ]]; then echo "Single database specified. Runnign only for database $S_DATABASE"; fi
      dbs+=($S_DATABASE)
  fi

  if [[ ${#dbs[@]} -eq 0 ]]; then echo "No databases found!!! exiting"; exit 1; fi

}

function get_master_known_partitions {

  parts=()
  local db=$1
  local host=$2
  local port=$3
  if [[ $verbose -gt 0 ]]; then echo "Getting partitions from master for ${db} on ${host}:${port}"; fi
  while IFS="$( echo -e '\t' )" read database_name ordinal; do

    if [[ $verbose -gt 0 ]]; then echo "Found partition: ${database_name}_${ordinal}"; fi
    parts+=("${database_name}_${ordinal}")

  done < <(mysql_master_query "select database_name, ordinal from information_schema.table_statistics where database_name='${db}' and partition_type='Master' and host='${host}' and port='${port}' group by database_name, ordinal order by database_name,ordinal")

}

function get_master_tbls {

  tbls=()
  local db=$1
  if [[ $verbose -gt 0 ]]; then echo "Getting tables for ${db} from Master"; fi
  while IFS="$( echo -e '\t' )" read table; do
    if [[ $verbose -gt 0 ]]; then echo "Found table: ${table}"; fi
    tbls+=("${table}")

  done < <(mysql_master_query "select table_name from information_schema.tables where table_schema='${db}' order by table_name")

}

function get_leaf_tbls {

  leaf_tbls=()
  local db=$1
  local host=$2
  local port=$3
  if [[ $verbose -gt 0 ]]; then echo "Getting tables for ${db} from Leaf ${host}:${port}"; fi
  while IFS="$( echo -e '\t' )" read table; do
    if [[ $verbose -gt 0 ]]; then echo "Found table: ${table}"; fi
    leaf_tbls+=("${table}")

  done < <(mysql_leaf_query ${host} ${port} "select table_name from information_schema.tables where table_schema='${db}' order by table_name")

}

function get_master_ref_tbls {

  ref_tbls=()
  local db=$1
  if [[ $verbose -gt 0 ]]; then echo "Getting Reference tables for ${db} from Master"; fi
  while IFS="$( echo -e '\t' )" read table; do
    if [[ $verbose -gt 0 ]]; then echo "Found Reference table: ${table}"; fi
    ref_tbls+=("${table}")

  done < <(mysql_master_query "select table_name from information_schema.table_statistics where database_name='${db}' and NODE_TYPE='Aggregator' and PARTITION_TYPE='Reference' order by table_name")

}

function get_leaves {

  leaves=()
  if [[ $verbose -gt 0 ]]; then echo "Getting leaves from master"; fi
  while IFS="$( echo -e '\t' )" read host port; do

    if [[ $verbose -gt 0 ]]; then echo "Found leaf at ${host}:${port}"; fi
    leaves+=("${host}:${port}")

  done < <(mysql_master_query "select host, port from information_schema.leaves")

  if [[ ${#leaves[@]} -eq 0 ]]; then echo "No leaves found!!! exiting"; exit 1; fi

}

function compare_schema {

  local host=$HOST
  local port=$PORT
  local db=\`$1\`
  local tbl=\`$2\`
  local leaf_host=$3
  local leaf_port=$4
  local leaf_db=\`$5\`
  local leaf_tbl=\`$6\`

  master_table_schema=$(mysql_master_query "describe ${db}.${tbl}")
  master_table_schema_without_auto_increment=$(echo $master_table_schema | sed 's/auto_increment//g' | sed 's/MUL//g' | sed 's/ //g')
  leaf_table_schema=$(mysql_leaf_query $leaf_host $leaf_port "describe ${leaf_db}.${leaf_tbl}")
  leaf_table_schema_without_auto_increment=$(echo $leaf_table_schema | sed 's/auto_increment//g' | sed 's/MUL//g' | sed 's/ //g')

  if [[ "${master_table_schema_without_auto_increment}" != "${leaf_table_schema_without_auto_increment}" ]]; then
    echo "Schema ${db}.${tbl} on master ${host}:${port} does not match on leaf ${leaf_host}:${leaf_port} partition ${leaf_db}.${leaf_tbl}. master:${master_table_schema_without_auto_increment}leaf:${leaf_table_schema_without_auto_increment}"
  fi

}


# this function basically takes two arrays defined in arr1 and arr2 and removes the elements in arr2 from arr1 returning clean_arr
function remove_from_array {
  clean_arr=()
  for i in ${arr1[@]}; do
    skip=
    for j in ${arr2[@]}; do
      [[ $i == $j ]] && { skip=1; break; }
    done
    [[ -n $skip ]] || clean_arr+=("$i")
  done

}

function similar_array {

  merged_arr=()
  for i in ${arr1[@]}; do
    for j in ${arr2[@]}; do
      [[ $i == $j ]] && { merged_arr+=("$i"); break; }
    done
  done

}


#############################################################
# Everything happens below here calling the functions above #
#############################################################

echo ""
echo `date`
echo "****************************** STARTING - MemSQL_Consistency_Checker.sh *********************************"
echo ""

get_leaves

# Check version
memsql_version $HOST $PORT
master_version=${version}
for leaf in ${leaves[@]}; do
  host=${leaf%:*}
  port=${leaf#*:}
  memsql_version $host $port

  if [[ "${master_version}" != "${version}" ]]; then
    echo "${version} on ${host}:${port} does not match Master ${master_version} on ${HOST}:${PORT}"
  fi
done

get_master_dbs

for db in ${dbs[@]}; do
  get_master_tbls $db
  get_master_ref_tbls $db
  # clean up master tables removing reference tables, so we can work them separately
  arr1=("${tbls[@]}"); arr2=("${ref_tbls[@]}"); remove_from_array
  no_ref_tbls=${clean_arr[@]}
  for leaf in ${leaves[@]}; do
    host=${leaf%:*}
    port=${leaf#*:}

    # Master Partitions
    get_leaf_tbls $db $host $port

    # compare arrays to see if there is a difference, if there is, we have an issue
    arr1=("${tbls[@]}"); arr2=("${leaf_tbls[@]}"); remove_from_array
    for tbl in ${clean_arr[@]}; do
      echo "Missing table ${db}.${tbl} from leaf ${host}:${port}"
    done
    arr1=("${leaf_tbls[@]}"); arr2=("${tbls[@]}"); remove_from_array
    for tbl in ${clean_arr[@]}; do
      echo "Orphaned table ${db}.${tbl} is on leaf ${host}:${port}"
    done

    # compare schemas
    arr1=("${leaf_tbls[@]}"); arr2=("${tbls[@]}"); similar_array
    for tbl in ${merged_arr[@]}; do
      compare_schema $db $tbl $host $port $db $tbl
    done

    # Slave Partitions
    get_master_known_partitions $db $host $port
    for part in ${parts[@]}; do
      get_leaf_tbls $part $host $port
      # compare arrays to see if there is a difference, if there is, we have an issue
      arr1=("${no_ref_tbls[@]}"); arr2=("${leaf_tbls[@]}"); remove_from_array
      for tbl in ${clean_arr[@]}; do
        echo "Missing table ${part}.${tbl} from leaf ${host}:${port}"
      done
      arr1=("${leaf_tbls[@]}"); arr2=("${no_ref_tbls[@]}"); remove_from_array
      for tbl in ${clean_arr[@]}; do
        echo "Orphaned table ${part}.${tbl} is on leaf ${host}:${port}"
      done

      # compare schemas
      arr1=("${leaf_tbls[@]}"); arr2=("${no_ref_tbls[@]}"); similar_array
      for tbl in ${merged_arr[@]}; do
        compare_schema $db $tbl $host $port $part $tbl
      done
    done

  done
done

echo ""
echo "****************************** DONE - MemSQL_Consistency_Checker.sh *********************************"
echo ""
