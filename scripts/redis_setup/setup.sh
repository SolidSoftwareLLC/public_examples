#!/usr/bin/env bash
set -e

# Redis configuration
# Based on https://www.digitalocean.com/community/tutorials/how-to-install-and-configure-redis-on-ubuntu-16-04
# with some additional setup for s3 backups and server adjustments

apt update && apt upgrade -y
apt install -y \
        awscli \
        htop

# Install Redis v4.0.11
apt install -y \
    build-essential \
    tcl

pushd /tmp
wget http://download.redis.io/releases/redis-4.0.11.tar.gz
tar xzf redis-4.0.11.tar.gz
pushd redis-4.0.11/
make
make install
popd
popd

# Configure Redis
adduser --system --group --no-create-home redis
mkdir /var/lib/redis
chown redis:redis /var/lib/redis
chmod 770 /var/lib/redis

# Use base configuration with some modifications. Stripped commented lines for brevity with:
# $ cat redis.conf | sed -e '/^# .*$/d' -e '/^#$/d' | sed -e '/^ *$/d'
# The unstripped file has great information in it: https://github.com/antirez/redis/blob/4.0.11/redis.conf
mkdir /etc/redis
cat > /etc/redis/redis.conf << EOF
################################## INCLUDES ###################################
################################## MODULES #####################################
################################## NETWORK #####################################
bind 0.0.0.0
protected-mode yes
port 6379
tcp-backlog 511
timeout 0
tcp-keepalive 300
################################# GENERAL #####################################
daemonize no
supervised systemd
pidfile /var/run/redis_6379.pid
loglevel notice
logfile ""
databases 16
always-show-logo yes
################################ SNAPSHOTTING  ################################
save 450 1
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir /var/lib/redis
################################# REPLICATION #################################
slave-serve-stale-data yes
slave-read-only yes
repl-diskless-sync no
repl-diskless-sync-delay 5
repl-disable-tcp-nodelay no
slave-priority 100
################################## SECURITY ###################################
################################### CLIENTS ####################################
maxclients 100000
############################## MEMORY MANAGEMENT ################################
maxmemory 4GB
############################# LAZY FREEING ####################################
lazyfree-lazy-eviction no
lazyfree-lazy-expire no
lazyfree-lazy-server-del no
slave-lazy-flush no
############################## APPEND ONLY MODE ###############################
appendonly no
appendfilename "appendonly.aof"
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
aof-load-truncated yes
aof-use-rdb-preamble no
################################ LUA SCRIPTING  ###############################
lua-time-limit 5000
################################ REDIS CLUSTER  ###############################
########################## CLUSTER DOCKER/NAT support  ########################
################################## SLOW LOG ###################################
slowlog-log-slower-than 10000
slowlog-max-len 128
################################ LATENCY MONITOR ##############################
latency-monitor-threshold 0
############################# EVENT NOTIFICATION ##############################
notify-keyspace-events ""
############################### ADVANCED CONFIG ###############################
hash-max-ziplist-entries 512
hash-max-ziplist-value 64
list-max-ziplist-size -2
list-compress-depth 0
set-max-intset-entries 512
zset-max-ziplist-entries 128
zset-max-ziplist-value 64
hll-sparse-max-bytes 3000
activerehashing yes
client-output-buffer-limit normal 0 0 0
client-output-buffer-limit slave 256mb 64mb 60
client-output-buffer-limit pubsub 32mb 8mb 60
hz 10
aof-rewrite-incremental-fsync yes
########################### ACTIVE DEFRAGMENTATION #######################
EOF

# Adjust the server for redis
sysctl -w net.core.somaxconn=65535
sysctl vm.overcommit_memory=1
echo 'vm.overcommit_memory=1' >> /etc/sysctl.conf
echo never > /sys/kernel/mm/transparent_hugepage/enabled

cat > /etc/rc.local << EOF
#!/bin/sh -e
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will "exit 0" on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.

sysctl -w net.core.somaxconn=65535
echo never > /sys/kernel/mm/transparent_hugepage/enabled
exit 0
EOF

# Setup systemd
cat > /etc/systemd/system/redis.service << EOF
[Unit]
Description=Redis In-Memory Data Store
After=network.target

[Service]
User=redis
Group=redis
LimitNOFILE=100000
ExecStart=/usr/local/bin/redis-server /etc/redis/redis.conf
ExecStop=/usr/local/bin/redis-cli shutdown
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl start redis
systemctl enable redis

# Setup tooling for backup
cat > /usr/local/bin/redis_backup << EOF
#!/usr/bin/env bash
bucket_name=FILL_ME_IN
dt=\$(date "+%Y%m%d-%H:%M")
aws s3 cp /var/lib/redis/dump.rdb s3://\${bucket_name}/redis-backups/\${dt}-dump.rdb
EOF
chmod +x /usr/local/bin/redis_backup

cat > cronconfig << EOF
PATH=/home/ubuntu/bin:/home/ubuntu/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin
# Upload your backup on a schedule
0 * * * * /usr/local/bin/redis_backup > /dev/null
EOF
crontab cronconfig
rm cronconfig
