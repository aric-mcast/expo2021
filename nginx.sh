#!/bin/bash
VERSION=1.0

#colors
normal=$(tput sgr0)
red=$(tput setaf 1)
green=$(tput setaf 2)
blue=$(tput setaf 4)

DOCKER_START='false'
DOCKER_IMAGE='nginx:1.21.3-alpine'

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
    -h|--help)
      printf "[-d] Start docker container\n[-i] [Image] Specify docker image\n[-v] Get script version\n"
      exit
      ;;
    -v|--version)
    printf "Script version $VERSION\n"
      exit
      ;;
    -d|--docker)
      DOCKER_START="true"
      shift # past argument
      shift # past value
      ;;
    -i|--image)
      DOCKER_IMAGE="$2"
      shift # past argument
      ;;
    *)    # unknown option
      POSITIONAL+=("$1") # save it in an array for later
      shift # past argument
      ;;
  esac
done

printf "${blue}NGINX Docker Setup Script\n${normal}"

printf "Selected Docker Image: $DOCKER_IMAGE\n"

if $DOCKER_START; then
    printf "Checking Docker version..\n"
    if [ -x "$(command -v docker)" ]; then
        printf "${green}$(docker --version)\n${normal}"
    else

        printf "${red}ERROR: Docker NOT INSTALLED\n${normal}"
        printf "Exiting..\n"
        exit
    fi
fi
read -p "Please input website url: https://" url

read -p "Are you sure you want to set up ${blue}https://${url}${normal}? [y/n]:" -n 1 -r


if [[ $REPLY =~ ^[Yy]$ ]]; then
    printf "\nChecking connection to https://${url}..\n"
    # > /dev/null 2>&1 hides output
    if ping -c 1 ${url} > /dev/null 2>&1; then
        printf "${green}Connected successfully!\n${normal}"
    else
        printf "${red}ERROR: Connection failed\n${normal}"
        printf "Exiting..\n"
        exit
    fi
else
    printf "\nUser cancelled setup\n"
    printf "Exiting..\n"
    exit
fi


DIR="$PWD/public_html"

if [ -d "$DIR" ]; then
    printf "Validating ${DIR}...\n"
    if test -f "${DIR}/index.html"; then
        printf "${green}Static page files discovered successfully!\n${normal}"
    else
        printf "${red}ERROR: Static page files do not exist!\n${normal}"
        printf "Exiting..\n"
        exit
    fi
else
    printf "${red}ERROR: ${DIR} Does not exist!\n${normal}"
    printf "Exiting..\n"
    exit
fi


if [ ! -d "$PWD/dhparam" ]; then
    printf "Creating directory dhparam...\n"
    mkdir -p "$PWD/dhparam";
fi

openssl dhparam -out $PWD/dhparam/dhparam-2048.pem 2048

if test -f "$PWD/dhparam/dhparam-2048.pem"; then
    printf "${green}SSL key generated successfully!\n${normal}"
fi


if [ ! -d "$PWD/conf.d" ]; then
    printf "Creating directory conf.d...\n"
    mkdir -p "$PWD/conf.d";
fi


rm -rf $PWD/conf.d/default.conf > /dev/null
tee -a $PWD/conf.d/default.conf > /dev/null <<EOT
server {
    listen 80;
	server_name ${url};
    root /public_html/;

    location ~ /.well-known/acme-challenge{
        allow all;
        root /usr/share/nginx/html/letsencrypt;
    }
}
EOT

if test -f "$PWD/conf.d/default.conf"; then
    printf "${green}NGINX config file generated successfully!\n${normal}"
fi


rm -rf $PWD/docker-compose.yml > /dev/null

tee -a $PWD/docker-compose.yml > /dev/null <<EOT
version: '3.8'

services:
  web:
    image: ${DOCKER_IMAGE}
    restart: always
    volumes:
      - ./public_html:/public_html
      - ./conf.d:/etc/nginx/conf.d/
      - ./dhparam:/etc/nginx/dhparam
      - ./certbot/conf/:/etc/nginx/ssl/
      - ./certbot/data:/usr/share/nginx/html/letsencrypt
    ports:
      - 80:80
      - 443:443
  certbot:
    image: certbot/certbot:latest
    command: certonly --webroot --webroot-path=/usr/share/nginx/html/letsencrypt --email aric.dev@mcast.edu.mt --agree-tos --no-eff-email -d ${url}
    volumes:
        - ./certbot/conf/:/etc/letsencrypt
        - ./certbot/logs/:/var/log/letsencrypt
        - ./certbot/data:/usr/share/nginx/html/letsencrypt
EOT

if test -f "$PWD/docker-compose.yml"; then
    printf "${green}Docker compose file generated successfully!\n${normal}"
fi

if $DOCKER_START; then
    printf "${blue}Initialisating Docker Deployment..\n${normal}"
fi

printf "Starting docker...\n"
sudo docker-compose up -d

docker-compose ps
sleep 5
docker-compose ps
sleep 2

printf "Stopping docker to upgrade configs...\n"
docker-compose down

rm -rf $PWD/conf.d/default.conf > /dev/null
tee -a $PWD/conf.d/default.conf > /dev/null <<EOT
server {
    listen 80;
	server_name ${url};
    root /public_html/;

    location ~ /.well-known/acme-challenge{
        allow all;
        root /usr/share/nginx/html/letsencrypt;
    }
    location / {
        return 301 https://${url}$request_uri;
    }
}

server {
     listen 443 ssl http2;
     server_name ${url};
     root /public_html/;

     ssl on;
     server_tokens off;
     ssl_certificate /etc/nginx/ssl/live/${url}/fullchain.pem;
     ssl_certificate_key /etc/nginx/ssl/live/${url}/privkey.pem;
     ssl_dhparam /etc/nginx/dhparam/dhparam-2048.pem;
     
     ssl_buffer_size 8k;
     ssl_protocols TLSv1.2 TLSv1.1 TLSv1;
     ssl_prefer_server_ciphers on;
     ssl_ciphers ECDH+AESGCM:ECDH+AES256:ECDH+AES128:DH+3DES:!ADH:!AECDH:!MD5;

    location / {
        index index.html;
    }

}
EOT

sleep 2

printf "Restarting docker...\n"

docker-compose up -d
docker-compose ps web

printf "${green}Script completed successfully!\n${normal}"
printf "Exiting..\n"