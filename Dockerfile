FROM maven:3.6.1-jdk-8 as jarlibs

RUN wget https://repo1.maven.org/maven2/net/sf/jasperreports/jasperreports/6.9.0/jasperreports-6.9.0.pom -O /pom.xml
RUN mvn dependency:resolve
RUN mkdir /jars &&\
  cp $(find /root/.m2/repository/ -type f | grep ".jar$") /jars/
RUN wget https://repo1.maven.org/maven2/net/sf/jasperreports/jasperreports/6.9.0/jasperreports-6.9.0.jar -O /jars/jasperreports-6.9.0.jar

FROM jruby:9.2.7.0-jre
COPY --from=jarlibs /jars /jars

RUN apt-get update &&\
  apt-get install -y \
    make \
  && apt-get clean && \
  rm -r /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock /
RUN bundle install

COPY . /jreport
WORKDIR /jreport
#CMD [ "./entrypoint.sh" ]
CMD [ "rails", "server", "-b", "0.0.0.0" ]
