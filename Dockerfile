FROM jruby:9.2.7

RUN apt-get update &&\
  apt-get install -y \
    git \
    make \
  && apt-get clean && \
  rm -r /var/lib/apt/lists/*

RUN git clone https://github.com/wattania/jasper_libs.git &&\
  cd /jasper_libs &&\
  git reset --hard be827993c13788f70ca57258c401feda9c356d79 &&\
  rm -rf .git

COPY Gemfile Gemfile.lock /
RUN bundle install

COPY . /jreport
WORKDIR /jreport
#CMD [ "./entrypoint.sh" ]
CMD [ "rails", "server", "-b", "0.0.0.0" ]
