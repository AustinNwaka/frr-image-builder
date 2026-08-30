# frr-image-builder

Builds a PNETLAB-ready FRR docker image from an upstream
[quay.io/frrouting/frr](https://quay.io/repository/frrouting/frr) image.

By default FRR's upstream image ships with every daemon disabled except
`zebra`, `staticd` and `mgmtd`, and no `vtysh.conf`. This repo turns that
into a one-line build step: pull the tag you want, enable the daemons you
need, enable `vtysh`, and tag the result the way PNETLAB's docker node
type expects (a plain local image tag such as `frrouting:10.7.0`).

## Usage

```bash
./build.sh <tag_or_ref> [options]
```

`<tag_or_ref>` is either a bare version (`10.7.0`, assumed to be
`quay.io/frrouting/frr:10.7.0`) or a full image reference
(`quay.io/frrouting/frr:10.7.0`, or any other registry/repo entirely).

The resulting image is tagged `frrouting:<version>` by default, matching
the existing convention already in use on this host (`frrouting:10.4.0`).

### Examples

```bash
# Pull 10.7.0, enable every daemon (default), tag as frrouting:10.7.0
./build.sh 10.7.0

# Same, but spelling out the full upstream reference
./build.sh quay.io/frrouting/frr:10.7.0

# Only enable a subset of daemons
./build.sh 10.7.0 --daemons "bgpd ospfd ospf6d isisd ldpd pimd"

# Use a daemon list from a file (one name per line, # comments allowed)
./build.sh 10.7.0 --daemons-file my-daemons.txt

# Tag the output differently
./build.sh 10.7.0 -o frrouting-lab:10.7.0

# See exactly what would happen without touching docker
./build.sh 10.7.0 --dry-run

# List every daemon name the script knows about
./build.sh --list-daemons
```

Run `./build.sh --help` for the full option list.

## What it does

1. Resolves the image reference and local output tag.
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
5. Tags the result locally (`frrouting:<version>` by default).

Per-daemon config files (`/etc/frr/bgpd.conf`, etc.) are intentionally
*not* pre-created — FRR's own init script (`daemon_prep` in
`frrcommon.sh`) creates them automatically, with correct ownership, the
first time a container from the image starts.

## Using the image in PNETLAB

PNETLAB's docker node type (`/opt/unetlab/html/devices/docker/device_docker.php`)
starts containers by referencing a local image tag directly — it doesn't
need a Dockerfile or registry access on the PNETLAB host itself, just the
tag present in `docker image ls`. Point (or create) a docker node template
at the tag this script produces, e.g. `frrouting:10.7.0`.

## Files

- `Dockerfile` — the actual build steps (daemons, vtysh).
- `build.sh` — CLI wrapper: argument parsing, validation, pull, build.
- `daemons-all.txt` — canonical list of valid/default daemon names.
