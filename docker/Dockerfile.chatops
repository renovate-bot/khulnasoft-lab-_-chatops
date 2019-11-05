FROM ruby:2.6-alpine

COPY Gemfile .
COPY Gemfile.lock .

WORKDIR app
ADD . /app/

RUN apk add --update build-base postgresql-dev
RUN gem install bundler --no-document
RUN bundle config --local path vendor/bundle
RUN bundle install --path vendor/bundle --retry 3 --deployment --without development
