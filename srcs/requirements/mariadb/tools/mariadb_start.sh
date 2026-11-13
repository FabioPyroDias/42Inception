#!/bin/sh

# Exit immediately if any commands fails.
set -e

# Sets paths to mounted secrets inside the container.
# They're declared in docker-compose.yaml and are mounted
#   as files in /run/secrets.
PATH_DATABASE_ROOT_PASSWORD=/run/secrets/db_root_password
PATH_DATABASE_PASSWORD=/run/secrets/db_password

# This is a safeguard.
# If the secret in the path stored in PATH_DATABASE_ROOT_PASSWORD
#   variable doesn't exist or is empty, stop the script.
# Without this secret, the root password would be empty
if ! test -s "$PATH_DATABASE_ROOT_PASSWORD"; then
    echo "File non-existing or empty at $PATH_DATABASE_ROOT_PASSWORD"
    exit 1
fi

# This is a safeguard.
# If the secret in the path stored in PATH_DATABASE_PASSWORD
#   variable doesn't exist or is empty, stop the script.
# Without this secret, the password of the WordPress database
#   would be empty
if ! test -s "$PATH_DATABASE_PASSWORD"; then
    echo "File non-existing or empty at $PATH_DATABASE_PASSWORD"
    exit 1
fi

# This is a safeguard.
# If MYSQL_DATABASE or MYSQL_USER environment variable isn't set or
#   just empty, stop the script.
: "${MYSQL_DATABASE:?MYSQL_DATABASE is not set}"
: "${MYSQL_USER:?MYSQL_USER is not set}"

# Read the content of the secrets.
DATABASE_ROOT_PASSWORD=$(cat "$PATH_DATABASE_ROOT_PASSWORD")
DATABASE_PASSWORD=$(cat "$PATH_DATABASE_PASSWORD")


# The server stores its socket in /run/mysqld
# In case this directory already exists, "-p" avoids the error.
mkdir -p /run/mysqld

# Changes the owner of the socket directory, as well as the
#   data directory, to mysql.
# The script runs as root, but the server runs as "mysql", which
#   has very few permissions. So the server can only write in
#   directories owned by "mysql"
# Since the volume comes from the host machine, the directories might
#   belong to a diferent user.
chown mysql:mysql /run/mysqld /var/lib/mysql

# This only runs on the first start. Creates the MariaDB tables.
# On an empty volume, this has to be done here since the volume is mounted
#   in /var/lib/mysql when the container starts and hides what the image
#   had in this directory.
# Without a volume, the Debian package has already initialized this directory
#   during the build, and "mariadb-install-db" only reports that the tables exist.
# ".init_done"'s purpose is to signal the successful installation of
#   "mariadb-install-db".
# If it fails, it leaves no marker. With this file, acting as an
#   installation flag, the next time the program runs, it will try to install
#   it again.
# Running "mariadb-install-db" on an already initialized data directory
#   is harmless. There's no overwrites.
if ! test -f /var/lib/mysql/.init_done; then
    mariadb-install-db --user=mysql
    touch /var/lib/mysql/.init_done
fi

# Apply the configuration.
# This runs on every start. This allows the secret file to be changed
#   and updating the container by simply restarting instead of deleting
#   the volume.

# "--bootstrap" is a special mode where the server reads SQL from its
#   standard input, executes it and exits without staying running.
# This avoids starting a temporary server and waiting for it to be ready.
# It also starts the server as if "--skip-gran-tables" had been given.
#   This is why the first "FLUSH PRIVILEGES" below is needed.
# "--user=mysql" specifies the server is not run as root.
# "<< EOF" sends the lines below to the standard input of the command
#   until a new "EOF" is found.

# "FLUSH PRIVILEGES" reloads the grant tables.
# This one is needed because "--bootstrap" starts the server without the
#   gran tables loaded, so acount statements like "ALTER USER" are
#   refused.
# "DROP USER IF EXISTS ''@'localhost'" removes the anonymous account,
#   an account that possesses an empty user name, that
#   "mariadb-install-db" creates to facilitate tests.
# MariaDB prioritizes accounts with the most specific host first. Only
#   then by name. An empty user name matches any user.
# Since "localhost" is more specific" than "%", which means "any address",
#   any local login match "localhost" first because of its host.
# This would result in an Access Denied error. MariaDB would try to login
#   as the anonymous user, which does not have a password, and the passwords
#   wouldn't match. This way, an error is avoided and the script keeps running.
# "ALTER USER" 'root'@'localhost' gives the root account a password.
# After the installation, root has no password and can only log in from inside
#   the container.
# "CREATE DATABASE" creates the database used by WordPress. 
# "CREATE USER" creates the account used by WordPress. Since the WordPress connects
#   from another container, the address can change. So, to deal with this scenario,
#   we specify "%" which means from any host.
# "ALTER USER" sets the password of that account to the current secret.
#   Its needed because "CREATE USER IF NOT EXISTS" does nothing when account
#   already exists, so changing the secret would not be applied.
# "GRANT ALL PRIVILEGES" gives that account all privileges ONLY on the specific
#   WordPress database. It can't manage other databases or accounts.
# "DELETE FROM mysql.global_priv" eliminates all anonymouse accounts.
# "DROP DATABASE IF EXISTS test" deletes the database called "test".
# By default, MariaDB creates this database for testing. Since almost every user
#   can access it, this can be considered a lack of security.
# "DELETE FROM mysql.db" deletes the permissions table with every rule
#   associated with the database "test". "DROP DATABASE test" deletes
#   all the files in the database, but leaves old permissions registered in
#   the system table.
# "FLUSH PRIVILEGES" is needed because the "DELETE" statements changed the grant
#   tables directly. "CREATE USER", "ALTER USER", "GRANT" and "DROP USER" take
#   effect immediatly and do not need it.
mariadbd --user=mysql --bootstrap << EOF
FLUSH PRIVILEGES;
DROP USER IF EXISTS ''@'localhost';
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DATABASE_ROOT_PASSWORD}';
CREATE DATABASE IF NOT EXISTS ${MYSQL_DATABASE};
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${DATABASE_PASSWORD}';
ALTER USER '${MYSQL_USER}'@'%' IDENTIFIED BY '${DATABASE_PASSWORD}';
GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${MYSQL_USER}'@'%';
DELETE FROM mysql.global_priv WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db LIKE 'test%';
FLUSH PRIVILEGES;
EOF

# Start MariaDB as PID 1 and keep it in the foreground.
# This way, Docker can properly manage the container
exec mariadbd --user=mysql