# Load environment variables from root .env file
if [ -f ../../.env ]; then
    export $(cat ../../.env | grep -v '^#' | xargs)
    env | grep 'CLICKHOUSE_'
fi

docker compose down -v
docker compose up -d
