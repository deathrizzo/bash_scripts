
#!/bin/bash

if [ ! $# == 1 ]; then
    echo Script Usage: $0 domain;
    exit;
fi

echo "Generating DKIM Keys for domain: $1 ..."

echo $1
mkdir $1

openssl genrsa -out $1/dkim1024.key 1024
openssl rsa -in $1/dkim1024.key -out $1/dkim1024.pub -pubout -outform PEM

echo "Finished Generating DKIM Key!"    
echo "Creating DNS Record for domain: $1 ..."

TXT='IN TXT'
V='"v=DKIM1;'
H='h=sha256;'
FILE=$1/dkim1024.pub

KEY=()
while IFS=$' \t\r\n' read -r LINE; do
    [[ $LINE == *'-END PUBLIC KEY-'* ]] && P=0
    (( P )) && KEY+=("$LINE") 
    [[ $LINE == *'-BEGIN PUBLIC KEY-'* ]] && P=1
done < "$FILE"

IFS= eval 'MERGED_KEY="${KEY[*]}"'  

P=p="$MERGED_KEY;"
S='s=email"'
T=s"`/bin/date +%m%y`._domainkey.$1 $TXT $V $H $P $S"
echo "$T" > $1/record.txt



