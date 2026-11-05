# Define the base root filesystem using Debian Bookworm.
# This will provide the necessary environment with core system libraries and tools,
#   without its kernel.
# The container uses the kernel of the host's machine.
FROM debian:bookworm

# Refresh the package list
# Install NGINX, OpenSSL and gettext-base
#   "--no-install-recommends" skips the optional packages, keeping the image smaller.
# By default, NGINX embeds SSL library to handle TLS, but not the "openssl" tool.
# "openssl" is needed to generate the cryptographic keys and certificates required for HTTPS.
# gettext-base provides "envsubst", which substitutes environment variables in templates.
# Delete the package lists to keep the image smaller.
# Remove the default NGINX configuration file. This will solve conflicts between configurations.
#   Specifically, the default config listens on port 80, the subject requires ONLY port 443.
# Create the directory to store SSL/TLS certificates and private keys for HTTPS
RUN apt-get update && \
    apt-get install -y --no-install-recommends nginx openssl gettext-base && \
    rm -rf /var/lib/apt/lists/* && \
    rm -f /etc/nginx/sites-enabled/default && \
    mkdir -p /etc/nginx/ssl

# Copy custom configuration file as a template.
# Since this file contains "$DOMAIN_NAME", NGINX cannot expand that by itself.
# At the container startup, the script runs "envsubst" on this template and
#   writes the final file to /etc/nginx/conf.d/default.conf
# The value of "$DOMAIN_NAME" is only known at runtime and comes from the .env file.
# This substitution cannot be done during the build.
# For the original file to not be overwritten, the template needs to be kept separately.
COPY conf/nginx.conf /etc/nginx/templates/default.conf.template

# Copy the initialization script that will generate SSL certificates into the 
#   executables installed manually folder.
# This script will have its permissions changed in the next RUN.
# The script generates the SSL certificate dynamically at runtime.
COPY tools/nginx_start.sh /usr/local/bin/

# Grant read and execute permissions to the script so Docker can run it
# COPY keeps the permissions the file has on the host.
# By default, files created on the host are not executable.
RUN chmod 755 /usr/local/bin/nginx_start.sh

# Run the script as the main process, PID 1.
# The exec form, which is a JSON array, does not start an intermediate shell,
#   so signals such as SIGTERM sent by "docker stop" reach the script directly.
ENTRYPOINT ["/usr/local/bin/nginx_start.sh"]