# frr-image-builder

Builds a PNETLAB-ready FRR docker image from an upstream
[quay.io/frrouting/frr](https://quay.io/repository/frrouting/frr) image.

By default FRR's upstream image ships with every daemon disabled except
`zebra`, `staticd` and `mgmtd`, and no `vtysh.conf`. This repo turns that
into a one-line build step: pull the tag you want, enable the daemons you
need, enable `vtysh`, and tag the result for both local PNETLAB use and
Docker Hub (`africodes/frrouting`).

Pre-built images are published at
[hub.docker.com/repository/docker/africodes/frrouting/general](https://hub.docker.com/repository/docker/africodes/frrouting/general) —
pull one directly instead of building if you just need the image:

```bash
docker pull africodes/frrouting:10.7.0
```

## Usage

```bash
./build.sh <tag_or_ref> [options]
```

`<tag_or_ref>` is either a bare version (`10.7.0`, assumed to be
`quay.io/frrouting/frr:10.7.0`) or a full image reference
(`quay.io/frrouting/frr:10.7.0`, or any other registry/repo entirely).

The resulting image is tagged `africodes/frrouting:<version>` by default.

### Examples

```bash
# Pull 10.7.0, enable every daemon (default), tag as africodes/frrouting:10.7.0
./build.sh 10.7.0

# Same, but spelling out the full upstream reference
./build.sh quay.io/frrouting/frr:10.7.0

# Only enable a subset of daemons
./build.sh 10.7.0 --daemons "bgpd ospfd ospf6d isisd ldpd pimd"

# Use a daemon list from a file (one name per line, # comments allowed)
./build.sh 10.7.0 --daemons-file my-daemons.txt

# Tag the output differently (e.g. keep the older frrouting:<version> convention)
./build.sh 10.7.0 -o frrouting:10.7.0

# Build and push to Docker Hub in one step (requires a prior `docker login -u africodes`)
./build.sh 10.7.0 --push

# See exactly what would happen without touching docker
./build.sh 10.7.0 --dry-run

# List every daemon name the script knows about
./build.sh --list-daemons
```

Run `./build.sh --help` for the full option list.

## Pushing to Docker Hub

`--push` runs `docker push` after a successful build. It assumes you've
already authenticated in the current shell:

```bash
docker login -u africodes
```

Use a Docker Hub **Personal Access Token** (Account Settings → Personal
access tokens, Read & Write scope) as the password, not your account
password — required if 2FA is enabled, and preferred either way. The
script never touches credentials itself; it just calls `docker push` and
lets the docker CLI use whatever session `docker login` already set up.

## What it does

1. Resolves the image reference and output tag.
2. Resolves the daemon list (default: every daemon in
   [`daemons-all.txt`](daemons-all.txt) except `zebra`/`staticd`/`mgmtd`,
   which FRR always starts regardless of the daemons file) and validates
   it against that same known-daemon list, to catch typos before building.
3. `docker pull`s the upstream image (skip with `--no-pull`).
4. `docker build`s [`Dockerfile`](Dockerfile), which:
   - flips the requested daemons from `<daemon>=no` to `<daemon>=yes` in
     `/etc/frr/daemons`,
   - sets `vtysh_enable=yes`,
   - creates `/etc/frr/vtysh.conf` (owned `frr:frrvty`, mode `0640`) so
     `vtysh` doesn't warn about a missing config file on every invocation,
   - appends an auto-start hook to `/root/.bashrc` so consoling into the
     container drops straight into `vtysh` instead of a plain shell (see
     below).
5. Tags the result (`africodes/frrouting:<version>` by default).
6. Optionally `docker push`es it (`--push`).

Per-daemon config files (`/etc/frr/bgpd.conf`, etc.) are intentionally
*not* pre-created — FRR's own init script (`daemon_prep` in
`frrcommon.sh`) creates them automatically, with correct ownership, the
first time a container from the image starts.

## Consoling straight into vtysh

PNETLAB's docker node type attaches the console with `docker exec -it
<container> /bin/bash`, which sources `~/.bashrc` for an interactive
shell. The image appends a hook there that auto-starts `vtysh` on
console attach — so opening the node's console lands you directly in the
FRR CLI, no need to type `vtysh` first.

It's a plain foreground command, not an `exec` replacement of the shell,
so `exit` from vtysh drops you into a real root bash shell instead of
disconnecting — useful if you need `ip addr`, package tools, log files,
etc. `exit` again from that shell ends the console session as normal.

## Using the image in PNETLAB

PNETLAB's docker node type (`/opt/unetlab/html/devices/docker/device_docker.php`)
starts containers by referencing a local image tag directly — it doesn't
need a Dockerfile or registry access on the PNETLAB host itself, just the
tag present in `docker image ls`.

Rather than picking the generic "Docker" node type and typing the image
tag in by hand every time, install the dedicated **FRRouting** node
template in [`pnetlab-template/`](pnetlab-template):

```bash
./pnetlab-template/install.sh
```

This copies `frrouting.yml` into PNETLAB's template directories
(`html/templates/intel`, `html/templates/amd`, `html/templates/device`).
PNETLAB auto-discovers node templates by scanning those directories
(`init.php`), and — for docker-type templates specifically — only shows
one as enabled in the "Add a node" dialog once a locally present image
tag contains the template's filename (`getTemplates()` in
`includes/functions.php` runs `docker images | grep frrouting`). So the
FRRouting entry lights up automatically as soon as `./build.sh` has
produced any `*frrouting*` tag — no manual template enabling needed. This
mirrors how the built-in cEOS template works (`templates/*/ceos.yml`),
except FRR needs no custom PHP device class (`devices/docker/device_ceos.php`
handles Arista-specific env vars/mounts) — the plain `device_docker.php`
already does everything FRR needs (standard bridge networking, telnet
console into a shell), so the template is YAML-only.

Defaults baked into the template: 4 Ethernet interfaces, 512MB RAM,
`--privileged` docker options (needed for the routing daemons to manage
interfaces/routes), telnet console. All are editable per-node after
adding it, same as any other node type.

You will still need to type the exact image tag (e.g.
`africodes/frrouting:10.7.0`) into the "Image" field when adding a node —
PNETLAB doesn't offer a tag picker, just free text validated against
what's locally available.

## Keeping Docker Hub up to date automatically

[`.github/workflows/build-and-push.yml`](.github/workflows/build-and-push.yml)
runs weekly (Mondays 06:00 UTC) and on manual dispatch:

1. Resolves a target version — either the input given to a manual run, or
   (on the schedule, and on a manual run with no input) the latest release
   from [FRRouting/frr](https://github.com/FRRouting/frr/releases) on
   GitHub.
2. Checks whether that version already exists as an `africodes/frrouting`
   tag on Docker Hub. Scheduled/auto-detected runs skip the build if it's
   already there; a manual run with an explicit `version` input always
   rebuilds and pushes, so you can re-run it after changing
   `daemons-all.txt` or the `Dockerfile` without waiting for a new FRR
   release.
3. If a build is needed, logs into Docker Hub and runs
   `./build.sh <version> --push`.

**Required repo secrets** (Settings → Secrets and variables → Actions):

- `DOCKERHUB_USERNAME` — `africodes`
- `DOCKERHUB_TOKEN` — a Docker Hub Personal Access Token with Read & Write
  scope (a separate token from the one used for interactive `docker
  login` on this machine is best practice, so either can be revoked
  independently).

Trigger a manual run from the Actions tab, or via `gh workflow run
"Build and push FRR image" -f version=10.7.0`.

## Files

- `Dockerfile` — the actual build steps (daemons, vtysh).
- `build.sh` — CLI wrapper: argument parsing, validation, pull, build, push.
- `daemons-all.txt` — canonical list of valid/default daemon names.
- `pnetlab-template/` — the FRRouting PNETLAB node template and its installer.
- `.github/workflows/build-and-push.yml` — CI to auto-build/push new FRR releases.
