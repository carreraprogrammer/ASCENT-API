FROM ruby:3.3
WORKDIR /app
RUN apt-get update -qq && apt-get install -y build-essential libpq-dev postgresql-client
COPY Gemfile Gemfile.lock* ./
RUN bundle install
COPY . .
ENTRYPOINT ["./docker/entrypoint.sh"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
