# frr-image-builder

Builds a PNETLAB-ready FRR docker image from an upstream
[quay.io/frrouting/frr](https://quay.io/repository/frrouting/frr) image.

By default FRR's upstream image ships with every daemon disabled except
`zebra`, `staticd` and `mgmtd`, and no `vtysh.conf`. This repo turns that
into a one-line build step: pull the tag you want, enable the daemons you
need, enable `vtysh`, and tag the result for both local PNETLAB use and
Docker Hub (`africodes/frrouting`).

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
     `vtysh` doesn't warn about a missing config file on every invocation.
5. Tags the result (`africodes/frrouting:<version>` by default).
6. Optionally `docker push`es it (`--push`).

Per-daemon config files (`/etc/frr/bgpd.conf`, etc.) are intentionally
*not* pre-created — FRR's own init script (`daemon_prep` in
`frrcommon.sh`) creates them automatically, with correct ownership, the
first time a container from the image starts.

## Using the image in PNETLAB

PNETLAB's docker node type (`/opt/unetlab/html/devices/docker/device_docker.php`)
starts containers by referencing a local image tag directly — it doesn't
need a Dockerfile or registry access on the PNETLAB host itself, just the
tag present in `docker image ls`. Point (or create) a docker node template
at the tag this script produces, e.g. `africodes/frrouting:10.7.0`, or
pull it from Docker Hub on any other PNETLAB host once pushed.

## Files

- `Dockerfile` — the actual build steps (daemons, vtysh).
- `build.sh` — CLI wrapper: argument parsing, validation, pull, build, push.
- `daemons-all.txt` — canonical list of valid/default daemon names.
