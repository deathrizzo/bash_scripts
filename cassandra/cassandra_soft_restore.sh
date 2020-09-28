#!/bin/bash
# RESTORES SNAPSHOTS FILES MATCHING THE KEY PASSED
# GIVES A CONFIRM PROMPT, READ BEFORE YOU ACCEPT!!! THERE IS NO TURNING BACK!!!
# PREVIOUS DATA MAY BE LOST!!!
# THIS IS A LIVE RESTORE: C* STAYS UP, MUST BE SAME VERSION AND SAME SCHEMA!!!

shopt -s nullglob

##################### CONSTANTS SECTION ############################################
NODETOOL=/opt/msys/3rdParty/cassandra/bin/nodetool
COMMIT_BKUP=/cassandra-backups/commitlog

##################### FUNCTIONS SECTION ############################################

function proceed_prompt ()
{
  printf "\n\n"
  read -p "### Ok to proceed? (y/n)" OK_TO_PROCEED
  if [[ "$OK_TO_PROCEED" == "y" ]] || [[ "$OK_TO_PROCEED" == "Y" ]]; then
    printf "\n Proceeding...\n"
  else
    printf "\nAborting...\n"
    exit 1
  fi
}

function check_cassandra_is_running ()
{
  printf "Checking Cassandra status...\n"
  CHECK1=$($NODETOOL info 2>&1)
  CHECK2=$($NODETOOL status 2>&1)
  if [[ "$CHECK1" == *"Failed"* ]] || [[ "$CHECK1" == *"refused"* ]]; then
    printf "$CHECK1\nERROR!  Cassandra is not running as expected. Aborting...\n"
    exit 254
  fi
  if [[ "$CHECK2" == *"Failed"* ]] || [[ "$CHECK2" == *"refused"* ]]; then
    printf "$CHECK2\nERROR!  Cassandra is not running as expected. Aborting...\n"
    exit 254
  fi
  if [[ "$CHECK2" == *"Exception"* ]] || [[ "$CHECK2" == *"Error"* ]]; then
    printf "$CHECK2\nERROR!  Cassandra is not running as expected. Aborting...\n"
    exit 254
  fi
  if [[ "$CHECK2" != *"UN"* ]]; then
    printf "$CHECK2\nERROR!  Cassandra is not running as expected. Aborting...\n"
    exit 254
  fi  
}

##################### INITIAL SANITY CHECK #########################################

# snapshot key, if made from ansible it should be the Cassandra release
SNAPKEY=$1

if [[ $SNAPKEY == "" ]]; then
  printf "The snapshot key cannot be blank. Aborting. \n"
  printf "Usage is: cassandra_soft_restore.sh <keystring>\n"
  printf "          where <keystring> is a unique part of the snapshot name\n"
  exit 253
fi

ALL_SNAPSHOT_PATHS=(/var/db/cassandra/data/*/*/snapshots/*$SNAPKEY*/*)
if [[ ${#ALL_SNAPSHOT_PATHS[@]} < 1 ]]; then
  printf "The snapshot key cannot be found! Nothing to restore. Aborting. \n"
  exit 252
fi

##################### WARN AND GET CONFIRMATION ####################################

printf "\n\nRESTORES SNAPSHOTS FILES MATCHING THE KEY PASSED \n"
printf "GIVES A CONFIRM PROMPT, READ BEFORE YOU ACCEPT!!! THERE IS NO TURNING BACK!!! \n"
printf "PREVIOUS DATA MAY BE LOST!!! \n"
printf "THIS IS A LIVE RESTORE: C* STAYS UP, MUST BE SAME VERSION AND SAME SCHEMA!!! \n"
proceed_prompt

##################### DRYRUN SECTION - NOT OPTIONAL BY DESIGN ######################

EXCL_KSPACES="'/var/db/cassandra/data/system' '/var/db/cassandra/data/system_traces' '/var/db/cassandra/data/system_auth' '/var/db/cassandra/data/system_distributed'"
KEYSPACE_PATHS=(/var/db/cassandra/data/*)
for KP in "${KEYSPACE_PATHS[@]}"
do
  if [[ "$EXCL_KSPACES" == *"'$KP'"* ]]; then
    printf "Skipping keyspace $KP \n"
  else
    CFPATHS=($KP/*)
    for CFP in "${CFPATHS[@]}"
    do
      SNAP_FILES=($CFP/snapshots/*$SNAPKEY*/*)
      for SFILE in "${SNAP_FILES[@]}"
      do
        printf "Will copy: $SFILE\n  To: $CFP/${SFILE##*/}\n"
      done
    done
  fi  
done

proceed_prompt

##################### LIVE RUN - RESTORING BACKUP ##################################
printf "Making backup of commit log in: $COMMIT_BKUP\n"
mkdir -p $COMMIT_BKUP
rm $COMMIT_BKUP/*
cp -r /var/db/cassandra/commitlog/* $COMMIT_BKUP/

printf "$NODETOOL flush \n"
$NODETOOL flush 

KEYSPACE_PATHS=(/var/db/cassandra/data/*)
for KP in "${KEYSPACE_PATHS[@]}"
do
  if [[ "$EXCL_KSPACES" == *"'$KP'"* ]]; then
    printf "Skipping keyspace $KP \n"
  else
    CFPATHS=($KP/*)
    for CFP in "${CFPATHS[@]}"
    do
      SNAP_FILES=($CFP/snapshots/*$SNAPKEY*/*)
      for SFILE in "${SNAP_FILES[@]}"
      do
        cp $SFILE $CFP/${SFILE##*/}
      done  
    done
  fi  
done 
chown -R msys-cass:msys-cass /var/db/cassandra/data

kspaces=$(echo "DESCRIBE KEYSPACES;" | /opt/msys/3rdParty/bin/cqlsh)
for k in $kspaces
do
  if [[ "$EXCL_KSPACES" == *"'$k'"* ]]; then
    printf "Skipping keyspace $k \n"
  else
    ktables=$(echo "USE $k; DESCRIBE TABLES;" | /opt/msys/3rdParty/bin/cqlsh)
    for t in $ktables 
      do
        printf "$NODETOOL refresh -- $k $t \n"  
        $NODETOOL refresh -- $k $t
      done
  fi  
done

printf "\nAll done!  Move to next C* node if applicable.  Once all done, repair plan should be run. \n"
printf "\nAlso, remember to clear space later by deleting backup in:  $COMMIT_BKUP\n"

