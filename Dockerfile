FROM ubuntu:22.04

LABEL maintainer="Jonathon Byrdziak"

ARG NODE_VERSION=16
ARG USER_ID=1000
ARG GROUP_ID=1000 

WORKDIR /var/www/html
USER root

ENV DEBIAN_FRONTEND noninteractive
ENV TZ=UTC

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

## Set proper user/group permissions before running scripts 
# www-data:www-data maps to user 33:33, we want it to map to 1000:1000, 
# the primary user on the host machine
RUN userdel -f www-data \
    && if getent group www-data ; then groupdel www-data; fi

# The dialout group conflicts with MAC and removing it isn't a problem...
RUN if getent group dialout ; then groupdel dialout; fi

RUN addgroup --gid ${GROUP_ID} www-data &&\
    useradd -l -u ${USER_ID} -g www-data www-data &&\
    install -d -m 0755 -o www-data -g www-data /home/www-data &&\
    chown --changes --silent --no-dereference --recursive \
          --from=33:33 ${USER_ID}:${GROUP_ID} \
        /home/www-data

RUN apt-get update \
    && apt-get install lsb-release ca-certificates apt-transport-https software-properties-common -y \
    && add-apt-repository ppa:ondrej/php \
    && apt-get install -y gnupg gosu curl zip unzip git supervisor sqlite3 libcap2-bin libpng-dev python2

## Now build the webserver
RUN apt-get update \
    && apt-get install -y \
       php7.4-cli php7.4-dev php7.4-xdebug \
       php7.4-pgsql php7.4-sqlite3 php7.4-odbc \
       php7.4-redis php7.4-memcached php7.4-gd \
       php7.4-curl php7.4-imap php7.4-mysql php7.4-mbstring \
       php7.4-xml php7.4-zip php7.4-bcmath php7.4-soap \
       php7.4-intl php7.4-readline php7.4-pcov \
       php7.4-msgpack php7.4-igbinary php7.4-ldap \
       php7.4-fpm \
    && php -r "readfile('http://getcomposer.org/installer');" | php -- --install-dir=/usr/bin/ --filename=composer \
    && curl -sL https://deb.nodesource.com/setup_$NODE_VERSION.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g npm \
    && apt-get install -y yarn \
    && apt-get install -y mysql-client \
    && apt-get install -y postgresql-client \
    && apt-get -y autoremove \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && apt-get update -y \
    && apt-get install nginx  -y

# Install Databricks Driver
RUN apt-get update \
    && apt-get install -y unixodbc unixodbc-dev libsasl2-modules-gssapi-mit wget
RUN wget https://databricks-bi-artifacts.s3.us-east-2.amazonaws.com/simbaspark-drivers/odbc/2.6.26/SimbaSparkODBC-2.6.26.1045-Debian-64bit.zip
RUN unzip SimbaSparkODBC-2.6.26.1045-Debian-64bit.zip
RUN dpkg -i simbaspark_2.6.26.1045-2_amd64.deb

#RUN apt-get update \
#    && apt-get install pip -y \
#    && pip install ngxtop nano

RUN setcap "cap_net_bind_service=+ep" /usr/bin/php7.4
RUN mkdir /opt/scripts/

COPY start-container /usr/local/bin/start-container
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

COPY nginx/make-localhost-cert /opt/scripts/make-localhost-cert
COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/sites-enabled/default.conf /etc/nginx/sites-available/default
COPY nginx/sites-enabled/default-ssl.conf /etc/nginx/sites-enabled/default-ssl

COPY php/php-fpm.conf /etc/php/7.4/fpm/pool.d/www.conf
COPY php/php.ini /etc/php/7.4/cli/php.ini
COPY php/php.ini /etc/php/7.4/fpm/php.ini
COPY php/xdebug.ini /etc/php/7.4/mods-available/xdebug.ini
COPY php/opcache.ini /etc/php/7.4/mods-available/opcache.ini

RUN rm -f /var/www/html/index.nginx-debian.html
RUN mkdir /var/www/html/nginx.d/ 
COPY html/* /var/www/html/

# Installing the cron
RUN apt-get update -y && apt-get install cron -yqq

RUN rm -Rf /etc/cron.daily
RUN rm -Rf /etc/cron.weekly
RUN rm -Rf /etc/cron.monthly
RUN rm -Rf /etc/cron.hourly

COPY cron/samplecron.sh /var/www/html/cron.d/samplecron.sh
COPY cron/runcron.sh /opt/scripts/runcron.sh
COPY cron/crontab /etc/cron.d/webapp

RUN crontab /etc/cron.d/webapp
RUN touch /var/log/cron.log
RUN mkdir /var/log/cron/
RUN chmod 0600 /etc/cron.d/webapp

#######  Turn on/Run the container #########
RUN chmod +x /usr/local/bin/start-container

EXPOSE 80
EXPOSE 443

## Finally start the container services...
ENTRYPOINT ["start-container"]
