# ModSecurity for NGINX

Builds the [ModSecurity](https://github.com/owasp-modsecurity/ModSecurity)
web application firewall and its NGINX connector from source on the
target host, installs the resulting dynamic module into the modules
directory the running NGINX was compiled to read, and writes a rule
configuration under `/etc/nginx/waf_rules`.

The role runs in six ordered phases, each consuming what the previous
one left behind: preconditions and build tree, dependencies, the
`libmodsecurity` build, the connector build, the rules, and the
toolchain cleanup. None of them stands alone — the phases share facts
and a build directory that only the first phase creates.

It installs no NGINX of its own, on purpose. The connector is compiled
against the source of the version already running on the host, and
NGINX refuses to load a module built from any other version, so
installing NGINX here would mean choosing the version the connector is
then locked to. That choice belongs to the
[install role](../install/README.md), which runs first.

> **Compiles from source and removes the toolchain.** The role
> downloads the ModSecurity release and the NGINX source onto the
> target, builds both, and then uninstalls `gcc`, `make`, `automake`
> and `git`. The removal is unconditional and does not check whether
> the host had those packages before the role ran, so anything
> unrelated that depended on them — configuration management that
> clones from `git`, a language runtime that builds native extensions
> — breaks after the first run. The build tree is deleted and
> recreated on every run, so a re-run re-downloads and recompiles
> everything and reports changes even when nothing about the firewall
> changed.

## Supported platforms

| Distribution | Versions | Dependency tasks |
| --- | --- | --- |
| AlmaLinux | 8, 9, 10 | `tasks/rhel/install_dependencies.yml` |
| CentOS | 8, 9, 10 | `tasks/rhel/install_dependencies.yml` |
| Debian | 11, 12 | `tasks/debian/install_dependencies.yml` |
| Oracle Linux | 8, 9, 10 | `tasks/rhel/install_dependencies.yml` |
| Red Hat Enterprise Linux | 8, 9, 10 | `tasks/rhel/install_dependencies.yml` |
| Rocky Linux | 8, 9, 10 | `tasks/rhel/install_dependencies.yml` |
| Ubuntu | 22.04, 24.04 | `tasks/debian/install_dependencies.yml` |

**The CI-tested platforms are Ubuntu 24.04 and AlmaLinux 10 only.** The
other rows share a package manager and a set of dependency names with
one of those two and are claimed on that basis, not on the basis of a
passing test.

Enterprise Linux starts at 8 because the dependency install goes
through `dnf`. From EL 9 the role also has to enable the builder
repository that `libmaxminddb-devel` lives in: `subscription-manager`
on subscribed Red Hat hosts, `dnf config-manager --set-enabled crb` on
the rebuilds. EL 8 and earlier get `geoip-devel` instead, which was
dropped from EL 9.

## Requirements

- **NGINX must already be installed**, with the binary on `PATH`. The
  role probes for it with `command -v nginx` and asserts on the result,
  so a host without NGINX fails on the first phase with
  `Nginx is not installed, please install nginx and retry again`. Run
  the [install role](../install/README.md) first, in the same play.
- The running NGINX version must have a matching source tarball
  published at `nginx.org`. The connector is built inside that tarball's
  tree, and a vendor build whose version string upstream never
  published fails the download. This is why the install role takes its
  Enterprise Linux packages from nginx.org.
- `become` privileges and `gather_facts: true`. The role reads
  `ansible_facts['distribution']`,
  `ansible_facts['distribution_major_version']`,
  `ansible_facts['architecture']` and
  `ansible_facts['processor_nproc']`.
- Outbound HTTPS from the target to `github.com` (the ModSecurity
  release tarball and the connector repository),
  `raw.githubusercontent.com` (the recommended configuration) and
  `nginx.org` (the NGINX source tarball).
- Roughly 2 GB free under `build_dir` and several minutes of CPU. The
  `libmodsecurity` compile is the longest step in the role by a wide
  margin, and `CFLAGS` is pinned to `-g -O0`, which keeps full debug
  symbols at the cost of a larger and slower library.
- On subscribed Red Hat hosts at EL 9 or later, an active subscription:
  the role enables CodeReady Builder through `subscription-manager`,
  which fails without one.

## Role variables

| Variable | Default | Description |
| --- | --- | --- |
| `build_dir` | `/tmp` | Parent of the build tree. The role creates `<build_dir>/modSecurity`, and deletes and recreates that subdirectory on every run. |
| `module_version` | `3.0.16` | ModSecurity release to build. Interpolated into both the download URL and the unpacked directory name, so it has to match an upstream release tag exactly, without the leading `v`. |
| `detection_only` | `false` | When `true`, no `SecDefaultAction` deny rule is appended, so a rule match is logged and the request is still served. |
| `supported_distribution` | the seven names above | Distributions the platform assertion accepts. |
| `target_platform` | `''` | Internal. Set to `rhel` or `debian` from the distribution fact before the dependency phase; not an operator setting. |

`build_dir`, `module_version` and `detection_only` are declared in
`vars/main.yml`, not in `defaults/`. Role vars outrank inventory, so
setting any of them in `group_vars` or `host_vars` has no effect and
fails silently. Override them as role parameters on the `roles:` entry,
or with `-e` on the command line.

`/tmp` is the default `build_dir` and two common host policies break
it: a `/tmp` mounted `noexec` fails the `configure` and `make` steps,
which execute scripts from inside the build tree, and a `/tmp` swept on
a schedule can remove the ModSecurity source tree between the build
phase and the rules phase that copies `unicode.mapping` back out of it.
Point `build_dir` at a normal directory on hosts with either policy.

> **Test before you enforce.** With `detection_only: false` — the
> default — anything the rules flag is answered with `403`, which can
> break a working site on the first request. Run with
> `detection_only: true` first, watch
> `/var/log/mod_security/audit/modsec_audit.log`, and only then
> enforce.

`detection_only` is narrower than its name suggests. It gates one line:
the `SecDefaultAction` appended at the end of `modsecurity.conf`. The
engine itself is armed either way — the role rewrites upstream's
`SecRuleEngine DetectionOnly` to `SecRuleEngine On` unconditionally, so
rules are always evaluated and always logged.

## Usage

The example below builds ModSecurity `3.0.16` against the NGINX the
install role put on the host, in logging-only mode:

```yaml
- name: Nginx ModSecurity
  hosts: all # Make sure to select a machine based on your inventory
  become: yes
  gather_facts: yes
  any_errors_fatal: yes
  roles:
  - name: hasnimehdi91.secure_nginx.install
  - name: hasnimehdi91.secure_nginx.mod_security
    vars:
      detection_only: true
```

To build a different release, or to keep the build off `/tmp`:

```yaml
  - name: hasnimehdi91.secure_nginx.mod_security
    vars:
      build_dir: /var/tmp
      module_version: "3.0.16"
      detection_only: false
```

## Results

| Path | What lands there |
| --- | --- |
| `<modules path>/ngx_http_modsecurity_module.so` | The compiled connector. The directory is scraped from `nginx -V`, so it follows the packaging — `/usr/lib/nginx/modules` on the Debian family, `/usr/lib64/nginx/modules` on Enterprise Linux. |
| `/etc/nginx/extras/mod-http-modsecurity.conf` | The `load_module` directive pointing at that module. |
| `/etc/nginx/nginx.conf` | Gains `include /etc/nginx/extras/*.conf;`, inserted before the `events` block because `load_module` is only valid in the main context. |
| `/etc/nginx/waf_rules/modsecurity.conf` | Upstream's recommended configuration, with `SecRuleEngine On`, the audit log paths rewritten, and — unless `detection_only` is `true` — a `SecDefaultAction` that answers a match with `403`. |
| `/etc/nginx/waf_rules/unicode.mapping` | The character mapping the transformation rules need, copied out of the built source tree so it matches the library version. |
| `/etc/nginx/waf_rules/main.conf` | The role's entry point: one `Include` line pulling in `modsecurity.conf`. |
| `/var/log/mod_security/audit/` | The audit log tree, mode `0700` — recorded request bodies routinely contain credentials and session tokens. |
| System library path | `libmodsecurity`, installed by `make install`, with the dynamic linker cache refreshed. |

What lands in `modsecurity.conf` is upstream's recommended engine
configuration. It is not an attack rule set: the
[OWASP Core Rule Set](https://github.com/coreruleset/coreruleset) is
not installed by this role, and adding it is a separate step.

### Switching the WAF on

> **The module is loaded and inert.** The role never emits
> `modsecurity on;` or `modsecurity_rules_file` into any `http`,
> `server` or `location` block, so after it finishes NGINX has the
> module loaded, the rules on disk, and no traffic being inspected.
> Closing that gap is the operator's job today.

Add both directives to your own site configuration — in `http` to
cover every virtual host, or in a single `server` block to scope it:

```nginx
http {
    modsecurity on;
    modsecurity_rules_file /etc/nginx/waf_rules/main.conf;
}
```

Then check the configuration and restart. A restart rather than a
reload: `load_module` is only read on a full start.

```bash
nginx -t && systemctl restart nginx
```

The restart is not optional even if you had already enabled the
directives on a previous run. The role defines `Handler | Restarting
nginx` and `Handler | Testing the nginx configuration` but never
notifies either, so the running process keeps serving without the
module until something restarts it.

## Testing

This role is exercised by the disposable-VM integration harness,
after the install role, on Ubuntu 24.04 and AlmaLinux 10. See the
[tests documentation](../../tests/README.md) for how to run it and the
[integration test documentation](../../tests/integration/README.md) for
the prerequisites.

The assertions are structural: that the module was built and installed
at the scraped path, that the `load_module` line and the include are in
place, that `nginx -t` passes, that the rule files exist, and that the
toolchain is gone. Nothing asserts that a request is blocked, because
with no `modsecurity on;` anywhere on the host, none is.

## Links

- Repository: <https://github.com/Black-Cockpit/ansible-secure-nginx>
- Issues: <https://github.com/Black-Cockpit/ansible-secure-nginx/issues>
- ModSecurity: <https://github.com/owasp-modsecurity/ModSecurity>
- ModSecurity NGINX connector:
  <https://github.com/owasp-modsecurity/ModSecurity-nginx>
- ModSecurity reference manual:
  <https://github.com/owasp-modsecurity/ModSecurity/wiki>
- OWASP Core Rule Set: <https://github.com/coreruleset/coreruleset>
