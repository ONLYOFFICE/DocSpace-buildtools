#!/bin/sh

echo "##################################################################"
echo "##### Run preparation for launching ONLYOFFICE Apps services #####"
echo "##################################################################"
cp -r /app/ASC.Files/server/* /var/www/products/ASC.Files/server/
cp -r /app/ASC.People/server/* /var/www/products/ASC.People/server/
cp -r /app/ASC.AI/server/* /var/www/products/ASC.AI/server/
echo "Ok" > /var/www/products/ASC.Files/server/status.txt
echo "Preparation for launching ONLYOFFICE Apps services is complete"
