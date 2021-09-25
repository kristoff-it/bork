id: 1jewxv8y57bejcvi9onjm0uetewi8rn3gwrttjy8pta40s03
name: bork
bin: True
provides: ["bork"]
license: MIT
description: A Twitch chat client for the terminal.
dev_dependencies:
  - src: git https://github.com/nektro/iguanaTLS # temp, waiting on pr

  - src: local zbox forks/zbox
  - src: git https://github.com/frmdstryr/zig-datetime
  - src: git https://github.com/Hejsil/zig-clap branch-zig-master
  # - src: git https://github.com/alexnask/iguanaTLS
  - src: git https://github.com/truemedian/hzzp
  - src: git https://github.com/leroycep/zig-tzif
  - src: git https://github.com/jecolon/ziglyph
