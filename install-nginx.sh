#!/bin/bash

echo -e "\033[32m -----"
echo -e "\033[32m Building for ${CONTAINER_ENGINE} with ${NETWORK}"
echo -e "\033[32m -----\033[0m"

if [ "$NETWORK" = "fabric" ]
then
    wget -O /usr/local/bin/generate_config -q https://s3-us-west-1.amazonaws.com/fabric-model/config-generator/generate_config
    chmod +x /usr/local/bin/generate_config

    GENERATE_CONFIG_FILE=/usr/local/bin/generate_config
    TEMPLATE_FILE_PLUS=/etc/nginx/nginx-plus-fabric.conf.j2
    TEMPLATE_FILE=/etc/nginx/nginx-fabric.conf.j2

    case "$CONTAINER_ENGINE" in
        kubernetes)
            CONFIG_FILE=/etc/nginx/fabric_config_k8s.yaml
            ;;
        local)
            CONFIG_FILE=/etc/nginx/fabric_config_local.yaml
            ;;
        *)
            CONFIG_FILE=/etc/nginx/fabric_config.yaml
            ;;
    esac
else
    GENERATE_CONFIG_FILE=/usr/local/bin/generate_config_router_mesh
    TEMPLATE_FILE_PLUS=/etc/nginx/nginx-plus-router-mesh.conf.j2
    TEMPLATE_FILE=/etc/nginx/nginx-router-mesh.conf.j2

    case "$CONTAINER_ENGINE" in
        kubernetes)
            CONFIG_FILE=/etc/nginx/router-mesh_config_k8s.yaml
            ;;
        local)
            CONFIG_FILE=/etc/nginx/router-mesh_config.yaml
            ;;
        *)
            CONFIG_FILE=/etc/nginx/fabric_config.yaml 
            ;;
    esac
fi


if [ "$USE_VAULT" = true ]; then
# Install vault client
    wget -q https://releases.hashicorp.com/vault/0.5.2/vault_0.5.2_linux_amd64.zip && \
	unzip -d /usr/local/bin vault_0.5.2_linux_amd64.zip && \
	. /etc/ssl/nginx/vault_env.sh && \
	mkdir -p /etc/ssl/nginx && \
	vault token-renew && \
	vault read -field=value secret/ssl/dhparam.pem > /etc/ssl/nginx/dhparam.pem && \
	vault read -field=value secret/letsencrypt/cert.pem > /etc/ssl/nginx/cert.pem && \
	vault read -field=value secret/letsencrypt/chain.pem > /etc/ssl/nginx/chain.pem && \
	vault read -field=value secret/letsencrypt/fullchain.pem > /etc/ssl/nginx/fullchain.pem && \
	vault read -field=value secret/letsencrypt/privkey.pem > /etc/ssl/nginx/privkey.pem

    if [ "$USE_NGINX_PLUS" = true ]; then
        vault read -field=value secret/nginx-repo.crt > /etc/ssl/nginx/nginx-repo.crt
        vault read -field=value secret/nginx-repo.key > /etc/ssl/nginx/nginx-repo.key
        vault read -field=value secret/ssl/csr.pem > /etc/ssl/nginx/csr.pem
    fi

else
# ensure certificate files exist
    if [[ ! -f /etc/ssl/nginx/certificate.pem || ! -f /etc/ssl/nginx/key.pem ]]; then
        echo -e "\033[31m -----"
        echo -e "\033[31m The certificate.pem or key.pem file does not exist in /etc/ssl/nginx"
        echo -e "\033[31m These files should copied by the COPY command in Dockerfile when USE_VAULT is false."
        echo -e "\033[31m If you are using vault, be sure that USE_VAULT is true in the Dockerfile."
        echo -e "\033[31m Generating self-signed certificates instead."
        echo -e "\033[31m -----\033[0m"
        openssl req -nodes -newkey rsa:2048 -keyout /etc/ssl/nginx/key.pem -out /etc/ssl/nginx/csr.pem -subj \
            "/C=US/ST=California/L=San Francisco/O=NGINX/OU=Professional Services/CN=proxy"
        openssl x509 -req -days 365 -in /etc/ssl/nginx/csr.pem -signkey /etc/ssl/nginx/key.pem -out /etc/ssl/nginx/certificate.pem
    fi

    if [ "$USE_NGINX_PLUS" = true ]; then
        if [[ ! -f /etc/ssl/nginx/nginx-repo.crt && ! -f /etc/ssl/nginx/nginx-repo.key ]]; then
            echo -e "\033[31m -----"
            echo -e "\033[31m The nginx-repo.crt and nginx-repo.key files were not found in /etc/ssl/nginx"
            echo -e "\033[31m These file should copied by the COPY command in Dockerfile when USE_VAULT is false."
            echo -e "\033[31m If you have implemented vault, be sure that USE_VAULT is true in the Dockerfile."
            echo -e "\033[31m -----\033[0m"
            exit 1;
        fi
    fi
fi


if [ "$USE_NGINX_PLUS" = true ];
then
  echo "Installing NGINX Plus"

  wget -q -O /etc/ssl/nginx/CA.crt https://cs.nginx.com/static/files/CA.crt
  wget -q -O - http://nginx.org/keys/nginx_signing.key | apt-key add -
  wget -q -O /etc/apt/apt.conf.d/90nginx https://cs.nginx.com/static/files/90nginx
  printf "deb https://plus-pkgs.nginx.com/`lsb_release -is | awk '{print tolower($0)}'` `lsb_release -cs` nginx-plus\n" >/etc/apt/sources.list.d/nginx-plus.list

  # Install NGINX Plus
  apt-get update
  apt-get install -o Dpkg::Options::="--force-confold" -y nginx-plus

  ${GENERATE_CONFIG_FILE} -p ${CONFIG_FILE} -t ${TEMPLATE_FILE_PLUS} > /etc/nginx/nginx.conf
else
  echo "Installing NGINX OSS"

  wget -q -O - http://nginx.org/keys/nginx_signing.key | apt-key add -
  printf "deb http://nginx.org/packages/`lsb_release -is | awk '{print tolower($0)}'`/ `lsb_release -cs` nginx\n" >/etc/apt/sources.list.d/nginx.list

  apt-get update
  apt-get install -o Dpkg::Options::="--force-confold" -y nginx

    ${GENERATE_CONFIG_FILE} -p ${CONFIG_FILE} -t ${TEMPLATE_FILE} > /etc/nginx/nginx.conf
fi
