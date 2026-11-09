# Demo assets

- `slop-demo.mp4`: 41-second captioned video, 1280 × 960, H.264, no audio.
- `slop-demo.gif`: looping 960 × 720 preview for the repository README.
- `poster.png`: still preview.

The screens come from the real plugin running in Neovim with Gitsigns inside an
isolated Rex session. GitHub requests use `tests/gh`, the repository's offline
fixture. No real PR or review was created. The video labels this simulation.

The walkthrough starts a PR review, opens quickfix, jumps to the next hunk,
writes and saves a Markdown comment, edits a two-line suggestion, opens the
draft list, and submits both comments with a summary. The capture script checks
the fixture state to confirm both comments and the summary were submitted.

`captures/` and `scenes.json` preserve the styled terminal screens and timings.
To render them again, install `pillow` and `imageio-ffmpeg`, then run:

```sh
DEMO_FONT=/path/to/JetBrainsMono.ttf python3 demo/render.py
```

The renderer uses JetBrains Mono (SIL Open Font License), downloaded separately;
the font is not bundled. `record.py` documents the Rex input sequence used for
the capture. It expects an isolated `slop-demo` Rex session, the sample file
`pagination.lua`, and fixture state at `/tmp/slop-video-repo/github.json`.
`init.lua` records the local Neovim configuration used for this capture; adjust
its checkout and Gitsigns paths before using it on another machine.
