# pino-bkg

Pinokio as a small, always-on home server, reached through **Pinokio's own web
UI** over a [bore](https://github.com/ekzhang/bore) tunnel — not through the
streamed X11 desktop.

This repository packages everything needed to run it on a home server with
Docker or Podman:

- **Pinokio's web UI** (served by its kernel on `127.0.0.1:42000`) is put
  behind an nginx reverse proxy with HTTP basic auth and exposed on port
  `3002`. The tunnel publishes *that*, so the UI works in any browser, on
  phones, and without streaming a desktop.
- **The host GPU** is passed into the container through the NVIDIA container
  toolkit (`--gpus all`), and the stock `app.disableHardwareAcceleration()`
  call is patched out so Electron actually uses it.
- **Stability fixes** for two upstream bugs (see below).

## Layout

```
Dockerfile                       extends joly0/pinokio-docker
compose.yaml                     Pinokio + bore
install.sh                       prerequisites, .env, build, start
start.sh                         up/down/logs/tunnel wrapper
scripts/tunnel-url.sh            print the public URL
.env.example                     configuration template
root/                            files copied into the image
  custom-cont-init.d/            installs the nginx UI proxy at boot
  etc/pinokio/ui-proxy.conf      the nginx server block
  usr/bin/start-pinokio.sh       single-instance launcher (GPU on, mode=full)
  usr/bin/wrapped-pinokio        supervisor (restart on exit)
patches/patch-asar.js            build-time app.asar patcher
```

## Requirements

- A 64-bit Linux host (amd64).
- Docker with the Compose plugin, **or** Podman with `podman-compose`.
- Optional but recommended: an NVIDIA GPU with the
  [NVIDIA container toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
  installed. Without a GPU, remove the `deploy:` block from `compose.yaml`.
- Disk space for Pinokio's apps and models (often tens to hundreds of GB).

## Install

```bash
git clone https://github.com/bkg-zig/pino-bkg.git
cd pino-bkg
./install.sh
```

`install.sh` checks the runtime and GPU, creates `config/` and `.env`
(generating a password if you have not set one), builds the image, and starts
the stack. There is deliberately **no hard minimum disk space**: it reports the
free space in the data directory and continues.

To pin a specific Pinokio release, set `PINOKIO_VERSION` (e.g. `8.2.0`) in
`.env` before installing.

## Use

```bash
./scripts/tunnel-url.sh     # print the public https URL
./start.sh                  # up (detached) + print URL
./start.sh logs -f bore     # follow the tunnel
./start.sh down             # stop
```

Open the printed URL and sign in with `CUSTOM_USER` / `PASSWORD` from `.env`.

Set `BORE_PORT` in `.env` to a fixed public port so the URL survives
reconnects (bore.pub may not have your port free; `0` means random).

## What is patched, and why

Both fixes are applied to `app.asar` at build time by
`patches/patch-asar.js`:

1. **GPU acceleration.** The stock Linux `main.js` calls
   `app.disableHardwareAcceleration()`, which forces SwiftShader. The call is
   neutralised so Electron uses the passed-through GPU.

2. **Local-sharing proxy crash.** `pinokiod`'s `lproxy.js` does
   `proxy.listen(port)` with a fixed port (`PINOKIO_SHARE_LOCAL_PORT`).
   Starting a *second* app that also wants local sharing throws `EADDRINUSE`,
   which is uncaught and kills the whole Pinokio kernel. The patch makes
   `listen()` fall back to a free port instead.

`lsof` is installed as well: Pinokio's own port-conflict detection shells out
to it and errors out when it is missing.

## Notes

- The desktop on ports `3000`/`3001` is still running inside the container and
  is reachable on your LAN. It is just not what the tunnel publishes.
- Basic auth is the only protection on the public URL. Pinokio can run
  arbitrary code in its apps, so treat the password like a root password and
  prefer a private bore server (`BORE_SERVER`) for anything long-lived.
