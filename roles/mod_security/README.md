mod_security
=========

This role is to install ModSecurity module within nginx.
The module supports different platforms including:

- RedHat Linux
- Rocky Linux
- Alma Linux 
- Centos
- Oracle Linux
- Ubuntu
- Debian

# Variables:

```yaml
# Build directory
build_dir: "/tmp"

# ModSecurity version default is v3.0.10
module_version: "3.0.10"

# Disable ModSecurity action
detection_only: false
```

# Example:

The example bellow install nginx ModSecurity module v3.0.10:

```yaml
- name: Nginx ModSecurity
  hosts: all # Make sure to select a machine based on your inventory
  become: yes
  gather_facts: yes
  any_errors_fatal: yes
  roles:
  - name: hasnimehdi91.secure_nginx.mod_security
```