FROM ruby:3.3
WORKDIR /app
RUN apt-get update -qq && apt-get install -y build-essential libpq-dev postgresql-client
COPY Gemfile Gemfile.lock* ./
RUN bundle install
COPY . .
RUN chmod +x docker/entrypoint.sh
CMD ["./docker/entrypoint.sh"]
