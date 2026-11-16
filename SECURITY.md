# Security Policy

## Reporting a vulnerability

Please report security problems **privately**, not as a public issue:

1. Open the [Security tab](https://github.com/mjoe/gaeld-deploy/security) of this repository.
2. Choose **Report a vulnerability** and describe the problem: what is affected, how to reproduce it, and which
   release tag or image you used.

This project is maintained by one person. I aim to reply within 7 days and will keep you informed about the fix.

## Scope

In scope: the files in this repository (Dockerfile, compose file, scripts, CI configuration) and the images published
to `ghcr.io/mjoe/gaeld-deploy`. Examples are insecure defaults, exposed ports, unsafe scripts or workflow weaknesses.

Out of scope, please report these upstream:

- Vulnerabilities in Gäld itself: see the [upstream security policy](https://github.com/Scanix/Gaeld/security/policy).
- Vulnerabilities in third-party software such as PHP, nginx, PostgreSQL or Valkey. Feel free to tell me as well, so
  that I can publish a rebuilt image once a fix is available.

## Supported versions

Only the latest release receives fixes. A fix is published as a new revision of the current upstream version, for
example `v3.9.0-2`. See [Releases and versioning](README.md#releases-and-versioning).
