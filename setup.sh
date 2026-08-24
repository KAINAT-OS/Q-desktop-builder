#!/bin/bash
# Quintuplet Desktop (Q Desktop) Meta-Package Generator

echo "🚀 Generating Q Desktop Builder Structure..."

# 1. Clean up old failed attempts
rm -rf debian/

# 2. Create the required directory structure
mkdir -p .github/workflows
mkdir -p arch
mkdir -p rootfs/usr/share/q-desktop/themes/red
mkdir -p rootfs/usr/share/q-desktop/themes/blue

# 3. Generate the GitHub Actions CI/CD Pipeline
cat << 'EOF' > .github/workflows/build-q-desktop.yml
name: Build and Deploy Quintuplet DE (Q Desktop)

on:
  push:
    branches: [ "main" ]
  workflow_dispatch:

jobs:
  # ------------------------------------------------------------------
  # JOB 1: Build Debian Meta-Package (Red / Dante)
  # ------------------------------------------------------------------
  build-debian:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Repository
        uses: actions/checkout@v4

      - name: Build Debian Package
        run: |
          mkdir -p package/DEBIAN
          cp -r rootfs/* package/
          
          # Dynamically generate the Debian control file
          printf "Package: q-desktop-shell\nVersion: 1.0.0\nArchitecture: all\nMaintainer: Kainat Quaderee <kainat@kainatgroup.com>\nDepends: plasma-desktop, plasma-workspace, kwin-x11 | kwin-wayland\nDescription: Quintuplet Desktop (Q Desktop) Shell Overlays\n Custom KDE Plasma desktop environment layer for Kainat OS Red (Dante).\n" > package/DEBIAN/control
          
          # Inject Dante identity marker
          mkdir -p package/etc/q-desktop
          echo "IDENTITY=DANTE" > package/etc/q-desktop/variant
          
          # Build the .deb binary package
          fakeroot dpkg-deb --build package q-desktop-shell_1.0.0_all.deb
          
          mkdir -p dist/debian
          mv q-desktop-shell_1.0.0_all.deb dist/debian/
          cd dist/debian
          dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz

      - name: Upload Debian Artifacts
        uses: actions/upload-artifact@v4
        with:
          name: debian-dist
          path: dist/debian/

  # ------------------------------------------------------------------
  # JOB 2: Build Arch Meta-Package (Blue / Vergil)
  # ------------------------------------------------------------------
  build-arch:
    runs-on: ubuntu-latest
    container: archlinux:latest
    steps:
      - name: Checkout Repository
        uses: actions/checkout@v4

      - name: Sync Arch Toolchain
        run: pacman -Syu --noconfirm --needed base-devel pacman-contrib

      - name: Build Arch Package
        run: |
          useradd builder -m
          chown -R builder:builder .
          su builder -c "cd arch && makepkg -sc --noconfirm"
          
          mkdir -p dist/arch
          mv arch/*.pkg.tar.zst dist/arch/
          cd dist/arch
          repo-add q-desktop.db.tar.gz *.pkg.tar.zst

      - name: Upload Arch Artifacts
        uses: actions/upload-artifact@v4
        with:
          name: arch-dist
          path: dist/arch/

  # ------------------------------------------------------------------
  # JOB 3: Deploy to SourceForge
  # ------------------------------------------------------------------
  deploy-sourceforge:
    needs: [build-debian, build-arch]
    runs-on: ubuntu-latest
    steps:
      - name: Download All Artifacts
        uses: actions/download-artifact@v4
        with:
          path: artifacts

      - name: Configure SSH and Deploy
        env:
          SF_KEY: ${{ secrets.SF_SSH_KEY }}
          SF_USER: ${{ secrets.SF_USERNAME }}
        run: |
          mkdir -p ~/.ssh
          echo "$SF_KEY" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519
          ssh-keyscan frs.sourceforge.net >> ~/.ssh/known_hosts
          
          rsync -avP --delete artifacts/arch-dist/ $SF_USER@frs.sourceforge.net:/home/frs/project/q-desktop/arch/
          rsync -avP --delete artifacts/debian-dist/ $SF_USER@frs.sourceforge.net:/home/frs/project/q-desktop/debian/
EOF

# 4. Generate the Arch Linux PKGBUILD
cat << 'EOF' > arch/PKGBUILD
# Maintainer: Kainat Quaderee <kainat@kainatgroup.com>
pkgname=q-desktop-shell
pkgver=1.0.0
pkgrel=1
pkgdesc="Quintuplet Desktop (Q Desktop) Shell Overlays"
arch=('any')
url="https://sourceforge.net/projects/q-desktop/"
license=('GPL')
depends=('plasma-desktop' 'plasma-workspace' 'kwin')

package() {
    # Copy the custom Q Desktop files into the Arch package
    cp -r ../rootfs/* "$pkgdir/"
    
    # Inject Q Desktop branding marker for Arch (Blue/Vergil)
    install -d "$pkgdir/etc/q-desktop"
    echo "IDENTITY=VERGIL" > "$pkgdir/etc/q-desktop/variant"
}
EOF

# 5. Create placeholder files so Git tracks the empty theme folders
echo "# Q Desktop Red (Dante) Assets" > rootfs/usr/share/q-desktop/themes/red/README.md
echo "# Q Desktop Blue (Vergil) Assets" > rootfs/usr/share/q-desktop/themes/blue/README.md

# 6. Create Main README
cat << 'EOF' > README.md
# Quintuplet Desktop (Q Desktop) Builder
This repository contains the CI/CD pipeline and meta-packages for Kainat OS.
EOF

echo "✅ Done! Your Q Desktop Builder structure is ready."
