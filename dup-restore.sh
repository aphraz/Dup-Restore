#!/bin/bash

# Purpose: Restore Database from Backups
# Author: Anas Moiz Hashmi from Cloudways

## Install jq package
apt-get install jq -y   > /dev/null

## START HELP FUNCTION

helpFunction()
{
   echo ""
   echo "Usage: $0 -s serverid -e emailaddress -a apikey"
   echo -e "\t-s Description of what is serverid"
   echo -e "\t-e Description of what is emailaddress"
   echo -e "\t-a Description of what is apikey"
   exit 1 # Exit script after printing help
}

while getopts "s:e:a:" opt
do
   case "$opt" in
      s ) serverid="$OPTARG" ;;
      e ) emailaddress="$OPTARG" ;;
      a ) apikey="$OPTARG" ;;
      ? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
   esac
done

# Print helpFunction in case parameters are empty
if [ -z "$serverid" ] || [ -z "$emailaddress" ] || [ -z "$apikey" ]
then
   echo "Some or all of the parameters are empty";
   helpFunction
fi

# Begin script in case all parameters are correct
echo "The Details entered are"
echo "ServerID :$serverid"
echo "Email Address :$emailaddress"
echo "Api Key :$apikey"

## END HELP FUNCTION

# GET ACCESS TOKEN FRO CLOUDWYAS API
accesstoken="$(curl -s -H "Accept: application/json" -H "Content-Type:application/json" -X POST --data '{"email" : "'$emailaddress'", "api_key" : "'$apikey'"}'  'https://api.cloudways.com/api/v1/oauth/access_token'  | jq -r '.access_token')"

echo "Accesstoken: $accesstoken"

# ALTER SCRIPT
echo -e "Copying duplicity_restore.sh   to   /var/cw/systeam/  \n"
sed '192,199d' /var/cw/scripts/bash/duplicity_restore.sh  >  /var/cw/systeam/duplicity_restore.sh

# GET APPLICATION NAMES
databases=$(find /home/master/applications/* -maxdepth 0 -type d -printf '%f\n')

# START RESTORATION
echo -e "Start Restoration from Duplicity\n"

for db in $databases; do

        # PULLING DUMP
        echo -e "Start Pulling Databases: $db"
        mkdir /var/cw/systeam/$db
        bash /var/cw/systeam/duplicity_restore.sh   --src $db -r --dst /var/cw/systeam/$db

        # CREATING DATABASES in MYSQL
        echo "Creating database: $db in mysql"
        mysql -e "CREATE DATABASE $db;"
        # GET MYSQL PASSWORD FOR DB
        mysqlpwd=$(curl -s  -X GET --header 'Accept: application/json' --header 'Authorization: Bearer '$accesstoken'' 'https://api.cloudways.com/api/v1/server'   |  jq -r   '.servers[]  | select(.id == "'$serverid'") | .apps[] | {mysql_db_name,mysql_password} |  select(.mysql_db_name=="'$db'") | .mysql_password')
        # SET MYSQL PRIVELAGDES
        echo "grant usage: $db in mysql"
        mysql -e "GRANT USAGE ON *.* TO '$db'@'%' IDENTIFIED BY  '$mysqlpwd';"
        echo "grant privleges: $db in mysql"
        mysql -e "GRANT ALL PRIVILEGES ON $db.* TO '$db'@'%';"
        echo "flush"
        mysql -e "FLUSH PRIVILEGES;"
        # IMPORTING DATABASES
        echo -e "Start Restoring Databases: $db"
        mysql $db < /var/cw/systeam/$db/mysql/$db*.sql
done

