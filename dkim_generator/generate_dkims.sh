#!/bin/bash

if [ ! $# == 1 ]; then
    echo Script Usage: $0 domains_file;
    exit;
fi

echo "Generating DKIM Keys for domains in file: $1 ..."
filecontent=( `cat "domains" `)

for d in "${filecontent[@]}"
do 
echo $d

mkdir /opt/msys/ecelerity/etc/conf/dkim/$d
openssl genrsa -out /opt/msys/ecelerity/etc/conf/dkim/$d/dkim1024.key 1024
openssl rsa -in /opt/msys/ecelerity/etc/conf/dkim/$d/dkim1024.key -out /opt/msys/ecelerity/etc/conf/dkim/$d/dkim1024.pub -pubout -outform PEM
echo "Fished Generating DKIM Key!"
echo "Creating DNS Record for domain: $ ..."

TXT='IN TXT'
V='"v=DKIM1;'
H='h=sha256;'
FILE=/opt/msys/ecelerity/etc/conf/dkim/$d/dkim1024.pub
KEY=()
while IFS=$' \t\r\n' read -r LINE; do
    [[ $LINE == *'-END PUBLIC KEY-'* ]] && P=0
    (( P )) && KEY+=("$LINE")  ## Store every line as an array element.
    [[ $LINE == *'-BEGIN PUBLIC KEY-'* ]] && P=1
done < "$FILE"

IFS= eval 'MERGED_KEY="${KEY[*]}"'  ## Merge key without spaces.

P=p="$MERGED_KEY;"
S='s=email"'
T=s"`/bin/date +%m%y`._domainkey.$d $TXT $V $H $P $S"
echo "$T" > /opt/msys/ecelerity/etc/conf/dkim/$d/record.txt



done

echo "Finished Generating DKIM keys!"
