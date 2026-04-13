#!/bin/bash
set -e

echo "==> Running migrations..."
bundle exec rails db:migrate

echo "==> Running seeds..."
bundle exec rails db:seed

echo "==> Starting Puma..."
exec bundle exec puma -C config/puma.rb
