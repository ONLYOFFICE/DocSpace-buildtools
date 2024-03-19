#!/bin/bash
set -e

#Create a hashed password using bcrypt and write it to the .htpasswd_dashboard file
echo "${DASHBOARD_USERNAME:-admin}:$(openssl passwd -6 -stdin <<< "${DASHBOARD_PASSWORD:-admin}")" > /etc/nginx/.htpasswd_dashboard 
