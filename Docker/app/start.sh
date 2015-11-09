#!/bin/bash
#
# Required vars:
#  - DB_NAME
#  - DB_USER
#  - DB_PWD
#  - LDAP_HOST
#  - LDAP_USER_BASE
#  - LDAP_GROUP_BASE
#  - LDAP_DN
#  - LDAP_PWD
#  - LDAP_GROUP

echo "Configuring certificates..."

if [[ -f "${SSL_CRT}" && -f "${SSL_KEY}" ]]
then
  echo "Files found -> copy"
  cp ${SSL_CRT} /etc/prosody/certs/localhost.crt
  cp ${SSL_KEY} /etc/prosody/certs/localhost.key
else
  echo "Files not found -> create"
  openssl req -new -x509 -days 365 -nodes -out "/etc/prosody/certs/localhost.crt" -newkey rsa:2048 -keyout "/etc/prosody/certs/localhost.key" -subj "/C=FR/ST=/L=/O=${XMPP_NAME}/CN=${XMPP_DOMAIN}"
fi
chown prosody:prosody /etc/prosody/certs/*

echo "Configuring prosody.cfg.lua..."

sed 's/{{XMPP_DOMAIN}}/'"${XMPP_DOMAIN}"'/' -i /app/config/prosody.cfg.lua

echo "Configuring Postgresql using link ${POSTGRES_PORT_5432_TCP_ADDR}:${POSTGRES_PORT_5432_TCP_PORT}..."

sed 's/{{DB_HOST}}/'"${POSTGRES_PORT_5432_TCP_ADDR}"'/' -i /app/config/prosody.cfg.lua
sed 's/{{DB_PORT}}/'"${POSTGRES_PORT_5432_TCP_PORT}"'/' -i /app/config/prosody.cfg.lua
sed 's/{{DB_NAME}}/'"${DB_NAME}"'/' -i /app/config/prosody.cfg.lua
sed 's/{{DB_USER}}/'"${DB_USER}"'/' -i /app/config/prosody.cfg.lua
sed 's/{{DB_PWD}}/'"${DB_PWD}"'/' -i /app/config/prosody.cfg.lua

cp -f /app/config/prosody.cfg.lua /etc/prosody/prosody.cfg.lua
chmod 755 /etc/prosody/prosody.cfg.lua

echo "Configuring prosody-ldap.cfg.lua..."

sed 's/{{XMPP_DOMAIN}}/'"${XMPP_DOMAIN}"'/' -i /app/config/prosody-ldap.cfg.lua

if [ ${LDAP_HOST} = "container" ]; then
  LDAP_HOST=${LDAP_PORT_389_TCP_ADDR}
fi
sed 's/{{LDAP_HOST}}/'"${LDAP_HOST}"'/' -i /app/config/prosody-ldap.cfg.lua
if [ -n "${LDAP_DN}" ]; then
    sed 's/{{LDAP_DN}}/'"${LDAP_DN}"'/' -i /app/config/prosody-ldap.cfg.lua
else
    sed '/{{LDAP_DN}}/d' -i /app/config/prosody-ldap.cfg.lua
fi
if [ -n "${LDAP_PWD}" ]; then
    sed 's/{{LDAP_PWD}}/'"${LDAP_PWD}"'/' -i /app/config/prosody-ldap.cfg.lua
else
    sed '/{{LDAP_PWD}}/d' -i /app/config/prosody-ldap.cfg.lua
fi
sed 's/{{LDAP_USER_BASE}}/'"${LDAP_USER_BASE}"'/' -i /app/config/prosody-ldap.cfg.lua
sed 's/{{LDAP_GROUP_BASE}}/'"${LDAP_GROUP_BASE}"'/' -i /app/config/prosody-ldap.cfg.lua
sed 's/{{LDAP_GROUP}}/'"${LDAP_GROUP}"'/' -i /app/config/prosody-ldap.cfg.lua

cp -f /app/config/prosody-ldap.cfg.lua /etc/prosody/prosody-ldap.cfg.lua
chmod 755 /etc/prosody/prosody-ldap.cfg.lua

echo "Configuring domain.cfg.lua..."

echo VirtualHost \"${XMPP_DOMAIN}\" >> /etc/prosody/conf.d/domain.cfg.lua
echo "	ssl = {" >> /etc/prosody/conf.d/domain.cfg.lua
echo "		key = \"/etc/prosody/certs/localhost.key\";" >> /etc/prosody/conf.d/domain.cfg.lua
echo "		certificate = \"/etc/prosody/certs/localhost.crt\";" >> /etc/prosody/conf.d/domain.cfg.lua
echo "	}" >> /etc/prosody/conf.d/domain.cfg.lua
echo Component \"chat.${XMPP_DOMAIN}\" \"muc\" >> /etc/prosody/conf.d/domain.cfg.lua
echo "    name = \"The ${XMPP_DOMAIN} chatrooms server\"" >> /etc/prosody/conf.d/domain.cfg.lua
echo "    restrict_room_creation = \"local\"" >> /etc/prosody/conf.d/domain.cfg.lua
echo "    max_history_messages = 50;" >> /etc/prosody/conf.d/domain.cfg.lua
echo "    max_archive_query_results = 50;" >> /etc/prosody/conf.d/domain.cfg.lua
echo "    muc_log_by_default = true;" >> /etc/prosody/conf.d/domain.cfg.lua
echo "    muc_log_all_rooms = true;" >> /etc/prosody/conf.d/domain.cfg.lua

chmod 755 /etc/prosody/conf.d/domain.cfg.lua

echo "Adding module files..."

cp -rf /app/modules/* /usr/lib/prosody/modules/
chmod -R 755 /usr/lib/prosody/modules/

prosodyctl start

tail -f /var/log/prosody/prosody.log
