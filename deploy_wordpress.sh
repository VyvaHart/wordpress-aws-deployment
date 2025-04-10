#!/bin/bash
set -e # Exit script if any command fails

# Required Environment Variables (export before execution)
# export DB_NAME="db_name"
# export DB_USER="db_username"
# export DB_PASSWORD="db_password"
# export DB_HOST="rds_endpoint" # RDS endpoint from Terraform (terraform output)
# export WP_ADMIN_USER="wp_admin_user"
# export WP_ADMIN_PASSWORD="wp_admin_password"
# export WP_ADMIN_EMAIL="wp_admin_email"
# export WP_URL="http://alb_dns_name" # ALB DNS name from Terraform (terraform output)
# export REDIS_HOST="redis_endpoint" # Redis endpoint from Terraform (terraform output)
# export REDIS_PORT="redis_port"     # Redis port from Terraform (terraform output)


echo "--- Starting WordPress Deployment ---"

# env variables check
if [[ -z "$DB_NAME" || -z "$DB_USER" || -z "$DB_PASSWORD" || -z "$DB_HOST" || -z "$WP_ADMIN_USER" || -z "$WP_ADMIN_PASSWORD" || -z "$WP_ADMIN_EMAIL" || -z "$WP_URL" || -z "$REDIS_HOST" || -z "$REDIS_PORT" ]]; then
  echo "Error: Missing required environment variables."
  echo "Check the list at the top of the script."
  exit 1
fi


WP_PATH="/var/www/html" # Install location
APACHE_USER="apache"    # Web server user


echo "--- Downloading WordPress ---"
# Check if WP-CLI command exists (should be installed by user_data in main.tf)
if ! [ -x "/usr/local/bin/wp" ]; then
    echo "Error: WP-CLI command not found."
    exit 1
fi

cd /var/www # Move to parent dir for download command

# Only download if the target directory is empty
if [ -z "$(ls -A $WP_PATH)" ]; then
   # Use WP-CLI to download WordPress
   sudo -u $APACHE_USER /usr/local/bin/wp core download --path=$WP_PATH --allow-root
   echo "WordPress downloaded."
else
   echo "WordPress directory ($WP_PATH) exists, skipping download."
fi

cd $WP_PATH # Go into the WordPress directory


echo "--- Configuring wp-config.php ---"
# Using WP-CLI to generate wp-config.php with DB details from env vars
sudo -u $APACHE_USER /usr/local/bin/wp config create \
  --path=$WP_PATH \
  --dbname="$DB_NAME" \
  --dbuser="$DB_USER" \
  --dbpass="$DB_PASSWORD" \
  --dbhost="$DB_HOST" \
  --dbprefix="wp_" \
  --allow-root


echo "--- Adding Redis configuration to wp-config.php ---"
# Using 'sed' to add multiple lines
sudo sed -i "/\/\* That's all, stop editing! Happy publishing. \*\//i \
define('WP_REDIS_HOST', '$REDIS_HOST');\n\
define('WP_REDIS_PORT', $REDIS_PORT);\n\
define('WP_REDIS_TIMEOUT', 1);\n\
define('WP_REDIS_READ_TIMEOUT', 1);\n\
define('WP_REDIS_DATABASE', 0);\n\
define('WP_CACHE_KEY_SALT', 'change_this_to_a_unique_phrase_$(date +%s)'); # Add unique salt based on time\n\
define('WP_CACHE', true);\n
" wp-config.php
# Added a timestamp to WP_CACHE_KEY_SALT to make it unique during each run

echo "--- Installing WordPress ---"
# Run the main WordPress install using WP-CLI
sudo -u $APACHE_USER /usr/local/bin/wp core install \
  --path=$WP_PATH \
  --url="$WP_URL" \
  --title="My WordPress Site (DevOps Assignment)" \
  --admin_user="$WP_ADMIN_USER" \
  --admin_password="$WP_ADMIN_PASSWORD" \
  --admin_email="$WP_ADMIN_EMAIL" \
  --skip-email \
  --allow-root


echo "--- Installing and Activating Redis Plugin ---"
sudo -u $APACHE_USER /usr/local/bin/wp plugin install redis-cache --activate --allow-root
# Enable Redis object cache (copies object-cache.php to wp-content)
sudo -u $APACHE_USER /usr/local/bin/wp redis enable --allow-root


echo "--- Setting Permissions ---"
sudo chown -R $APACHE_USER:$APACHE_USER $WP_PATH
sudo find $WP_PATH -type d -exec chmod 755 {} \;
sudo find $WP_PATH -type f -exec chmod 644 {} \;
# for wp-content (uploads, themes, plugins)
sudo find $WP_PATH/wp-content -type d -exec chmod 775 {} \;
sudo find $WP_PATH/wp-content -type f -exec chmod 664 {} \;
# read-only for owner
sudo chmod 600 $WP_PATH/wp-config.php

echo "--- WordPress Deployment Complete ---"
echo "Access URL: $WP_URL"
echo "Admin User: $WP_ADMIN_USER"
