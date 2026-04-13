#!/bin/bash
set -e

echo "=== STARTUP ==="
echo "RAILS_ENV: $RAILS_ENV"
echo "DATABASE_URL: ${DATABASE_URL:0:40}..."
echo "PORT: ${PORT:-3000}"

echo ""
echo "==> Waiting for database..."
until pg_isready -d "$DATABASE_URL" -t 5; do
  echo "DB not ready, retrying in 2s..."
  sleep 2
done
echo "DB is ready."

echo ""
echo "==> Running migrations..."
bundle exec rails db:migrate

echo ""
echo "==> Running seeds..."
bundle exec rails db:seed

echo ""
echo "==> Starting Puma on port ${PORT:-3000}..."
exec bundle exec puma -C config/puma.rb
