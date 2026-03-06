#!/bin/bash
set -e

echo "Starting init script..."

# Ensure correct permissions for mysql directory (in case volume is mounted)
# We need to be root to change ownership, but we are running as root in the container by default?
# The Dockerfile creates a user 'lifuser' but doesn't switch to it with USER instruction until potentially later or never?
# Looking at Dockerfile: "RUN useradd -m lifuser" then "WORKDIR /home/lifuser/yoserver".
# It does NOT have a "USER lifuser" instruction, so we are running as root.

# Fix permissions for MariaDB if it's a mounted volume
chown -R mysql:mysql /var/lib/mysql

echo "Initializing MariaDB..."
# Start MariaDB
service mysql start

# Wait for MariaDB to be fully operational
until mysqladmin ping --silent; do
    echo "Waiting for MariaDB to start..."
    sleep 1
done
echo "MariaDB started."

# Use environment variables for database credentials
DB_USER=${DB_USER:-lif_1}
DB_PASS=${DB_PASS:-supersafepassword}

# Check if the database already exists
if mysql -u root -e "USE $DB_USER" 2>/dev/null; then
    echo "Database '$DB_USER' already exists. Skipping initialization."
else
    echo "Database '$DB_USER' not found. Configuring MariaDB for Life is Feudal..."
    
    # Create database and user
    mysql -u root -e "CREATE DATABASE IF NOT EXISTS $DB_USER; \
        CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_PASS'; \
        GRANT ALL PRIVILEGES ON $DB_USER.* TO '$DB_USER'@'%'; \
        FLUSH PRIVILEGES;"
    echo "Database configured with user $DB_USER and database $DB_USER."

    echo "Applying Life is Feudal customizations to mysql..."
    # MariaDB configuration
    cat > /etc/mysql/mariadb.conf.d/90-lifeisfeudal.cnf <<EOF
[mysqld]
innodb_file_per_table=ON
innodb_file_format=Barracuda
innodb_flush_log_at_trx_commit=1
max_sp_recursion_depth=255
max_allowed_packet=10M
query_cache_size=0
query_cache_type=OFF
EOF
    
    # Restart to apply config changes
    service mysql restart
    
    # Wait again after restart
    until mysqladmin ping --silent; do
        echo "Waiting for MariaDB to restart..."
        sleep 1
    done
    echo "MariaDB configuration updated."
fi

# Create the config file and substitute the variables
# We do this every time to ensure env vars are respected if they change
echo "Initializating and populating local_config.cs file with DB_USER and DB_PASS environment variables..."
cat > /home/lifuser/yoserver/config_local.cs <<EOF
\$cm_config::DB::Connect::server = "localhost";
\$cm_config::DB::Connect::user = "${DB_USER}";
\$cm_config::DB::Connect::password = "${DB_PASS}";
EOF

# Fix permissions for the server directory so lifuser can access it
chown -R lifuser:lifuser /home/lifuser

# Switch to lifuser for running the server
echo "Initialization complete. Handing over to run.sh..."
# We use gosu or runuser to drop privileges if we are root, or just run it if we want to run as root (but usually bad practice).
# The Dockerfile didn't install gosu. Let's check if we can just su.
su lifuser -c "./run.sh"