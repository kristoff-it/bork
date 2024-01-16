# bork
*A TUI chat client tailored for livecoding on Twitch, currently in alpha stage.*

<img src=".github/bork.png"  align="right" width="350px"/>

### Main features
- Displays Twitch emotes in the terminal, **including your own custom emotes!**  
- Understands Twitch-specific concepts (subcriptions, gifted subs, ...). 
- Displays badges for your subs, mods, etc.
- Supports clearing chat and deletes messages from banned users. 
- Click on a message to highlight it and let your viewers know who you're relpying to. 

## Why?
Many livecoders show their chat feed on stream. It makes sense for the livecoding genre, since the content is text-heavy and you want viewers to be aware of all social interactions taking place, even when they put the video in full screen mode.

It's also common for livecoders to use terminal applications to show chat on screen, partially out of convenience, partially because of the appeal of the terminal aestetic. Unfortunately the most common solution, irssi, is an IRC client that can show basic Twitch messages, but that doesn't understand any of the Twitch-specific concepts such as subs, sub gifts, highlighted messages, etc.

Bork is designed to replace irssi for this usecase by providing all the functionality that isn't present in a general-purpose IRC client.

## Requirements
To see Twitch emotes in the terminal, you will need [Kitty](https://github.com/kovidgoyal/kitty), Ghostty, or any terminal emulator that supports the Kitty graphics protocol.
Bork will otherwise fallback to showing the emote name (eg "Kappa").

Bork also temporarily has a dependency on `curl`. Bork will try to invoke it to check the validity of your Twitch OAuth token. This requirement will go away in the future.

## Obtaining bork
Get a copy of bork from [the Releases section of GitHub](https://github.com/kristoff-it/bork/releases) or build it yourself (see below).

## Usage
Run `bork start` to run the main bork instance. On first run you will be greeded by a config wizard.

Run `bork` (without subcommand) for the main help menu.

Supported subcommands:

- `start` runs the main bork instance
- `quit` quits the main bork instance
- `afk` shows an afk window in bork with a countdown
- `reconnect` makes bork to reconnect
- `send` sends a message
- `links` obtains a list of links sent to chat
- `ban` bans a user (also deletes all their messages)
- `unban` unbans a user
- `version` prints the version

## Build
Requires a **very** recent version of Zig, as bork development tracks Zig master.

Run `zig build` to obtain a debug build of bork.

Run `zig build -Doptimize=ReleaseFast` to obtain a ReleaseFast build of bork.

## Demo
https://youtu.be/Px8rVB3ZpKA
