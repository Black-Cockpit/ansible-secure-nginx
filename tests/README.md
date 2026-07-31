# Tests

The collection ships one kind of test: a disposable-VM integration
harness that installs nginx and the ModSecurity module on a real
machine and asserts the result.

## No unit tests

There are none, and none are missing. Unit tests need a unit to
test — a Python plugin, a filter, a module — and this collection
ships no Python at all: `plugins/` holds nothing but its placeholder
README. Both roles are task files calling builtin Ansible modules, and
the only way to prove they do what they claim is to run them against a
machine. That is what the integration harness is for.

If a plugin is ever added under `plugins/`, a `tests/unit/` suite
belongs beside it. Until then, adding one would mean writing tests for
code that does not exist.

## Integration tests

The harness boots a throwaway VirtualBox machine, runs the `install`
role and then the `mod_security` role against it over SSH, and asserts
that the packages, the compiled module, the nginx configuration and
the rule set are all where the roles promise to leave them. It
finishes by destroying the machine.

The set of machines to test is a matrix — each entry pins a box, its
firmware and its resources. Adding a platform is a new matrix entry,
with no changes to the harness itself.

Run one entry, or the whole matrix:

```bash
cd tests/integration
./run.sh ubuntu2404      # a single entry, full cycle
./run.sh all             # every entry, with a pass/fail summary
```

Expect 10 to 20 minutes per entry: the `mod_security` role compiles
libmodsecurity and the nginx source on the guest, and that is nearly
all of the wall clock.

> **The WAF is not exercised end to end.** The assertions are
> structural. The `mod_security` role loads the module and writes the
> rule files but never switches the engine on for any nginx context,
> so a test that sent an attack payload and expected `403` would fail
> against a correct run. See
> [known gap](integration/README.md#known-gap-no-functional-waf-test)
> for why it is deferred rather than weakened.

See the [integration test documentation](integration/README.md) for
the prerequisites (including the VirtualBox/KVM VT-x note), the full
list of assertions, and how to add a platform.

## Links

- Integration harness: [integration/README.md](integration/README.md)
- Repository: <https://github.com/Black-Cockpit/ansible-secure-nginx>
- Issues: <https://github.com/Black-Cockpit/ansible-secure-nginx/issues>
