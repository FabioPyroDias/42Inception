# Define the base root filesystem using Debian Bookworm.
# This will provide the necessary environment with core system libraries and tools,
#   without its kernel.
# The container uses the kernel of the host's machine.
FROM debian:bookworm

# Refresh the package list
# Install PHP8.2-FPM, PHP8.2-MySQL, MariaDB-Client and Curl
#   "--no-install-recommends" skips the optional packages, keeping the image smaller.
# "php8.2-fpm" is needed to execute the .php files with the FastCGI Process Manager.
# "php8.2-mysql" allows PHP to communicate with MariaDB
# "mariadb-client" is needed to ping the database server and check that it already answers.
# Curl downloads files over HTTPS.
#   It will be used to fetch WordPress and WordPress Command Line Interface, wp-cli.
# Curl is installed without "--no-install-recommends" because the CA certificates
#   it needs to verify HTTPS sites are only installed as a recommended package.
# Delete the package lists to keep the image smaller.
RUN apt-get update && \
    apt-get install -y --no-install-recommends php8.2-fpm php8.2-mysql mariadb-client && \
    apt-get install -y curl && \
    rm -rf /var/lib/apt/lists/*

# Download "wp-cli", WordPress Command Line Interface tool as an executable file.
# -f makes Curl exit with an error on HTTP error, instead of saving the error page as the file.
# -L follows HTTP redirects to new locations.
# -o writes the downloaded output to a custom local file "/usr/local/bin/wp"
RUN curl -fL -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar

# Grants read and execute permissions to the executable.
# Without them, the downloaded file is just data.
RUN chmod 755 /usr/local/bin/wp

# By default, the Debian package makes PHP-FPM listen to communications via a file.
#   In the Docker context, this is inside the container.
# NGINX runs on a different container, so it cannot reach that file if it's not shared.
# The idea is for the PHP-FPM to listen to a TCP port, specifically 9000,
#   so NGINX can reach it through the Docker network.
RUN sed -i 's/listen = \/run\/php\/php8.2-fpm.sock/listen = 9000/' /etc/php/8.2/fpm/pool.d/www.conf

# Copy the initialization script into the executables installed manually folder.
# In this script, WordPress is installed and its two users are created.
# All of this is done at runtime, since it depends on the database and on secrets that
#   are only available when the container starts.
COPY tools/wordpress_start.sh /usr/local/bin/

# Grant read and execute permissions to the script so Docker can it can be executed.
# COPY keeps the permissions the file has on the host.
# By default, files created on the host are not executable.
RUN chmod 755 /usr/local/bin/wordpress_start.sh

# Set /var/www/html as the working directory, creating it if needed.
# This is where the WordPress files will live, so commands such as wp-cli,
#   act on this directory by default.
WORKDIR /var/www/html

# Run the script as the main process, PID 1.
# The exec form, which is a JSON array, does not start an intermediate shell,
#   so signals such as SIGTERM sent by "docker stop" reach the script directly.
ENTRYPOINT ["/usr/local/bin/wordpress_start.sh"]