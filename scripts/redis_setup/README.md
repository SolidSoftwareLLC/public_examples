## Steps
1. Update the redis config with the appropriate maxmemory for the database
  ```bash
  ...
  ################################### CLIENTS ####################################
  maxmemory 4GB
  ...
  ```

2. Update the setup script with the bucket name for your redis backups
  ```bash
  ...
  cat > /usr/local/bin/redis_backup << EOF
  #!/usr/bin/env bash
  bucket_name=FILL_ME_IN
  ...
  ```

3. SCP the script onto your instance
  ```bash
  $ scp -i ~/.ssh/your-key-name.pem ubuntu@instance-ip-address:~/
  ```

4. SSH onto the instance and run it
  ```bash
  $ ssh ~/.ssh/your-key-name.pem ubuntu@instance-ip-address
  $ sudo ./setup.sh
  ```
