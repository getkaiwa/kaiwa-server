FROM ubuntu:14.04

ENV DEBIAN_FRONTEND noninteractive
ENV HOME /root

ENV XMPP_DOMAIN example.com

ENV DB_NAME docker
ENV DB_USER docker
ENV DB_PWD docker

ENV LDAP_HOST container
ENV LDAP_DN ""
ENV LDAP_PWD ""
ENV LDAP_GROUP mygroup
ENV LDAP_USER_BASE ou=users,dc=example.com
ENV LDAP_GROUP_BASE ou=groups,dc=example.com

ENV SSL_CRT ""
ENV SSL_KEY ""

RUN sed -i 's/^#\s*\(deb.*universe\)$/\1/g' /etc/apt/sources.list && \
    sed -i 's/^#\s*\(deb.*multiverse\)$/\1/g' /etc/apt/sources.list && \
    apt-get -y update && \
    dpkg-divert --local --rename --add /sbin/initctl && \
    ln -sf /bin/true /sbin/initctl && \
    dpkg-divert --local --rename --add /usr/bin/ischroot && \
    ln -sf /bin/true /usr/bin/ischroot && \
    apt-get -y upgrade && \
    apt-get install -y vim wget sudo net-tools pwgen unzip openssh-server \
        logrotate supervisor language-pack-en software-properties-common \
        python-software-properties apt-transport-https ca-certificates curl && \
    apt-get clean

RUN locale-gen en_US && locale-gen en_US.UTF-8 && echo 'LANG="en_US.UTF-8"' > /etc/default/locale

RUN add-apt-repository -y ppa:patrick-georgi/ppa
RUN apt-get update

RUN apt-get install -y --force-yes postgresql-client lua5.1 liblua5.1-dev lua-bitop lua-bitop-dev lua-sec lua-ldap lua-dbi-postgresql lua-expat lua-socket lua-filesystem lua-zlib lua-event libidn11-dev libssl-dev mercurial bsdmainutils make openssl

RUN groupadd prosody
RUN useradd -g prosody prosody

RUN hg clone http://hg.prosody.im/trunk prosody-trunk

RUN cd prosody-trunk && ./configure --ostype=debian --prefix=/usr --sysconfdir=/etc/prosody --datadir=/var/lib/prosody --require-config

RUN cd prosody-trunk && make && make install

RUN mkdir /etc/prosody/conf.d /var/log/prosody

RUN chown -R prosody:prosody /etc/prosody /var/lib/prosody /var/log/prosody

RUN mkdir -p /var/run/prosody
RUN chown prosody.prosody /var/run/prosody

ADD app /app
RUN chmod +x /app/start.sh

CMD "/app/start.sh"
