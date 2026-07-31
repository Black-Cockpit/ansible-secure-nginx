# hasnimehdi91.secure_nginx

Ansible collection that installs NGINX and builds the
[ModSecurity](https://github.com/owasp-modsecurity/ModSecurity) web
application firewall against it. It ships two roles — one that puts
NGINX on the host, and one that compiles `libmodsecurity` and the NGINX
connector from source, installs the resulting dynamic module, and
writes a rule configuration under `/etc/nginx/waf_rules`.

The two roles are meant to run in that order. `mod_security` compiles
its connector against the NGINX already on the host and refuses to run
without one, so `install` is what makes it usable.

> **Compiles from source and removes the toolchain.** The
> `mod_security` role downloads the ModSecurity release and the NGINX
> source onto the target, builds both there, and then uninstalls `gcc`,
> `make`, `automake` and `git` — unconditionally, whether or not the
> role installed them. Anything else on the host that depends on those
> packages breaks after the first run, and `git` is the one that
> usually bites. Budget several minutes of CPU and a couple of
> gigabytes under `build_dir` for every run, re-runs included: the
> build tree is deleted and rebuilt each time.

## Roles

- **install** — installs NGINX, then enables and starts the service.
  See the [install role documentation](roles/install/README.md).
- **mod_security** — builds and installs the ModSecurity module for
  NGINX and its rule configuration. See the
  [mod_security role documentation](roles/mod_security/README.md).

> **The firewall is loaded, not switched on.** `mod_security` loads
> the module and writes the rules, but never emits `modsecurity on;`
> into an NGINX context, so no traffic is inspected once it finishes.
> The two directives you still have to add are in
> [switching the WAF on](roles/mod_security/README.md#switching-the-waf-on).

## Coverage

Both roles accept the same set of distributions, named in each role's
`supported_distribution` variable and enforced by an assertion on the
first task. A distribution outside that set fails the run on the host
that caused it rather than reporting `ok` and doing nothing.

| Distribution | Versions | NGINX package source | Tested by CI |
| --- | --- | --- | --- |
| AlmaLinux | 8, 9, 10 | nginx.org stable | 10 |
| CentOS | 8, 9, 10 | nginx.org stable | — |
| Debian | 11, 12 | distribution archive | — |
| Oracle Linux | 8, 9, 10 | nginx.org stable | — |
| Red Hat Enterprise Linux | 8, 9, 10 | nginx.org stable | — |
| Rocky Linux | 8, 9, 10 | nginx.org stable | — |
| Ubuntu | 22.04, 24.04 | distribution archive | 24.04 |

**The CI-tested platforms are Ubuntu 24.04 and AlmaLinux 10 only.**
Every other row is claimed because it shares its package manager,
repository layout and dependency names with one of those two — not
because it has been exercised. Treat the untested rows as supported by
construction, and validate one yourself before relying on it.

Enterprise Linux takes NGINX from the official nginx.org stable
repository rather than from AppStream, because `mod_security` needs a
source tarball matching the running version and vendor builds carry
version strings upstream never published. The Debian family keeps
installing the distribution package. See the
[install role](roles/install/README.md) for what that difference costs
on each path.

## Requirements

- Python 3 and Ansible on the control node. `meta/runtime.yml` declares
  `ansible-core` `2.15.8` or newer; the repository's own tooling pins
  `ansible>=10.0.0,<14.0.0` in `requirements.txt`.
- `become` privileges on the targets, each running one of the platforms
  above.
- Outbound HTTPS from every target to `github.com`, for the ModSecurity
  release tarball and the connector repository, and to `nginx.org`, for
  the NGINX source tarball on every platform and for the package
  repository on Enterprise Linux.
- Roughly 2 GB free under `build_dir` and several minutes of CPU per
  target. The two source builds dominate the run time by a wide margin.
- A `build_dir` that is neither mounted `noexec` nor swept on a
  schedule. The default is `/tmp`, where both policies are common and
  both break the build.

## Installation

```bash
ansible-galaxy collection install hasnimehdi91.secure_nginx
```

## Usage

Install NGINX on its own:

```yaml
- name: Install nginx
  hosts: all
  become: true
  gather_facts: true
  any_errors_fatal: true
  roles:
    - name: hasnimehdi91.secure_nginx.install
```

Install NGINX and build the firewall against it. Start with
`detection_only: true`, which logs rule matches and serves the request
anyway, review the audit log, and only then flip it to `false`:

```yaml
- name: Install nginx and ModSecurity
  hosts: all
  become: true
  gather_facts: true
  any_errors_fatal: true
  roles:
    - name: hasnimehdi91.secure_nginx.install
    - name: hasnimehdi91.secure_nginx.mod_security
      vars:
        detection_only: true
```

`detection_only`, `module_version` and `build_dir` are declared in the
role's `vars/main.yml`, which outranks inventory. Set them as role
parameters as above, or on the command line — the same names in
`group_vars` or `host_vars` are silently ignored:

```bash
ansible-playbook -i inventory playbook.yml -e detection_only=true
```

## Results

After both roles have run the host has NGINX installed, enabled and
started; `ngx_http_modsecurity_module.so` in the modules directory that
NGINX was compiled to read; a `load_module` directive included from
`/etc/nginx/nginx.conf`; and a rule configuration under
`/etc/nginx/waf_rules`. The full list of paths is in the
[mod_security role documentation](roles/mod_security/README.md#results).

Two things the collection does not finish, and that you have to:

- **Nothing switches the firewall on.** No `modsecurity on;` or
  `modsecurity_rules_file` directive is written into any `http`,
  `server` or `location` block, so the module is loaded and inert and
  no request is inspected. The lines to add are in
  [switching the WAF on](roles/mod_security/README.md#switching-the-waf-on).
- **Nothing reloads NGINX.** `mod_security` defines restart and
  configuration-test handlers but never notifies them, so the running
  process keeps serving without the module until it is restarted by
  hand or by whatever runs after the role.

The collection also installs no attack rule set. What lands in
`/etc/nginx/waf_rules/modsecurity.conf` is upstream's recommended
engine configuration, not the
[OWASP Core Rule Set](https://github.com/coreruleset/coreruleset);
adding the CRS is a separate step on top of this collection.

## Testing

The collection ships a disposable-VM integration harness that boots a
machine, runs both roles against it and asserts the result. There are
no unit tests: the collection ships no Python plugins, so there is
nothing for them to exercise. See the
[tests documentation](tests/README.md).

The matrix covers Ubuntu 24.04 and AlmaLinux 10 and nothing else, and
its assertions are structural — that the module was built, installed
and loaded, that the rule files are on disk, and that `nginx -t` still
passes. No test asserts that the firewall blocks a request, because
after the roles run it does not.

## Links

- Repository: <https://github.com/Black-Cockpit/ansible-secure-nginx>
- Issues: <https://github.com/Black-Cockpit/ansible-secure-nginx/issues>
- ModSecurity: <https://github.com/owasp-modsecurity/ModSecurity>
- ModSecurity NGINX connector:
  <https://github.com/owasp-modsecurity/ModSecurity-nginx>
- OWASP Core Rule Set: <https://github.com/coreruleset/coreruleset>
- NGINX Linux packages: <https://nginx.org/en/linux_packages.html>
