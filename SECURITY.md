# Security policy

## Reporting

Use GitHub's private vulnerability reporting for this repository:
<https://github.com/somework/lockrot-action/security/advisories/new>. Do not open a public issue.
You will get an acknowledgement within a few days, and a fix or an explanation before anything is
published.

If the problem is in lockrot itself rather than in this action or the image, report it at
<https://github.com/somework/lockrot/security/advisories/new> instead.

## What the action trusts

- **GitHub Releases of `somework/lockrot`** for `lockrot.phar` and `lockrot.phar.sha256`. The
  default release is pinned by version and sha256 in [`lockrot.env`](lockrot.env); a download that
  does not match is refused. An explicit `version` trusts the `.sha256` file from the same release,
  and the `checksum` input replaces both.
- **`actions/cache` and `shivammathur/setup-php`**, pinned by commit SHA in [`action.yml`](action.yml).
- **The token in `github-token`** is handed to lockrot, which uses it against `api.github.com` only.

## What the image trusts

The same release assets, fetched and verified at build time, on the official `php` image pinned by
digest. Every published image is signed with cosign through GitHub's OIDC identity and carries a
GitHub build-provenance attestation; the README shows how to verify both.

## Supported versions

The newest `v1.x.y` release, which `v1` follows. Older releases keep working but are not patched.
