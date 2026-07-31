# NGINX installation

Installs NGINX and leaves the service enabled and started. The role
checks the target's distribution against a list it has been written
for, then hands the run to one of two paths — `apt` on the Debian
family, `dnf` on the Enterprise Linux family. There is nothing else to
it: this role installs a web server and gets out of the way.

The package source is not the same on both paths, and that is
deliberate. Enterprise Linux takes NGINX from the official nginx.org
stable repository; the Debian family installs the distribution's own
package.

> **Changes where NGINX comes from on Enterprise Linux.** The role
> writes `/etc/yum.repos.d/nginx.repo`, overwriting any file already at
> that path, and configures the upstream nginx.org repository with
> `module_hotfixes=true` so DNF's modular filtering stops hiding it.
> An NGINX already installed from AppStream is left in place — the
> install uses `state: present`, not `latest` — but the next
> `dnf upgrade` on that host will move it to the upstream package.
> Nothing on the Debian path is affected.

## Why the package source matters

The `mod_security` role compiles an NGINX connector module against the
source tarball for the version running on the host, downloaded from
nginx.org by version number. NGINX refuses to load a dynamic module
built from any other version, so the connector build only works when
`nginx.org` publishes a tarball whose version string matches the
installed package exactly.

Vendor builds are where that breaks. They carry patch suffixes, and the
Enterprise Linux rebuilds ship version numbers upstream never
published, so there is no tarball to match and the connector build
fails on a 404. Taking the binary from the same origin as the source
keeps the two in step — which is what the Enterprise Linux path does.

The Debian path deliberately does not do this. Switching it to
nginx.org would replace the NGINX build on every host already running
that path, which is a change of behaviour rather than a fix. The same
version-mismatch risk therefore still applies on Debian and Ubuntu when
the vendor's version string is not one nginx.org ever published.

## Supported platforms

| Distribution | Versions | Path | Package source |
| --- | --- | --- | --- |
| AlmaLinux | 8, 9, 10 | `tasks/rhel.yml` | nginx.org stable |
| CentOS | 8, 9, 10 | `tasks/rhel.yml` | nginx.org stable |
| Debian | 11, 12 | `tasks/debian.yml` | distribution archive |
| Oracle Linux | 8, 9, 10 | `tasks/rhel.yml` | nginx.org stable |
| Red Hat Enterprise Linux | 8, 9, 10 | `tasks/rhel.yml` | nginx.org stable |
| Rocky Linux | 8, 9, 10 | `tasks/rhel.yml` | nginx.org stable |
| Ubuntu | 22.04, 24.04 | `tasks/debian.yml` | distribution archive |

**The CI-tested platforms are Ubuntu 24.04 and AlmaLinux 10 only.** The
other rows share a package manager and a repository layout with one of
those two and are claimed on that basis, not on the basis of a passing
test.

Enterprise Linux starts at 8 because the install goes through `dnf` and
relies on `module_hotfixes`, and neither exists on 7.

Oracle Linux is accepted by the platform assertion and dispatched to
the Enterprise Linux path, but it needs one check before you trust it:
the repository URL the role writes contains `$releasever`, which
expands from the release package rather than from the EL major version.
On a distribution that versions itself differently — Oracle Linux above
all — confirm the URL that produces resolves before treating the
platform as supported.

## Requirements

- A control node with Ansible. See the
  [collection requirements](../../README.md#requirements).
- `become` privileges on the target, which is running one of the
  platforms above.
- Outbound HTTPS from the target to `nginx.org` on the Enterprise Linux
  path, for both the repository metadata and the signing key. The
  Debian path needs only the distribution mirrors it is already
  configured for.
- `systemd`. Both paths finish by enabling and starting the unit.

## Role variables

| Variable | Default | Description |
| --- | --- | --- |
| `supported_distribution` | the seven names above | Distributions the platform assertion accepts. |

`supported_distribution` is a gate, not a feature switch. Widening it
is only half the job: a name added here without a matching dispatch
condition in `tasks/main.yml` passes the assertion, matches neither
`include_tasks`, and leaves the role reporting `ok` having installed
nothing. Keep it in step with `mod_security`'s variable of the same
name too — the two roles run back to back against the same host.

The role has no other tunables. There is no version pin, no repository
override and no service-state flag.

## Usage

```yaml
- name: Install nginx
  hosts: all
  become: true
  gather_facts: true
  any_errors_fatal: true
  roles:
    - name: hasnimehdi91.secure_nginx.install
```

`gather_facts: true` is required, not decorative: the assertion and
both dispatch conditions read
`ansible_facts['distribution']`.

Run it, then run `mod_security` in the same play to build the firewall
against what this role installed:

```bash
ansible-playbook -i inventory playbook.yml
```

## Results

- NGINX is installed, its unit is enabled, and the service is started.
- On Enterprise Linux, `/etc/yum.repos.d/nginx.repo` is present, owned
  by `root:root`, mode `0644`, and points at the nginx.org stable
  repository with GPG checking on.
- On the Debian family the package index has been refreshed and the
  distribution's NGINX package is installed.

Both paths use `state: present`, so a second run does not upgrade an
NGINX that is already there. That is what keeps a re-run of the
installer from moving the web server underneath a `mod_security`
connector compiled against the previous version. Upgrading is an
operator decision, taken deliberately, not a side effect of running
this role again.

The Debian path enables and starts the unit even though the
distribution's `postinst` already did, so the outcome the role promises
comes from the role rather than from a packaging side effect, and a
host whose unit was stopped by hand is returned to the state the role
claims to leave behind.

## Testing

This role is exercised by the disposable-VM integration harness,
together with `mod_security`, on Ubuntu 24.04 and AlmaLinux 10. See the
[tests documentation](../../tests/README.md) for how to run it and the
[integration test documentation](../../tests/integration/README.md) for
the prerequisites.

## Links

- Repository: <https://github.com/Black-Cockpit/ansible-secure-nginx>
- Issues: <https://github.com/Black-Cockpit/ansible-secure-nginx/issues>
- NGINX Linux packages: <https://nginx.org/en/linux_packages.html>
