FROM ruby:3.3
WORKDIR /app
RUN apt-get update -qq && apt-get install -y build-essential default-libmysqlclient-dev mariadb-client
COPY Gemfile Gemfile.lock* ./
RUN bundle install
COPY . .
ENTRYPOINT ["./docker/entrypoint.sh"]
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
