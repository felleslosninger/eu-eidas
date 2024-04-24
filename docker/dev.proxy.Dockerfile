FROM maven:3.9-eclipse-temurin-11 as builder

WORKDIR /data

# Download EU-eidas software
RUN git clone https://ec.europa.eu/digital-building-blocks/code/scm/eid/eidasnode-pub.git

RUN cd eidasnode-pub && mvn clean install --file EIDAS-Parent/pom.xml -P NodeOnly -P nodeJcacheIgnite -P specificCommunicationJcacheIgnite

FROM tomcat:9.0-jre11-temurin-jammy

RUN groupadd --system --gid 1000 tomcat \
    && adduser --system --uid 1000 --gid 1000 tomcat \
    && chown -R tomcat $CATALINA_HOME

USER tomcat

COPY docker/bouncycastle/java_bc.security /opt/java/openjdk/conf/security/java_bc.security
COPY docker/bouncycastle/bcprov-jdk18on-1.78.jar /usr/local/lib/bcprov-jdk18on-1.78.jar

# change tomcat port
RUN sed -i 's/port="8080"/port="8082"/' ${CATALINA_HOME}/conf/server.xml

COPY docker/proxy/tomcat-setenv.sh ${CATALINA_HOME}/bin/setenv.sh

RUN mkdir -p $CATALINA_HOME/eidas-proxy-config/ && pwd
COPY docker/proxy/config/ $CATALINA_HOME/eidas-proxy-config

# Replace base URLs in eidas.xml and metadata (whitelist). TODO: move to environment specific k8 config
RUN sed -i 's/EU-PROXY-URL/http:\/\/eu-eidas-proxy:8082/g' ${CATALINA_HOME}/eidas-proxy-config/eidas.xml
RUN sed -i 's/EIDAS-PROXY-URL/http:\/\/eidas-proxy:8081/g' ${CATALINA_HOME}/eidas-proxy-config/eidas.xml
RUN sed -i 's/DEMOLAND-CA-URL/http:\/\/eidas-demo-ca:8080/g' ${CATALINA_HOME}/eidas-proxy-config/metadata/MetadataFetcher_Service.properties
RUN sed -i 's/NO-EU-EIDAS-CONNECTOR-URL/http:\/\/eu-eidas-connector:8083/g' $CATALINA_HOME/eidas-proxy-config/metadata/MetadataFetcher_Service.properties

# Only for local development
RUN sed -i 's/metadata.restrict.http">true/metadata.restrict.http">false/g' ${CATALINA_HOME}/eidas-proxy-config/eidas.xml


# Add war files to webapps: /usr/local/tomcat/webapps
COPY --from=builder /data/eidasnode-pub/EIDAS-Node-Proxy/target/EidasNodeProxy.war ${CATALINA_HOME}/webapps/

# eIDAS audit log folder
RUN mkdir -p ${CATALINA_HOME}/eidas/logs

EXPOSE 8082
