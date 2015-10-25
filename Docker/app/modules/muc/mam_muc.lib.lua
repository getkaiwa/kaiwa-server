-- XEP-0313: Message Archive Management for Prosody MUC
-- Copyright (C) 2011-2014 Kim Alvefur
--
-- This file is MIT/X11 licensed.

local xmlns_mam     = "urn:xmpp:mam:0";
local xmlns_delay   = "urn:xmpp:delay";
local xmlns_forward = "urn:xmpp:forward:0";
local muc_form_enable_logging = "muc#roomconfig_enablelogging"

local st = require "util.stanza";
local rsm = module:require "mod_mam/rsm";
local jid_bare = require "util.jid".bare;
local jid_split = require "util.jid".split;
local dataform = require "util.dataforms".new;
local it = require"util.iterators";

-- Support both old and new MUC code
--local mod_muc = module:depends"muc";
local rooms;-- = rawget(mod_muc, "rooms");
local each_room = --[[rawget(mod_muc, "each_room") or ]]function() return it.values(rooms); end;
local new_muc = not rooms;
if new_muc then
	rooms = module:shared"muc/rooms";
end
local get_room_from_jid = --[[rawget(mod_muc, "get_room_from_jid") or ]]
	function (jid)
		return rooms[jid];
	end

local getmetatable = getmetatable;
local function is_stanza(x)
	return getmetatable(x) == st.stanza_mt;
end

local tostring = tostring;
local time_now = os.time;
local m_min = math.min;
local timestamp, timestamp_parse = require "util.datetime".datetime, require "util.datetime".parse;
local max_history_length = module:get_option_number("max_history_messages", 50);
local default_max_items, max_max_items = 20, module:get_option_number("max_archive_query_results", max_history_length);

local log_all_rooms = module:get_option_boolean("muc_log_all_rooms", false);
local log_by_default = module:get_option_boolean("muc_log_by_default", true);

local archive_store = "muc_log";
local archive = module:open_store(archive_store, "archive");
if not archive or archive.name == "null" then
	module:log("error", "Could not open archive storage");
	return
elseif not archive.find then
	module:log("error", "mod_%s does not support archiving, switch to mod_storage_sql2", archive._provided_by);
	return
end

local function logging_enabled(room)
	if log_all_rooms then
		return true;
	end
	local enabled = room._data.logging;
	if enabled == nil then
		return log_by_default;
	end
	return enabled;
end

local send_history, save_to_history;

	-- Override history methods for all rooms.
if not new_muc then -- 0.10 or older
	module:hook("muc-room-created", function (event)
		local room = event.room;
		if logging_enabled(room) then
			room.send_history = send_history;
			room.save_to_history = save_to_history;
		end
	end);

	function module.load()
		for room in each_room() do
			if logging_enabled(room) then
				room.send_history = send_history;
				room.save_to_history = save_to_history;
			end
		end
	end
	function module.unload()
		for room in each_room() do
			if room.send_history == send_history then
				room.send_history = nil;
				room.save_to_history = nil;
			end
		end
	end
end

if not log_all_rooms then
	module:hook("muc-config-form", function(event)
		local room, form = event.room, event.form;
		table.insert(form,
		{
			name = muc_form_enable_logging,
			type = "boolean",
			label = "Enable Logging?",
			value = logging_enabled(room),
		}
		);
	end);

	module:hook("muc-config-submitted", function(event)
		local room, fields, changed = event.room, event.fields, event.changed;
		local new = fields[muc_form_enable_logging];
		if new ~= room._data.logging then
			room._data.logging = new;
			if type(changed) == "table" then
				changed[muc_form_enable_logging] = true;
			else
				event.changed = true;
			end
			if new then
				room.send_history = send_history;
				room.save_to_history = save_to_history;
			else
				room.send_history = nil;
				room.save_to_history = nil;
			end
		end
	end);
end

-- Note: We ignore the 'with' field as this is internally used for stanza types
local query_form = dataform {
	{ name = "FORM_TYPE"; type = "hidden"; value = xmlns_mam; };
	{ name = "with"; type = "jid-single"; };
	{ name = "start"; type = "text-single" };
	{ name = "end"; type = "text-single"; };
};

-- Serve form
module:hook("iq-get/bare/"..xmlns_mam..":query", function(event)
	local origin, stanza = event.origin, event.stanza;
	origin.send(st.reply(stanza):add_child(query_form:form()));
	return true;
end);

-- Handle archive queries
module:hook("iq-set/bare/"..xmlns_mam..":query", function(event)
	local origin, stanza = event.origin, event.stanza;
	local room = stanza.attr.to;
	local room_node = jid_split(room);
	local orig_from = stanza.attr.from;
	local query = stanza.tags[1];

	local room_obj = get_room_from_jid(room);
	if not room_obj then
		origin.send(st.error_reply(stanza, "cancel", "item-not-found"))
		return true;
	end
	local from = jid_bare(orig_from);

	-- Banned or not a member of a members-only room?
	local from_affiliation = room_obj:get_affiliation(from);
	if from_affiliation == "outcast" -- banned
		or room_obj:get_members_only() and not from_affiliation then -- members-only, not a member
		origin.send(st.error_reply(stanza, "auth", "forbidden"))
		return true;
	end

	local qid = query.attr.queryid;

	-- Search query parameters
	local qstart, qend;
	local form = query:get_child("x", "jabber:x:data");
	if form then
		local err;
		form, err = query_form:data(form);
		if err then
			origin.send(st.error_reply(stanza, "modify", "bad-request", select(2, next(err))));
			return true;
		end
		qstart, qend = form["start"], form["end"];
	end

	if qstart or qend then -- Validate timestamps
		local vstart, vend = (qstart and timestamp_parse(qstart)), (qend and timestamp_parse(qend))
		if (qstart and not vstart) or (qend and not vend) then
			origin.send(st.error_reply(stanza, "modify", "bad-request", "Invalid timestamp"))
			return true
		end
		qstart, qend = vstart, vend;
	end

	-- RSM stuff
	local qset = rsm.get(query);
	local qmax = m_min(qset and qset.max or default_max_items, max_max_items);
	local reverse = qset and qset.before or false;

	local before, after = qset and qset.before, qset and qset.after;
	if type(before) ~= "string" then before = nil; end

	-- Load all the data!
	local data, err = archive:find(room_node, {
		start = qstart; ["end"] = qend; -- Time range
		limit = qmax + 1;
		before = before; after = after;
		reverse = reverse;
		total = true;
		with = "message<groupchat";
	});

	if not data then
		origin.send(st.error_reply(stanza, "cancel", "internal-server-error"));
		return true;
	end
	local total = err;

	origin.send(st.reply(stanza))
	local msg_reply_attr = { to = stanza.attr.from, from = stanza.attr.to };

	local results = {};

	-- Wrap it in stuff and deliver
	local first, last;
	local count = 0;
	local complete = "true";
	for id, item, when in data do
		count = count + 1;
		if count > qmax then
			complete = nil;
			break;
		end
		local fwd_st = st.message(msg_reply_attr)
			:tag("result", { xmlns = xmlns_mam, queryid = qid, id = id })
				:tag("forwarded", { xmlns = xmlns_forward })
					:tag("delay", { xmlns = xmlns_delay, stamp = timestamp(when) }):up();

		if not is_stanza(item) then
			item = st.deserialize(item);
		end
		item.attr.xmlns = "jabber:client";
		fwd_st:add_child(item);

		if not first then first = id; end
		last = id;

		if reverse then
			results[count] = fwd_st;
		else
			origin.send(fwd_st);
		end
	end
	if reverse then
		for i = #results, 1, -1 do
			origin.send(results[i]);
		end
	end

	-- That's all folks!
	module:log("debug", "Archive query %s completed", tostring(qid));

	if reverse then first, last = last, first; end
	origin.send(st.message(msg_reply_attr)
		:tag("fin", { xmlns = xmlns_mam, queryid = qid, complete = complete })
			:add_child(rsm.generate {
				first = first, last = last, count = total }));
	return true;
end);

module:hook("muc-get-history", function (event)
	local room = event.room;
	if not logging_enabled(room) then return end
	local room_jid = room.jid;
	local maxstanzas = event.maxstanzas;
	local maxchars = event.maxchars;
	local since = event.since;
	local to = event.to;

	-- Load all the data!
	local query = {
		limit = m_min(maxstanzas or 20, max_history_length);
		start = since;
		reverse = true;
		with = "message<groupchat";
	}
	module:log("debug", require"util.serialization".serialize(query))
	local data, err = archive:find(jid_split(room_jid), query);

	if not data then
		module:log("error", "Could not fetch history: %s", tostring(err));
		return
	end

	local history, i = {}, 1;

	for _, item, when in data do
		item.attr.to = to;
		item:tag("delay", { xmlns = "urn:xmpp:delay", from = room_jid, stamp = timestamp(when) }):up(); -- XEP-0203
		if maxchars then
			local chars = #tostring(item);
			if maxchars - chars < 0 then
				break
			end
			maxchars = maxchars - chars;
		end
		history[i], i = item, i+1;
	end
	function event.next_stanza()
		i = i - 1;
		return history[i];
	end
	return true;
end, 1);

function send_history(self, to, stanza)
	local maxchars, maxstanzas, seconds, since;
	local history_tag = stanza:find("{http://jabber.org/protocol/muc}x/history")
	if history_tag then
		local history_attr = history_tag.attr;
		maxchars = tonumber(history_attr.maxchars);
		maxstanzas = tonumber(history_attr.maxstanzas);
		seconds = tonumber(history_attr.seconds);
		since = history_attr.since;
		if since then
			since = timestamp_parse(since);
		end
		if seconds then
			since = math.max(os.time() - seconds, since or 0);
		end
	end

	local event = {
		room = self;
		to = to; -- `to` is required to calculate the character count for `maxchars`
		maxchars = maxchars, maxstanzas = maxstanzas, since = since;
		next_stanza = function() end; -- events should define this iterator
	};
	module:fire_event("muc-get-history", event);

	for msg in event.next_stanza, event do
		self:_route_stanza(msg);
	end
end

-- Handle messages
function save_to_history(self, stanza)
	local room = jid_split(self.jid);

	-- Policy check
	if not logging_enabled(self) then return end -- Don't log

	module:log("debug", "We're logging this")
	-- And stash it
	local with = stanza.name
	if stanza.attr.type then
		with = with .. "<" .. stanza.attr.type
	end
	archive:append(room, nil, time_now(), with, stanza);
end

module:hook("muc-broadcast-message", function (event)
	local room, stanza = event.room, event.stanza;
	if stanza:get_child("body") then
		save_to_history(room, stanza);
	end
end);

if module:get_option_boolean("muc_log_presences", true) then
	module:hook("muc-occupant-joined", function (event)
		save_to_history(event.room, st.stanza("presence", { from = event.nick }));
	end);
	module:hook("muc-occupant-left", function (event)
		save_to_history(event.room, st.stanza("presence", { type = "unavailable", from = event.nick }));
	end);
end

module:hook("muc-room-destroyed", function(event)
	local username = jid_split(event.room.jid);
	archive:delete(username);
end);

-- TODO should we perhaps log presence as well?
-- And role/affiliation changes?

module:add_feature(xmlns_mam);

module:hook("muc-disco#info", function(event)
	event.reply:tag("feature", {var=xmlns_mam}):up();
end);
