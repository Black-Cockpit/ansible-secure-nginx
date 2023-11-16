# Ansible Collection - hasnimehdi91.secure_nginx

This collection provides roles to securely install and configure nginx.


## Installation

    ansible-galaxy collection install hasnimehdi91.secure_nginx

## Usage

```yaml
- name: Test
  hosts: all
  become: no
  connection: local
  roles:
  # Install nginx
  - hasnimehdi91.secure_nginx.install
  # Install ModSecurity web application firewall
  - hasnimehdi91.secure_nginx.mod_security
  # Harden nginx using cis benchmark 
  - hasnimehdi91.secure_nginx.cis_hardening