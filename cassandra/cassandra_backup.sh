#!/bin/bash
#
# Description : The backup script will complete the backup in 2 phases -
#  1. First Phase: Taking backup of Keyspace SCHEMA
#  2. Seconf Phase: Taking snapshot of keyspaces
#

#read AWS vars
#source /etc/aws/s3archive.sh

#if [ "$AWS_SECRET_ACCESS_KEY" == "" ]; then
#        echo "AWS secret key not set, exiting"
#        exit 2
#fi


# This block is for messagesystems
_BACKUP_DIR=/cassandra-backups/
_DATA_DIR=/var/db/cassandra/data
_NODETOOL=/opt/msys/3rdParty/cassandra/bin/nodetool
_CQLSH=/opt/msys/3rdParty/bin/cqlsh
_BUCKET="msys-cassandra-backups"
_PREFIX=`hostname | awk -F "." '{print $2}'`/


## Do not edit below given variable ##

_TODAY_DATE=$(date +%F)
_BACKUP_SNAPSHOT_DIR="$_BACKUP_DIR/$_TODAY_DATE/SNAPSHOTS"
_BACKUP_SCHEMA_DIR="$_BACKUP_DIR/$_TODAY_DATE/SCHEMA"
_SNAPSHOT_DIR=$(find $_DATA_DIR -type d -name snapshots)
_SNAPSHOT_NAME=`hostname`-snp-$(date +%F-%H%M-%S)
_DATE_SCHEMA=$(date +%F-%H%M-%S)

###### Create / check backup Directory ####

if [ -d  "$_BACKUP_SCHEMA_DIR" ]
then
echo "$_BACKUP_SCHEMA_DIR already exist"
else
mkdir -p "$_BACKUP_SCHEMA_DIR"
fi

if [ -d  "$_BACKUP_SNAPSHOT_DIR" ]
then
echo "$_BACKUP_SNAPSHOT_DIR already exist"
else
mkdir -p "$_BACKUP_SNAPSHOT_DIR"
fi



##################### SECTION 1 : SCHEMA BACKUP ############################################

## List All Keyspaces
$_CQLSH -e "DESC KEYSPACES" |perl -pe 's/\e([^\[\]]|\[.*?[a-zA-Z]|\].*?\a)//g' | sed '/^$/d' > Keyspace_name_schema.cql

#_KEYSPACE_NAME=$(cat Keyspace_name_schema.cql)

## Create directory inside backup SCHEMA directory. As per keyspace name.
for i in $(cat Keyspace_name_schema.cql)
do
if [ -d $i ]
then
echo "$i directory exist"
else
mkdir -p $_BACKUP_SCHEMA_DIR/$i
fi
done

## Take SCHEMA Backup - All Keyspace and All tables
for VAR_KEYSPACE in $(cat Keyspace_name_schema.cql)
do
$_CQLSH -e "DESC KEYSPACE  $VAR_KEYSPACE" > "$_BACKUP_SCHEMA_DIR/$VAR_KEYSPACE/$VAR_KEYSPACE"_schema-"$_DATE_SCHEMA".cql
done


##################### END OF LINE ---- SECTION 1 : SCHEMA BACKUP #####################

###### Create snapshots for all keyspaces
echo "creating snapshots for all keyspaces ....."
$_NODETOOL snapshot -t $_SNAPSHOT_NAME

###### Get Snapshot directory path
_SNAPSHOT_DIR_LIST=`find $_DATA_DIR -type d -name snapshots|awk '{gsub("'$_DATA_DIR'", "");print}' > snapshot_dir_list`

#echo $_SNAPSHOT_DIR_LIST > snapshot_dir_list

## Create directory inside backup directory. As per keyspace name.
for i in `cat snapshot_dir_list`
do
if [ -d $_BACKUP_SNAPSHOT_DIR/$i ]
then
echo "$i directory exist"
else
mkdir -p $_BACKUP_SNAPSHOT_DIR/$i
echo $i Directory is created
fi
done

### Copy default Snapshot dir to backup dir

find $_DATA_DIR -type d -name $_SNAPSHOT_NAME > snp_dir_list

for SNP_VAR in `cat snp_dir_list`;
do
## Triming _DATA_DIR
_SNP_PATH_TRIM=`echo $SNP_VAR|awk '{gsub("'$_DATA_DIR'", "");print}'`

cp -prvf "$SNP_VAR" "$_BACKUP_SNAPSHOT_DIR$_SNP_PATH_TRIM";

done

tar -zcf $_BACKUP_DIR/`hostname`-snapshot-$_TODAY_DATE.tar.gz $_BACKUP_DIR/$_TODAY_DATE 

_FILE_LIST=`find $_BACKUP_DIR -type f -name "*.gz"`
for FILE in ${_FILE_LIST[*]}
do
    s3cmd put $FILE s3://$_BUCKET/$_PREFIX -v --server-side-encryption --no-check-md5
#s3put -a $AWS_ACCESS_KEY_ID -s $AWS_SECRET_ACCESS_KEY -b $_BUCKET -k $_PREFIX $FILE
done

rm -rf $_BACKUP_DIR/$_TODAY_DATE
rm $_FILE_LIST
$_NODETOOL clearsnapshot
