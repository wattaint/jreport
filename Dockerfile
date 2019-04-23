FROM jruby:9.2.7

RUN apt-get update &&\
  apt-get install \
    make \
  && apt-get clean && \
  rm -r /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock /
RUN bundle install
