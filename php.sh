#!/bin/bash

sudo yum update -y # Software update

sudo yum install php-mbstring php-xml -y # Install the required dependencies

sudo systemctl restart httpd # Restart Apache

sudo systemctl restart php-fpm # Restart php-fpm

cd /var/www/html # Navigate to the Apache document root

wget https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.tar.gz # Download the file directly to your instance

mkdir phpMyAdmin && tar -xvzf phpMyAdmin-latest-all-languages.tar.gz -C phpMyAdmin --strip-components 1 # Create a phpMyAdmin folder and extract the package

rm phpMyAdmin-latest-all-languages.tar.gz # Delete the phpMyAdmin-latest-all-languages.tar.gz tarball