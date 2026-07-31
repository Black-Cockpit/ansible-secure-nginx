# Integration test harness

Prove the `install` and `mod_security` roles against a real system: a
disposable VirtualBox VM is booted, both roles are run against it, and
the result is asserted. Everything is driven by `run.sh`.

> **Every run destroys its VM.** The default cycle ends in
> `vagrant destroy -f`, so nothing survives it. A run invoked with
> `keep` leaves the machine behind instead, and the next run of that
> entry then boots the machine it left rather than a clean one —
> destroy it by hand before trusting another result from it.

## Requirements

Install on the host:

- VirtualBox
- Vagrant
- Ansible (`ansible-playbook` on `PATH`)
- Python 3 with `PyYAML` — `run.sh` reads the matrix with it

The roles compile ModSecurity and the nginx source on the guest, so a
run needs the host to spare 4 GB of RAM and 4 cores for the duration,
plus roughly 8 GB of disk per machine.

### Free VT-x for VirtualBox (KVM hosts)

VirtualBox and KVM cannot both own the CPU's virtualization (VT-x) at
the same time. On a host where the KVM modules are loaded, VirtualBox
fails to boot the VM with:

```text
VBoxManage: error: VT-x is being used by another hypervisor (VERR_VMX_IN_VMX_ROOT_MODE)
```

Unload the KVM module before running the harness (Intel shown; use
`kvm_amd` on AMD):

```bash
sudo modprobe -r kvm_intel
```

It is safe to unload when nothing is using KVM (no running
libvirt/QEMU guests) and it is reversible with
`sudo modprobe kvm_intel`. If the unload reports the module is in use,
stop the KVM guests first (for example
`sudo systemctl stop libvirtd`). The modules can reload on reboot or
when libvirt starts, so re-check before each session.

## Run it

```bash
cd tests/integration
./run.sh ubuntu2404
```

That command runs the whole cycle for the `ubuntu2404` entry:

1. `vagrant up` — boot the box and grow its root filesystem.
2. Install — run the `install` role, then the `mod_security` role.
3. Verify — assert the result.
4. Destroy the VM.

Expect 10 to 20 minutes per entry. Almost all of it is the two source
compiles inside the guest; the harness itself is idle for most of the
run.

### Other forms

```bash
./run.sh ubuntu2404 keep   # run, keep the VM for inspection (vagrant ssh)
./run.sh all               # run every entry, print a pass/fail summary
./run.sh                   # print usage and list the entries
```

A run that fails before the verify phase leaves its VM behind on
purpose, so the half-built machine can be inspected. Clean it up with
`vagrant destroy -f <entry>` when you are done with it.

## The matrix

| Entry | Box | Firmware |
| --- | --- | --- |
| `ubuntu2404` | `bento/ubuntu-24.04` | bios |
| `alma10` | `almalinux/10` | efi (default) |

Both entries run with 4 GB of RAM and 4 CPUs, and both grow their root
filesystem before the roles run. These two are what the collection is
tested on. The roles accept a wider list of distributions — RHEL,
CentOS, Rocky, Oracle Linux and Debian all pass the platform
assertions — but nothing in this harness exercises them.

## What is asserted

`playbooks/verify.yml` makes thirteen structural assertions, grouped:

| Group | Assertion |
| --- | --- |
| Installation | `nginx -v` exits 0 and reports a version |
| Installation | the `nginx` package is present in the package facts |
| Module | `ngx_http_modsecurity_module.so` exists, and is not empty, in the modules directory scraped from `nginx -V` |
| Module | `/etc/nginx/extras/mod-http-modsecurity.conf` loads that module by that path |
| Module | `/etc/nginx/nginx.conf` includes `/etc/nginx/extras/*.conf` above the `events` block |
| Module | `nginx -t` exits 0 |
| Rules | `/etc/nginx/waf_rules/modsecurity.conf` sets `SecRuleEngine On` |
| Rules | `SecAuditLogStorageDir` points at `/var/log/mod_security/audit` |
| Rules | a `SecDefaultAction` denies with 403 — skipped when the entry sets `detection_only: true` |
| Rules | `/etc/nginx/waf_rules/unicode.mapping` exists |
| Rules | `/etc/nginx/waf_rules/main.conf` exists |
| Cleanup | `gcc`, `make`, `automake` and `git` are absent from the package facts |
| Service | nginx restarts, stays running, and its effective configuration loads the module |

The `nginx -t` assertion is the load-bearing one. Everything before it
proves files are in the right places; it is the only check that proves
the running binary accepts the module those files describe. A
connector compiled against a different nginx version, or compiled
without `--with-compat`, fails exactly there and nowhere earlier.

The service group restarts nginx itself. That restart is the harness
compensating for a gap in the `mod_security` role, which defines a
restart handler and never notifies it: without the restart, the
process still running is the one that started before the module was
installed.

### Known gap: no functional WAF test

There is no assertion that sends an attack payload and expects `403`,
and that is deliberate. The `mod_security` role loads the module and
writes the rule files, but never emits `modsecurity on;` or
`modsecurity_rules_file` into an nginx `http`, `server` or `location`
context, so the engine inspects no traffic on a correctly configured
host. A functional assertion would fail against a run in which every
role did exactly what it promises.

The functional test belongs with the change that switches the WAF on,
so that the assertion and the behaviour arrive together. Until then
this harness asserts structure only.

## Add a platform

Add an entry to `platforms.yml`. The machine definition, the harness
entry list and the generated Makefile targets are all read from that
file, so a new distribution or version is a matrix row and nothing
else — no changes to `run.sh`, the `Vagrantfile` or the playbooks.

```yaml
  rocky10:
    box: cloud-image/rocky-10
    memory: 4096
    cpus: 4
    disk_size: 20GB
```

Two fields decide how the machine boots and how much room it has:

| Field | Meaning |
| --- | --- |
| `firmware` | `efi` (default) or `bios`. It must match how the box's disk image boots; the wrong value hangs the boot rather than failing it. |
| `disk_size` | Present means "run `provision/grow_disk.sh` on this entry". The virtual disk is never resized — only the root partition inside a box that ships more disk than it partitions. |

`detection_only` is optional and defaults to `false`. Setting it
`true` on an entry runs `mod_security` in logging mode and drops the
blocking-action assertion from the verification for that entry only.

## Layout

```text
tests/integration/
  .gitignore           run output: reports/, *.ssh_config, collections/
  README.md            this file
  Vagrantfile          one machine per matrix entry
  ansible.cfg          roles_path, host key checking, pipelining
  platforms.yml        the matrix — single source of truth
  run.sh               the driver
  playbooks/
    install.yml        run install, then mod_security
    verify.yml         assert the result
  provision/
    grow_disk.sh       grow the root filesystem into the free space
```

A run also creates `reports/`, holding the per-entry SSH configuration
`run.sh` builds from `vagrant ssh-config` and hands to
`ansible-playbook`. It is regenerated every run and never committed.

## Links

- Collection tests overview: [../README.md](../README.md)
- ModSecurity: <https://github.com/owasp-modsecurity/ModSecurity>
- ModSecurity nginx connector:
  <https://github.com/owasp-modsecurity/ModSecurity-nginx>
- Vagrant: <https://developer.hashicorp.com/vagrant/docs>
