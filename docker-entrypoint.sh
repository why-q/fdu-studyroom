#!/bin/bash
set -e

# Create mysql user and group if they do not exist
if ! getent group mysql >/dev/null; then
    groupadd -r mysql
fi

if ! getent passwd mysql >/dev/null; then
    useradd -r -g mysql mysql
fi

chown -R mysql:mysql /var/lib/mysql /var/run/mysqld
chmod 755 /var/run/mysqld
chsh -s /bin/bash mysql

# Init MySQL
if [ ! -d "/var/lib/mysql/mysql" ]; then
    gosu mysql mysqld --initialize-insecure
fi

# Run MySQL
gosu mysql mysqld --bind-address=127.0.0.1 --port=3306 "$@" &

# Wait for MySQL to be ready
for i in {30..0}; do
    if mysqladmin ping -h "127.0.0.1" --silent; then
        break
    fi
    echo 'Waiting for MySQL to be ready...'
    sleep 1
done

if [ "$i" = 0 ]; then
    echo >&2 'MySQL start process failed.'
    exit 1
fi

mysql=(mysql --protocol=socket -uroot)

# Set root user password and grant privileges
echo ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'ye0401'; | "${mysql[@]}"
echo "GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;" | "${mysql[@]}"
echo "FLUSH PRIVILEGES;" | "${mysql[@]}"

# Check if the database exists, create it if not
if ! echo 'SHOW DATABASES;' | mysql -uroot -pye0401 | grep -q 'reservation_demo'; then
    echo "Creating database reservation_demo..."
    echo "CREATE DATABASE reservation_demo;" | mysql -uroot -pye0401
fi

# import .sql file
if [ -f /docker-entrypoint-initdb.d/reservation_demo.sql ]; then
    echo "Importing database from /docker-entrypoint-initdb.d/reservation_demo.sql"
    mysql -uroot -pye0401 reservation_demo </docker-entrypoint-initdb.d/reservation_demo.sql
fi

# Start the Spring Boot application
echo 'Starting Spring Boot application...'
exec java -jar /app/target/reserve_demo-0.0.1-SNAPSHOT.jar
