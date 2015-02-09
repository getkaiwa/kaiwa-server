-- Last User Interaction in Presence via Last Activity compatibility module
-- http://xmpp.org/extensions/xep-0319.html
-- http://xmpp.org/extensions/xep-0012.html
-- Copyright (C) 2014 Tobias Markmann
--
-- This file is MIT/X11 licensed.

local st = require "util.stanza";
local datetime = require "util.datetime";

local function on_presence(event)
	local stanza = event.stanza;

	local last_activity = stanza.name == "presence" and stanza:get_child("query", "jabber:iq:last") or false;
	local has_idle = stanza:get_child("idle", "urn:xmpp:idle:1");
	if last_activity and not has_idle then
		module:log("debug", "Adding XEP-0319 tag from Last Activity.");
		local seconds = last_activity.attr.seconds;
		local last_userinteraction = datetime.datetime(os.time() - seconds);
		stanza:tag("idle", { xmlns = "urn:xmpp:idle:1", since = last_userinteraction }):up();
	end
end

-- incoming
module:hook("presence/full", on_presence, 900);
module:hook("presence/bare", on_presence, 900);

-- outgoing
module:hook("pre-presence/bare", on_presence, 900);
module:hook("pre-presence/full", on_presence, 900);
module:hook("pre-presence/host", on_presence, 900);