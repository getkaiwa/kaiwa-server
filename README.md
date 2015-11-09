# Kaiwa server

Any XMPP server that supports websockets would work, but Prosody also supports
some extra features that makes Kaiwa nicer to use, like message archiving.

It works with PostgreSQL (and LDAP optionally).

## Installation with Docker

1. Start a PostgreSQL Docker image
```bash
        $ docker pull orchardup/postgresql
        $ docker run -d \
             --name postgres \
             -p 5432:5432 \
             -e POSTGRESQL_USER=kaiwa \
             -e POSTGRESQL_PASS=mypassword \
             orchardup/postgresql
```

2. Start and configure an LDAP Docker image (optional)
```bash
        $ docker pull nickstenning/slapd
        $ docker run -d \
             --name ldap \
             -p 389:389 \
             -e LDAP_DOMAIN=myorga \
             -e LDAP_ORGANISATION=MyOrganisation \
             -e LDAP_ROOTPASS=mypassword \
             nickstenning/slapd
        $ wget https://raw.githubusercontent.com/digicoop/kaiwa-server/master/users.ldif
        $ sed 's/admin@example.com/admin@myorga.com/' -i users.ldif
        $ sed 's/user1@example.com/bob@myorga.com/' -i users.ldif
        $ sed 's/adminpass/mypassword/' -i users.ldif
        $ sed 's/user1pass/mypassword/' -i users.ldif
        $ sed 's/example.com/myorga/' -i users.ldif
        $ sed 's/ExampleDesc/MyOrgaDesc/' -i users.ldif
        $ sed 's/user1/bob/' -i users.ldif
        $ ldapadd -h localhost -x -D cn=admin,dc=myorga -w mypassword -f users.ldif
```

3. Start a Kaiwa-server Docker image

    LDAP params are not mandatory
```bash
        $ docker pull sebu77/kaiwa-server
        $ docker run -d \
             -p 5222:5222 -p 5269:5269 -p 5280:5280 -p 5281:5281 -p 3478:3478/udp \
             --name kaiwa-server \
             --link postgres:postgres \
             --link ldap:ldap \
             -e XMPP_DOMAIN=myorga.com \
             -e DB_NAME=kaiwa \
             -e DB_USER=kaiwa \
             -e DB_PWD=mypassword \
             -e LDAP_BASE=dc=myorga \
             -e LDAP_DN=cn=admin,dc=myorga \
             -e LDAP_PWD=mypassword \
             -e LDAP_GROUP=myorgagroup \
             sebu77/kaiwa-server
```

4. Start a Kaiwa Docker image

    LDAP params are not mandatory
```bash
        $ docker pull sebu77/kaiwa
        $ docker run -d \
             -p 80:8000 \
             --name kaiwa \
             --link ldap:ldap \
             -e XMPP_NAME=" + data.org + " \
             -e XMPP_DOMAIN=myorga.com \
             -e XMPP_WSS=ws://myorga.com:5280/xmpp-websocket \
             -e XMPP_MUC=chat.myorga.com \
             -e XMPP_STARTUP=groupchat/home%40chat.myorga.com \
             -e XMPP_ADMIN=admin \
             -e LDAP_BASE=dc=myorga \
             -e LDAP_DN=cn=admin,dc=myorga \
             -e LDAP_PWD=mypassword \
             -e LDAP_GROUP=myorgagroup \
             sebu77/kaiwa
```

## Installation from source

1. Install dependencies

        add-apt-repository -y ppa:patrick-georgi/ppa
        apt-get update
        apt-get install postgresql-client lua5.1 liblua5.1-dev lua-bitop lua-bitop-dev lua-sec lua-ldap lua-dbi-postgresql lua-expat lua-socket lua-filesystem lua-zlib lua-event libidn11-dev libssl-dev mercurial bsdmainutils make openssl

2. Install Prosody from sources

        groupadd prosody
        useradd -g prosody prosody
        hg clone http://hg.prosody.im/trunk prosody-trunk
        cd prosody-trunk && ./configure --ostype=debian --prefix=/usr --sysconfdir=/etc/prosody --datadir=/var/lib/prosody --require-config
        make && make install
        openssl req -new -x509 -days 365 -nodes -out "/etc/prosody/certs/localhost.crt" -newkey rsa:2048 -keyout "/etc/prosody/certs/localhost.key" -subj "/C=FR/ST=/L=Paris/O=Orga/CN=localhost"
        chown prosody:prosody /etc/prosody/certs/*
        ln -s /etc/prosody/certs/localhost.key "/etc/prosody/certs/localhost.key"
        RUN ln -s /etc/prosody/certs/localhost.crt "/etc/prosody/certs/localhost.crt"
        mkdir /etc/prosody/conf.d /var/log/prosody
        chown -R prosody:prosody /etc/prosody /var/lib/prosody /var/log/prosody
        mkdir -p /var/run/prosody
        chown prosody.prosody /var/run/prosody

3. Install the included modules

        cp -r modules/* /usr/lib/prosody/modules/
        chmod -R 755 /usr/lib/prosody/modules/

4. Configure Prosody

   First edit the included template config to replace the HOST value, and set any other desired options.

        cp -f /app/config/prosody.cfg.lua /etc/prosody/prosody.cfg.lua
        chmod 755 /etc/prosody/prosody.cfg.lua
        cp -f /app/config/prosody-ldap.cfg.lua /etc/prosody/prosody-ldap.cfg.lua
        chmod 755 /etc/prosody/prosody-ldap.cfg.lua

5. Allow access to port 5281. Proxying to hide the port would be best (eg, use `wss://HOST/xmpp-websocket`).

   If you don't proxy the WS connections, be sure to visit https://HOST:5281/xmpp-websocket first so that
   any client certificate requests are fulfilled. Otherwise, connecting to Kaiwa might fail because the
   browser closes the websocket connection if prompted for client certs.

## Ports / DNS

By default, You will need to ensure that these ports are open on your server:

- 5222 (XMPP client to server connections)
- 5269 (XMPP server to server connections)
- 5280/5281 HTTP and WebSocket connection (5281 for SSL versions)
- 3478 UDP (STUN/TURN)

You should also setup DNS SRV records:

- `_xmpp-client._tcp.HOST 3600 IN SRV 0 10 5222 HOST`
- `_xmpp-server._tcp.HOST 3600 IN SRV 0 10 5269 HOST`

If you use the `mod_http_altconnect` module, Kaiwa will be able to auto-discover the WebSocket connection
endpoint for your server, if you make https://HOST/.well-known/host-meta served by Prosody.

One way to do this is to make Prosody act as your HTTP server. An example nginx config for doing that
is included.

