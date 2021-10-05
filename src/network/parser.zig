const std = @import("std");
const datetime = @import("datetime");
const Chat = @import("../Chat.zig");

const ParseResult = union(enum) {
    ping,
    clear: ?[]const u8,
    message: Chat.Message,
};

pub fn parseMessage(data: []u8, alloc: *std.mem.Allocator, tz: datetime.Timezone) !ParseResult {
    std.log.debug("data:\n{s}\n", .{data});
    if (data.len == 0) return error.NoData;

    // Basic message structure:
    // <@metadata >:<prefix> <command> <params> :<trailing>
    //
    // Metadata and trailing are optional. Metadata starts with `@` and ends with a space.
    // Prefix is missing from PINGs, present otherwise, commands can have zero params.

    var remaining_data: []const u8 = data;

    const metadata: []const u8 = blk: {
        if (remaining_data[0] == '@') {
            // Message has metadata
            const end = std.mem.indexOf(u8, data, " :") orelse return error.NoChunks;
            const m = remaining_data[1..end]; // Skip the `@`
            remaining_data = remaining_data[end + 1 ..]; // Leave the colon there to unify the two cases

            break :blk m;
        }

        // Message has no metadata
        break :blk "";
    };
    std.log.debug("metadata: [{s}]", .{metadata});

    // Prefix
    const prefix = blk: {
        if (remaining_data[0] == ':') {
            // Message has prefix
            const end = std.mem.indexOf(u8, remaining_data, " ") orelse return error.NoCommand;
            const p = remaining_data[1..end]; // Skip the colon
            remaining_data = remaining_data[end + 1 ..];

            break :blk p;
        }
        // Message has no prefix
        break :blk "";
    };
    std.log.debug("prefix: [{s}]", .{prefix});

    // Command and arguments
    const cmd_and_args = blk: {
        if (std.mem.indexOf(u8, remaining_data, " :")) |end| {
            // Message has trailer
            const cmd_and_args = remaining_data[0..end];
            remaining_data = remaining_data[end + 2 ..]; // Skip the entire separator

            break :blk cmd_and_args;
        }
        // Message has no trailer
        const cmd_and_args = remaining_data;
        remaining_data = "";
        break :blk cmd_and_args;
    };
    std.log.debug("cmd and args: [{s}]", .{cmd_and_args});

    // Trailer
    const trailer = remaining_data[0..]; // Empty string if no trailer
    std.log.debug("trailer: [{s}]", .{trailer});

    var cmd_and_args_it = std.mem.tokenize(u8, cmd_and_args, " ");
    const cmd = cmd_and_args_it.next().?; // Calling the iterator once should never fail

    // Prepare fields common to multiple msg types
    var time: [5]u8 = undefined;
    var now = datetime.Datetime.now().shiftTimezone(&tz);
    _ = std.fmt.bufPrint(&time, "{d:0>2}:{d:0>2}", .{
        now.time.hour,
        now.time.minute,
    }) catch unreachable; // we know we have the space

    // Switch over all possible message types
    if (std.mem.eql(u8, cmd, "PRIVMSG")) {
        const meta = try parseMetaSubsetLinear(metadata, [_][]const u8{
            "badge-info", // 0
            "display-name", // 1
            "emotes", // 2
            "mod", // 3
        });

        const sub_badge: Badge = if (meta[0].len > 0)
            try parseBadge(meta[0])
        else
            Badge{ .name = "", .count = 0 };
        const display_name = meta[1];
        const emotes = try parseEmotes(meta[2], alloc);
        const is_mod = std.mem.eql(u8, meta[3], "1");
        const highlight_pos = std.mem.indexOf(u8, metadata, "msg-id=highlighted-message;");

        return ParseResult{
            .message = Chat.Message{
                .login_name = display_name,
                .kind = .{
                    .chat = .{
                        .text = trailer,
                        .time = time,
                        .display_name = display_name,
                        .sub_months = sub_badge.count,
                        .is_founder = std.mem.eql(u8, sub_badge.name, "founder"),
                        .emotes = emotes,
                        .is_mod = is_mod,
                        .is_highlighted = highlight_pos != null,
                    },
                },
            },
        };
    } else if (std.mem.eql(u8, cmd, "CLEARCHAT")) {
        // @ban-duration=600;
        // room-id=102701971;
        // target-user-id=137180345;
        // tmi-sent-ts=1625379632217 :tmi.twitch.tv CLEARCHAT #kristoff_it :soul_serpent
        return ParseResult{
            .clear = if (trailer.len > 0) trailer else null,
        };
    } else if (std.mem.eql(u8, cmd, "USERNOTICE")) {
        // Welcome to a new world of pain.
        // Here's another great protocol idea from Twitch:
        // Hidden deep inside the metadata there's the `msg-id` field,
        // which, in the case of USERNOTICE is not a unique id, but
        // a tag that identifies the event type among the following:
        //
        //    sub, resub, subgift, anonsubgift, submysterygift,
        //    giftpaidupgrade, rewardgift, anongiftpaidupgrade,
        //    raid, unraid, ritual, bitsbadgetier
        //
        // If you read already other comments in this file you
        // probably know where this is going: each type has
        // different fields present, which makes our linear
        // scan strategy less applicable.
        // The solution in this case is to look twice: once to
        // get the message type and a second time to grab all the
        // fields we need.
        //
        // One might be tempted at this point to really implement
        // the sorted version of this algorithm NotLikeThis
        const msg_type = (try parseMetaSubsetLinear(metadata, [1][]const u8{"msg-id"}))[0];

        if (std.mem.eql(u8, msg_type, "raid")) {
            // @badge-info=;
            // badges=;
            // color=#5F9EA0;
            // display-name=togglebit;
            // emotes=;
            // flags=;
            // id=20d2355b-92d6-4262-a5d5-c0ef7ccb8bad;
            // login=togglebit;
            // mod=0;
            // msg-id=raid;
            // msg-param-displayName=togglebit;
            // msg-param-login=togglebit;
            // msg-param-profileImageURL=https://static-cdn.jtvnw.net/jtv_user_pictures/0bb9c502-ab5d-4440-9c9d-14e5260ebf86-profile_image-70x70.png;
            // msg-param-viewerCount=126;
            // room-id=102701971;
            // subscriber=0;
            // system-msg=126\sraiders\sfrom\stogglebit\shave\sjoined!;
            // tmi-sent-ts=1619015565551;
            // user-id=474725923;
            // user-type= :tmi.twitch.tv USERNOTICE #kristoff_it

            const meta = try parseMetaSubsetLinear(metadata, [_][]const u8{
                "display-name", // 0
                "login", // 1
                "msg-param-profileImageURL", // 2
                "msg-param-viewerCount", // 3
            });

            const count = try std.fmt.parseInt(usize, meta[3], 10);
            return ParseResult{
                .message = Chat.Message{
                    .login_name = meta[1],
                    .kind = .{
                        .raid = .{
                            .display_name = meta[0],
                            .profile_picture_url = meta[2],
                            .count = count,
                        },
                    },
                },
            };
        }
        if (std.mem.eql(u8, msg_type, "submysterygift")) {
            // @badge-info=founder/1;
            // badges=founder/0;
            // color=;
            // display-name=kristoff_it;
            // emotes=;
            // flags=;
            // id=47f6274d-970c-4f2e-ab10-6cf1474a0813;
            // login=kristoff_it;
            // mod=0;
            // msg-id=submysterygift;
            // msg-param-mass-gift-count=5;
            // msg-param-origin-id=d0\sf0\s99\s5b\s67\s87\s9d\s6e\s79\s92\se9\s25\sbf\s75\s40\s82\se0\s9b\sea\s2e;
            // msg-param-sender-count=5;
            // msg-param-sub-plan=1000;
            // room-id=180859114;
            // subscriber=1;
            // system-msg=kristoff_it\sis\sgifting\s5\sTier\s1\sSubs\sto\smattknite's\scommunity!\sThey've\sgifted\sa\stotal\sof\s5\sin\sthe\schannel!;
            // tmi-sent-ts=1609457534121;
            // user-id=102701971;
            // user-type= :tmi.twitch.tv USERNOTICE #mattknite
            const meta = try parseMetaSubsetLinear(metadata, [_][]const u8{
                "display-name", // 0
                "login", // 1
                "msg-param-mass-gift-count", // 2
                "msg-param-sub-plan", // 3
            });

            const count = try std.fmt.parseInt(usize, meta[2], 10);
            const tier = try parseSubTier(meta[3]);

            return ParseResult{
                .message = Chat.Message{
                    .login_name = meta[1],
                    .kind = .{
                        .sub_mistery_gift = .{
                            .display_name = meta[0],
                            .count = count,
                            .tier = tier,
                        },
                    },
                },
            };
        } else if (std.mem.eql(u8, msg_type, "subgift")) {
            // @badge-info=founder/1;
            // badges=founder/0;
            // color=;
            // display-name=kristoff_it;
            // emotes=;
            // flags=;
            // id=b35bbd66-50e7-4b77-831c-fab505906551;
            // login=kristoff_it;
            // mod=0;
            // msg-id=subgift;
            // msg-param-gift-months=1;
            // msg-param-months=1;
            // msg-param-origin-id=da\s39\sa3\see\s5e\s6b\s4b\s0d\s32\s55\sbf\sef\s95\s60\s18\s90\saf\sd8\s07\s09;
            // msg-param-recipient-display-name=g_w1;
            // msg-param-recipient-id=203259404;
            // msg-param-recipient-user-name=g_w1;
            // msg-param-sender-count=0;
            // msg-param-sub-plan-name=Channel\sSubscription\s(mattknite);
            // msg-param-sub-plan=1000;
            // room-id=180859114;
            // subscriber=1;
            // system-msg=kristoff_it\sgifted\sa\sTier\s1\ssub\sto\sg_w1!;
            // tmi-sent-ts=1609457535209;
            // user-id=102701971;
            // user-type= :tmi.twitch.tv USERNOTICE #mattknite
            const meta = try parseMetaSubsetLinear(metadata, [_][]const u8{
                "display-name", // 0
                "login", // 1
                "msg-param-gift-months", // 2
                "msg-param-recipient-display-name", // 3
                "msg-param-recipient-user-name", // 4
                "msg-param-sub-plan", // 5
            });

            const months = try std.fmt.parseInt(usize, meta[2], 10);
            const tier = try parseSubTier(meta[5]);

            return ParseResult{
                .message = Chat.Message{
                    .login_name = meta[1],
                    .kind = .{
                        .sub_gift = .{
                            .sender_display_name = meta[0],
                            .months = months,
                            .tier = tier,
                            .recipient_display_name = meta[3],
                            .recipient_login_name = meta[4],
                        },
                    },
                },
            };
        } else if (std.mem.eql(u8, msg_type, "sub")) {
            const meta = try parseMetaSubsetLinear(metadata, [_][]const u8{
                "display-name", // 0
                "login", // 1
                "msg-param-sub-plan", // 2
            });

            const tier = try parseSubTier(meta[2]);

            return ParseResult{
                .message = Chat.Message{
                    .login_name = meta[1],
                    .kind = .{
                        .sub = .{
                            .display_name = meta[0],
                            .tier = tier,
                        },
                    },
                },
            };
        } else if (std.mem.eql(u8, msg_type, "resub")) {
            //  **UNRELIABLE** From the spec **UNRELIABLE**
            // @badge-info=;
            // badges=staff/1,broadcaster/1,turbo/1;
            // color=#008000;
            // display-name=ronni;
            // emotes=;
            // id=db25007f-7a18-43eb-9379-80131e44d633;
            // login=ronni;
            // mod=0;
            // msg-id=resub;
            // msg-param-cumulative-months=6;
            // msg-param-streak-months=2;
            // msg-param-should-share-streak=1;
            // msg-param-sub-plan=Prime;
            // msg-param-sub-plan-name=Prime;
            // room-id=1337;subscriber=1;
            // system-msg=ronni\shas\ssubscribed\sfor\s6\smonths!;
            // tmi-sent-ts=1507246572675;
            // turbo=1;
            // user-id=1337;
            // user-type=staff :tmi.twitch.tv USERNOTICE #dallas :Great stream -- keep it up!
            const meta = try parseMetaSubsetLinear(metadata, [_][]const u8{
                "display-name", // 0
                "emotes", // 1
                "login", // 2
                "msg-param-cumulative-months", // 3
                "msg-param-sub-plan", // 4
            });

            const tier = try parseSubTier(meta[4]);
            const count = try std.fmt.parseInt(usize, meta[3], 10);
            const emotes = try parseEmotes(meta[1], alloc);

            return ParseResult{
                .message = Chat.Message{
                    .login_name = meta[2],
                    .kind = .{
                        .resub = .{
                            .display_name = meta[0],
                            .count = count,
                            .tier = tier,
                            .time = time,
                            .resub_message = trailer,
                            .resub_message_emotes = emotes,
                        },
                    },
                },
            };
        } else {
            return error.UnknownUsernotice;
        }

        // } else if (std.mem.eql(u8, cmd, "PING")) {

        // } else if (std.mem.eql(u8, cmd, "PING")) {
        // } else if (std.mem.eql(u8, cmd, "PING")) {
    } else if (std.mem.eql(u8, cmd, "PING")) {
        return .ping;
    } else {
        return error.UnknownMessage;
    }
}

fn parseSubTier(data: []const u8) !Chat.Message.SubTier {
    if (data.len == 0) return error.MissingSubTier;
    return switch (data[0]) {
        'P' => .prime,
        '1' => .t1,
        '2' => .t2,
        '3' => .t3,
        else => error.BadSubTier,
    };
}

fn parseEmotes(data: []const u8, allocator: *std.mem.Allocator) ![]Chat.Message.Emote {
    // Small hack: count the dashes to know how many emotes
    // are present in the text.
    const count = std.mem.count(u8, data, "-");
    var emotes = try allocator.alloc(Chat.Message.Emote, count);
    errdefer allocator.free(emotes);

    var emote_it = std.mem.tokenize(u8, data, "/");
    var i: usize = 0;
    while (emote_it.next()) |e| {
        const colon_pos = std.mem.indexOf(u8, e, ":") orelse return error.NoColon;
        const emote_id = e[0..colon_pos];

        var pos_it = std.mem.tokenize(u8, e[colon_pos + 1 ..], ",");
        while (pos_it.next()) |pos| : (i += 1) {
            var it = std.mem.tokenize(u8, pos, "-");
            const start = blk: {
                const str = it.next() orelse return error.NoStart;
                break :blk try std.fmt.parseInt(usize, str, 10);
            };
            const end = blk: {
                const str = it.next() orelse return error.NoEnd;
                break :blk try std.fmt.parseInt(usize, str, 10);
            };

            if (it.rest().len != 0) return error.BadEmote;

            // result.emote_chars += end - start;
            emotes[i] = Chat.Message.Emote{
                .twitch_id = emote_id,
                .start = start,
                .end = end,
            };
        }
    }

    // Sort the array by start position
    std.sort.sort(Chat.Message.Emote, emotes, {}, Chat.Message.Emote.lessThan);
    for (emotes) |em| std.log.debug("{}", .{em});

    return emotes;
}

const Badge = struct {
    name: []const u8,
    count: usize,
};

fn parseBadge(data: []const u8) !Badge {
    var it = std.mem.tokenize(u8, data, "/");
    return Badge{
        .name = it.next().?, // first call will not fail
        .count = try std.fmt.parseInt(usize, it.rest(), 10),
    };
}

/// `keys` must be an array of strings
fn parseMetaSubsetLinear(meta: []const u8, keys: anytype) ![keys.len][]const u8 {
    // Given the starting fact that the Twitch IRC spec sucks ass,
    // we have an interesting conundrum on our hands.
    // Metadata is a series of key-value pairs (keys being simple names,
    // values being occasionally composite) that varies from message
    // type to message type. There's a few different message types
    // that we care about and each has a different set of kv pairs.
    // Unfortunately, as stated above, the Twitch IRC spec does indeed
    // suck major ass, and so we can't rely on it blindly, which means
    // that we can't just try to decode a struct and expect things to
    // go well.
    // Also, while we can make some assumptions about the protocol,
    // Twitch is going to make changes over time as it tries to refine
    // its product (after years of inaction lmao) to please the
    // insatiable Bezosaurus Rex that roams Twith's HQ.
    // Finally, one extra constraint comes from me: I don't want to
    // decode this thing into a hashmap. I would have written bork in
    // Perl if I wanted to do things that way.
    //
    // So, after this inequivocably necessary introduction, here's the
    // plan: we assume fields are always presented in the same order
    // (within each message type) and expect Twitch to add new fields
    // over time (fields that we don't care about in this version, that is).
    //
    // We expect the caller to provide the `keys` array sorted following
    // the same logic and we scan the tag list lineraly expecting to
    // match everything as we go. If we scan the full list and discover
    // we didn't find all fields, we then fall-back to a "scan everything"
    // strategy and print a warning to the logging system.
    // This will make the normal case O(n) and the fallback strat O(n^2).
    // I could sort and accept a O(nlogn) across the whole board, plus
    // maybe a bit of dynamic allocation, but hey go big or go home.
    //
    // Ah I almost forgot: some fields are present only when enabled, like
    // `emote-only` which is present when a message contains only emotes,
    // but disappears when there's also non-emote content. GJ Twitch!
    var values: [keys.len][]const u8 = undefined;
    var it = std.mem.tokenize(u8, meta, ";");

    // linear scan
    var first_miss: usize = outer: for (keys) |k, i| {
        while (it.next()) |kv| {
            var kv_it = std.mem.tokenize(u8, kv, "=");
            const meta_k = kv_it.next().?; // First call will always succeed
            const meta_v = kv_it.rest();
            if (std.mem.eql(u8, k, meta_k)) {
                values[i] = meta_v;
                continue :outer;
            }
        }

        // If we reach here we consumed all kv pairs
        // and couldn't find our key. Not good!
        break :outer i;
    } else {
        // Success: we found all keys in one go!
        return values;
    };

    // Fallback to bad search, but first complain about it.
    std.log.debug("Linear scan of metadata failed! Let the maintainers know that Gondor calls for aid!", .{});

    // bad scan
    outer: for (keys[first_miss..]) |k, i| {
        it = std.mem.tokenize(u8, meta, ";"); // we now reset every loop
        while (it.next()) |kv| {
            var kv_it = std.mem.tokenize(u8, kv, "=");
            const meta_k = kv_it.next().?; // First call will always succeed
            const meta_v = kv_it.rest();
            if (std.mem.eql(u8, k, meta_k)) {
                values[i] = meta_v;
                continue :outer;
            }
        }

        // The key is really missing.
        return error.MissingKey;
    }

    return values;
}
