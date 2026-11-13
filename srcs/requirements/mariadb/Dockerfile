# Define the base root filesystem using Debian Bookworm.
# This will provide the necessary environment with core system libraries and tools,
#   without its kernel.
# The container uses the kernel of the host's machine.
FROM debian:bookworm

# Refresh the package list
# Install MariaDB
#   "--no-install-recommends" skips the optional packages, keeping the image smaller.
# "mariadb-server" install both the server and the client program.
# Delete the package lists to keep the image smaller.
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends mariadb-server && \
    rm -rf /var/lib/apt/lists/*

# Copy custom configuration file into one of the folders that MariaDB reads on startup.
# Only files ending with ".cnf" are read.
# The name starts with "99" because the files are read in alphabetical order,
#   and the last value read wins.
# This way, the custom configuration is read after Debian's own "50-server.cnf",
#   so its bind-address (0.0.0.0) overrides the default 127.0.0.1. set there.
# Otherwise, only connections from inside the container would be accepted.
COPY conf/99-mariadb.cnf /etc/mysql/mariadb.conf.d/

# Copy the initialization script into the executables installed manually folder.
# In this script, the database is created as well as the user and password.
# All of these are created at runtime since they depend on the volume and
#   on secrets that do not exist during the build.
# This script will have its permissions changed in the next RUN.
COPY tools/mariadb_start.sh /usr/local/bin/

# Grant read and execute permissions to the script so Docker can run it.
# COPY keeps the permissions the file has on the host.
# By default, files created on the host are not executable.
RUN chmod 755 /usr/local/bin/mariadb_start.sh

# Run the script as the main process, PID 1.
# The exec form, which is a JSON array, does not start an intermediate shell,
#   so signals such as SIGTERM sent by "docker stop" reach the script directly.
ENTRYPOINT ["/usr/local/bin/mariadb_start.sh"]