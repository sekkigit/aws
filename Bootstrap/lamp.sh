#!/bin/bash

sudo yum update -y # Software update

sudo amazon-linux-extras install -y lamp-mariadb10.2-php7.2 php7.2 # Nstall the lamp-mariadb10.2-php7.2 and php7.2

sudo yum install -y httpd # Install multiple software packages

sudo systemctl start httpd # Tart the Apache web server

sudo systemctl enable httpd # Start at each system boot

sudo usermod -a -G apache ec2-user # Add your user

sudo chown -R ec2-user:apache /var/www # Change the group ownership of /var/www

sudo chmod 2775 /var/www && find /var/www -type d -exec sudo chmod 2775 {} \; # Change the directory permissions of /var/www

find /var/www -type f -exec sudo chmod 0664 {} \; # Change the file permissions of /var/www

echo "PHP Server $(+%s)" > /var/www/html/index.html