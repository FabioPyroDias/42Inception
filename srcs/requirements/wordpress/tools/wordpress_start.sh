#!/bin/sh

# Exit immediately if any command fails.
set -e

# Sets paths to mounted secrets inside the container.
# They're declared in docker-compose.yaml and are mounted
#   as files in /run/secrets.
PATH_WORDPRESS_ADMIN_PASSWORD=/run/secrets/wp_admin_password
PATH_WORDPRESS_USER_PASSWORD=/run/secrets/wp_password
PATH_DATABASE_PASSWORD=/run/secrets/db_password

# This is a safeguard.
# If the secret in the path stored in PATH_WORDPRESS_ADMIN_PASSWORD
#   variable doesn't exist or is empty, stop the script.
# Without this secret, the WordPress administrator's password would be empty
if ! test -s "$PATH_WORDPRESS_ADMIN_PASSWORD"; then
    echo "File non-existing or empty at $PATH_WORDPRESS_ADMIN_PASSWORD"
    exit 1
fi

# This is a safeguard.
# If the secret in the path stored in PATH_WORDPRESS_USER_PASSWORD
#   variable doesn't exist or is empty, stop the script.
# Without this secret, the second WordPress user's password would be empty
if ! test -s "$PATH_WORDPRESS_USER_PASSWORD"; then
    echo "File non-existing or empty at $PATH_WORDPRESS_USER_PASSWORD"
    exit 1
fi

# This is a safeguard.
# If the secret in the path stored in PATH_DATABASE_PASSWORD
#   variable doesn't exist or is empty, stop the script.
# Without this secret, the connection between WordPress and the MariaDB
#   wouldn't be successful.
if ! test -s "$PATH_DATABASE_PASSWORD"; then
    echo "File non-existing or empty at $PATH_DATABASE_PASSWORD"
    exit 1
fi

# This is a safeguard.
# If MYSQL_HOST, WP_ADMIN_USER, WP_ADMIN_EMAIL, WP_USER,
#   WP_EMAIL or WP_TITLE, DOMAIN_NAME, MYSQL_DATABASE, MYSQL_USER
#   environment variable isn't set or just empty, stop the script.
: "${MYSQL_HOST:?MYSQL_HOST is not set}"
: "${WP_ADMIN_USER:?WP_ADMIN_USER is not set}"
: "${WP_ADMIN_EMAIL:?WP_ADMIN_EMAIL is not set}"
: "${WP_USER:?WP_USER is not set}"
: "${WP_EMAIL:?WP_EMAIL is not set}"
: "${WP_TITLE:?WP_TITLE is not set}"
: "${DOMAIN_NAME:?DOMAIN_NAME is not set}"
: "${MYSQL_DATABASE:?MYSQL_DATABASE is not set}"
: "${MYSQL_USER:?MYSQL_USER is not set}"

# Read the content of the secrets.
WORDPRESS_ADMIN_PASSWORD=$(cat "$PATH_WORDPRESS_ADMIN_PASSWORD")
WORDPRESS_USER_PASSWORD=$(cat "$PATH_WORDPRESS_USER_PASSWORD")
DATABASE_PASSWORD=$(cat "$PATH_DATABASE_PASSWORD")

# Maximum number of times the script pings MariaDB before
#   stopping it the script.
MAX_PING_ATTEMPTS=20

# Wait time between pings, in seconds.
INTERVAL_TIME=5

# Wait for MariaDB to answer the pings.
# The container may already be running while the database
#   is still starting and ins't accepting connections yet.
# If MariaDB never answer, the script stops with an error.
for attempt in $(seq 1 "$MAX_PING_ATTEMPTS"); do
    # The "--silent" option avoids printing errors when the
    #   connection isn't estabilished.
    # The ping only checks the server answer.
    if mariadb-admin ping -h "$MYSQL_HOST" --silent; then
        break
    fi

    # In case all the pings fail, simply print the reason for
    #   the stop of this script.
    if [ "$attempt" -eq "$MAX_PING_ATTEMPTS" ]; then
        echo "MariaDB did not answer after $MAX_PING_ATTEMPTS pings."
        exit 1
    fi

    # Pauses the script from running.
    # Without it, the pings would just keep on going one after another,
    #   not giving time for the server to start accepting connections.
    sleep "$INTERVAL_TIME"
done

# Files Volume
# Download and configure WordPress if "wp-config.php" doesn't exist.
# This file is used by WordPress to know how to connect to the database.
#   If it exists, Files Volume was already prepared.
# Without this, WordPress would be downloaded and configured at every restart.
if ! test -f /var/www/html/wp-config.php; then
    # "--alow-root" is needed in every wp command.

    # Downloads WordPress into the WORKDIR, /var/www/html. 
    wp core download --allow-root

    # Creates the "wp-config.php" with the data needed to connect to MariaDB.
    wp config create --allow-root \
        --dbname="$MYSQL_DATABASE" \
        --dbuser="$MYSQL_USER" \
        --dbpass="$DATABASE_PASSWORD" \
        --dbhost="$MYSQL_HOST"
fi

# Database Volume
# Install the site if WordPress isn't installed in the database yet.
# "wp core is-installed" checks the database, not the files.
# Just like the previous "if", if this check didn't exist, every restart would
#   try to install the site.
if ! wp core is-installed --allow-root; then
    # Creates the tables, sets the site data and creates the administrator.
    wp core install --allow-root \
        --url="https://$DOMAIN_NAME" \
        --title="$WP_TITLE" \
        --admin_user="$WP_ADMIN_USER" \
        --admin_password="$WORDPRESS_ADMIN_PASSWORD" \
        --admin_email="$WP_ADMIN_EMAIL" \
        --skip-email
fi

# To avoid printing errors or unecessary information in the terminal,
#   the result of this search is stored in a variable.
# If the variable length is zero, then the second user doesn't exist.
USER_EXISTS=$(wp user list --user_login="$WP_USER" --field=ID --allow-root)

# Create the second user only if they don't exist yet.
if [ -z "$USER_EXISTS" ]; then
    wp user create "$WP_USER" "$WP_EMAIL" \
        --user_pass="$WORDPRESS_USER_PASSWORD" --allow-root
fi

# The script runs as root, but PHP-FPM runs as www-data.
# Files created by "wp-client" belong to root. Without this, PHP-FPM
#   wouldn't be able to write in these files.
# By running this on every start, this also repairs wrong ownership.
chown -R www-data:www-data /var/www/html

# Start PHP-FPM as PID 1 and keep it in the foreground.
# This way, Docker can properly manage the container.
exec php-fpm8.2 -F