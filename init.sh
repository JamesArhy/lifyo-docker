#!/bin/bash

set -e

printf "===== Life is Feudal: Your Own Server %s =====\\nhttps://github.com/JamesArhy/lifyo-docker\\n\\n" "$VERSION"

CURRENTUID=$(id -u)
HOME="/home/steam"
MSGERROR="\033[0;31mERROR:\033[0m"
MSGWARNING="\033[0;33mWARNING:\033[0m"
NUMCHECK='^[0-9]+$'
RAMAVAILABLE=$(awk '/MemAvailable/ {printf( "%d\n", $2 / 1024000 )}' /proc/meminfo)
USER="steam"

if ! [[ "$PGID" =~ $NUMCHECK ]] ; then
    printf "${MSGWARNING} Invalid group id given: %s\\n" "$PGID"
    PGID="1000"
elif [[ "$PGID" -eq 0 ]]; then
    printf "${MSGERROR} PGID/group cannot be 0 (root)\\n"
    exit 1
fi

if ! [[ "$PUID" =~ $NUMCHECK ]] ; then
    printf "${MSGWARNING} Invalid user id given: %s\\n" "$PUID"
    PUID="1000"
elif [[ "$PUID" -eq 0 ]]; then
    printf "${MSGERROR} PUID/user cannot be 0 (root)\\n"
    exit 1
fi

if [[ ! -w "/data" ]]; then
    echo "The current user does not have write permissions for /data"
    exit 1
fi

mkdir -p \
    /data/mariadb \
    /data/gamefiles \
    /home/steam/.steam/root \
    /home/steam/.steam/steam \
    || exit 1

#!/bin/bash

# Initialize variables
DB_DIR="/var/lib/mysql"
DB_USER="lif"
DB_PASSWORD="yourpassword"  # Change this to a secure password
DB_NAME="life_is_feudal"

# Check if MariaDB has been initialized
if [ ! -d "$DB_DIR/mysql" ]; then
    echo "MariaDB data directory not found, initializing database..."

    # Start MariaDB service
    service mysql start

    # Secure the installation (you can automate this as needed)
    mysql -u root -e "UPDATE mysql.user SET Password = PASSWORD('$DB_PASSWORD') WHERE User = 'root';"
    mysql -u root -e "DELETE FROM mysql.user WHERE User='';"
    mysql -u root -e "DROP DATABASE IF EXISTS test;"
    mysql -u root -e "FLUSH PRIVILEGES;"

    # Create database and user for the game server
    mysql -u root -p"$DB_PASSWORD" -e "CREATE DATABASE $DB_NAME;"
    mysql -u root -p"$DB_PASSWORD" -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
    mysql -u root -p"$DB_PASSWORD" -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
    mysql -u root -p"$DB_PASSWORD" -e "FLUSH PRIVILEGES;"

    echo "MariaDB initialized and user $DB_USER created."
else
    echo "MariaDB already initialized, skipping setup."
fi

# Start the game server by calling run.sh
exec /home/steam/run.sh