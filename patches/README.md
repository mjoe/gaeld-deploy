# Local patches

Files named `patches/*.patch` are applied to the upstream Gäld source during the image build, in alphabetical order.
The repository ships **no** patches, and `*.patch` files are ignored by git, so your patches stay on your machine and
are never part of the published images.

- Format: a unified diff relative to the Gäld source root, applied with `patch -p1`
  (for example from `diff -ruN original modified` or `git diff`).
- If a patch no longer applies after an upstream update, the build stops with an error naming the patch.
- The applied patches are listed in `/var/www/html/.gaeld-rev` inside the image.
- A patched image is your own build. If you offer a modified Gäld to other people over a network, the AGPL-3.0
  requires you to make the modified source available to them.
