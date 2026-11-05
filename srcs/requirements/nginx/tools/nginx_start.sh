#!/bin/sh

# Exit immediately if any commands fails.
set -e

# This is a safeguard.
# If DOMAIN_NAME variable isn't defined, stop the script.
# Without DOMAIN_NAME, the "certificate" and the "server_name" would be empty
: "${DOMAIN_NAME:?DOMAIN_NAME is not set}"

# Generate a TLS certificate using openssl if it doesn't exist already
# openssl req creates or requests certificates.
#   -x509 generates a new self-signed certificate.
#   -nodes creates the private key without password. If the key had a password,
#       "openssl" would ask for the password and the container wouldn't provide it.
#       The script would stop.
#   -newkey sets the key type
#   -days estabilishes how many days the key is valid.
#   -keyout sets where the private key is stored
#   -out sets where to store the certificate
#   -subj estabilishes the certificate name with just "CN", which means "Common Name".
#       Without this flag, "openssl" would ask for more specifications like country, city,
#       and so on.
#       Like the "nodes", the container wouldn't answer and the script would stop.
if [ ! -f /etc/nginx/ssl/inception.crt ]; then
    openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
    -keyout /etc/nginx/ssl/inception.key -out /etc/nginx/ssl/inception.crt \
    -subj "/CN=${DOMAIN_NAME}"
fi

# Substitutes the DOMAIN_NAME variable found in Environment Variables
#   in the nginx.conf template to genereate the final configuration file
envsubst '${DOMAIN_NAME}' < /etc/nginx/templates/default.conf.template > /etc/nginx/conf.d/default.conf

# Start NGINX as PID 1 and keep it in the foreground.
# This way, Docker can properly manage the container
exec nginx -g 'daemon off;'