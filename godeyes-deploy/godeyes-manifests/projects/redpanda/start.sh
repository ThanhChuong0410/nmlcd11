# Load environment variables from root .env file
if [ -f ../../.env ]; then
    export $(cat ../../.env | grep -v '^#' | xargs)
    env | grep "REDPANDA_"
fi

export REDPANDA_VERSION=v25.2.10
export REDPANDA_CONSOLE_VERSION=v3.2.2
docker compose down -v
docker compose up -d
