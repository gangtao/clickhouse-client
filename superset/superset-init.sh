#!/bin/bash

set -eo pipefail

export FLASK_APP=superset

# check to see if the superset config already exists, if it does skip to
# running the user supplied docker-entrypoint.sh, note that this means
# that users can copy over a prewritten superset config and that will be used
# without being modified
echo "Checking for existing Superset config..."
if [ ! -f $SUPERSET_HOME/superset_config.py ]; then
  echo "No Superset config found, creating from environment"
  touch $SUPERSET_HOME/superset_config.py

  cat > $SUPERSET_HOME/superset_config.py <<EOF
ROW_LIMIT = ${SUP_ROW_LIMIT}
WEBSERVER_THREADS = ${SUP_WEBSERVER_THREADS}
SUPERSET_WEBSERVER_PORT = ${SUP_WEBSERVER_PORT}
SUPERSET_WEBSERVER_TIMEOUT = ${SUP_WEBSERVER_TIMEOUT}
SECRET_KEY = '${SUP_SECRET_KEY}'
SQLALCHEMY_DATABASE_URI = '${SUP_META_DB_URI}'
WTF_CSRF_ENABLED = ${SUP_CSRF_ENABLED}
WTF_CSRF_EXEMPT_LIST = ${SUP_CSRF_EXEMPT_LIST}
MAPBOX_API_KEY = '${SUP_MAPBOX_API_KEY}'
EOF
fi

# check for existence of /docker-entrypoint.sh & run it if it does
echo "Checking for docker-entrypoint"
if [ -f /docker-entrypoint.sh ]; then
  echo "docker-entrypoint found, running"
  chmod +x /docker-entrypoint.sh
  . docker-entrypoint.sh
fi

# set up Superset if we haven't already
if [ ! -f $SUPERSET_HOME/.setup-complete ]; then
  echo "Running first time setup for Superset"

  echo "Creating admin user ${ADMIN_USERNAME}"
  /usr/local/bin/flask fab create-admin \
    --username $ADMIN_USERNAME \
    --firstname $ADMIN_FIRST_NAME \
    --lastname $ADMIN_LAST_NAME \
    --email $ADMIN_EMAIL \
    --password $ADMIN_PWD

  echo "Initializing database"
  superset db upgrade

  echo "Creating default roles and permissions"
  superset init

  touch $SUPERSET_HOME/.setup-complete
else
  # always upgrade the database, running any pending migrations
  superset db upgrade
fi

echo "Starting up Superset gunicorn server"
gunicorn \
      -w ${SUP_WEBSERVER_WORKERS} \
      -k gevent \
      --timeout ${SUP_WEBSERVER_TIMEOUT} \
      -b  0.0.0.0:${SUP_WEBSERVER_PORT} \
      "superset.app:create_app()"