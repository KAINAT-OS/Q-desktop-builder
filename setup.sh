#!/bin/bash
# ============================================================================
# Quintuplet Desktop (Q Desktop) - Full Repository Setup Script
# Author: Kainat Quaderee
# Purpose: Sets up the CI/CD pipeline for building Q Desktop meta-packages
#          for both Arch Linux (Blue/Vergil) and Debian (Red/Dante)
# ============================================================================

set -e

echo "🚀 Initializing Quintuplet Desktop (Q Desktop) Builder..."
echo "========================================================="

# ---------------------------------------------------------------------------
# STEP 1: Clean up any previous failed attempts
# ---------------------------------------------------------------------------
echo "🧹 Cleaning up old files..."
rm -rf debian/ rootfs/ arch/ dist/ package/ 2>/dev/null || true

# ---------------------------------------------------------------------------
# STEP 2: Create directory structure
# ---------------------------------------------------------------------------
echo "📁 Creating directory structure..."
mkdir -p .github/workflows
mkdir -p arch
mkdir -p rootfs/usr/share/q-desktop/themes/red
mkdir -p rootfs/usr/share/q-desktop/themes/blue
mkdir -p rootfs/usr/share/q-desktop/configs

# ---------------------------------------------------------------------------
# STEP 3: Create the GitHub Actions CI/CD Workflow
# ---------------------------------------------------------------------------
echo "⚙️  Generating GitHub Actions workflow..."
cat << 'WORKFLOW_EOF' > .github/workflows/build-q-desktop.yml
name: Build and Deploy Quintuplet DE (Q Desktop)

on:
  push:
    branches: [ "main" ]
  workflow_dispatch:

jobs:
  # ------------------------------------------------------------------
  # JOB 1: Build Arch Linux (Blue / Vergil) Package
  # ------------------------------------------------------------------
  build-arch:
    runs-on: ubuntu-latest
    container: archlinux:latest
    steps:
      - name: Checkout Repository
        uses: actions/checkout@v4

      - name: Sync Arch Mirror & Toolchain
        run: |
          pacman -Syu --noconfirm --needed base-devel git cmake ninja pacman-contrib
          # FIX: Pre-install runtime dependencies as root so makepkg doesn't prompt for sudo password
          pacman -S --noconfirm --needed plasma-desktop plasma-workspace kwin

      - name: Build PKGBUILD
        run: |
          useradd builder -m
          chown -R builder:builder .
          su builder -c "cd arch && makepkg -sc --noconfirm"

      - name: Generate Arch Repository DB
        run: |
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
  # JOB 2: Build Debian (Red / Dante) Package
  # ------------------------------------------------------------------
  build-debian:
    runs-on: ubuntu-latest
    container: debian:bookworm
    steps:
      - name: Checkout Repository
        uses: actions/checkout@v4

      - name: Install Debian Build Chain
        run: |
          apt-get update
          apt-get install -y build-essential devscripts dpkg-dev apt-utils git cmake ninja-build fakeroot

      - name: Build Debian Package
        run: |
          # Create package structure dynamically
          mkdir -p package/DEBIAN
          mkdir -p package/etc/q-desktop
          mkdir -p package/usr/share/q-desktop/themes/red
          mkdir -p package/usr/share/q-desktop/themes/blue
          mkdir -p package/usr/share/q-desktop/configs
          
          # Copy rootfs contents if they exist
          if [ -d "rootfs" ]; then
            cp -r rootfs/* package/ 2>/dev/null || true
          fi
          
          # Inject Dante identity marker
          echo "IDENTITY=DANTE" > package/etc/q-desktop/variant
          
          # Generate DEBIAN/control dynamically
          printf "Package: q-desktop-shell\nVersion: 1.0.0\nArchitecture: all\nMaintainer: Kainat Quaderee <kainat@kainatgroup.com>\nDepends: plasma-desktop, plasma-workspace, kwin-x11 | kwin-wayland\nDescription: Quintuplet Desktop (Q Desktop) Shell Overlays\n Custom KDE Plasma desktop environment layer for Kainat OS Red (Dante).\n Contains QML overrides, themes, and configuration manifests.\n" > package/DEBIAN/control
          
          # Build the .deb package directly (bypasses dpkg-buildpackage changelog requirements)
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
  # JOB 3: Deploy Packages to SourceForge
  # ------------------------------------------------------------------
  deploy-sourceforge:
    needs: [build-arch, build-debian]
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
          
          # Sync Arch Repo to SourceForge
          rsync -avP --delete artifacts/arch-dist/ $SF_USER@frs.sourceforge.net:/home/frs/project/q-desktop/arch/
          # Sync Debian Repo to SourceForge
          rsync -avP --delete artifacts/debian-dist/ $SF_USER@frs.sourceforge.net:/home/frs/project/q-desktop/debian/
WORKFLOW_EOF

# ---------------------------------------------------------------------------
# STEP 4: Create the Arch Packaging File (Blue / Vergil)
# ---------------------------------------------------------------------------
echo "📦 Generating Arch PKGBUILD..."
cat << 'PKGBUILD_EOF' > arch/PKGBUILD
# Maintainer: Kainat Quaderee <kainat@kainatgroup.com>
pkgname=q-desktop-shell
pkgver=1.0.0
pkgrel=1
pkgdesc="Quintuplet Desktop (Q Desktop) Shell Overlays - Blue/Vergil Identity"
arch=('any')
url="https://sourceforge.net/projects/q-desktop/"
license=('GPL')
depends=('plasma-desktop' 'plasma-workspace' 'kwin')

package() {
    # Copy the custom Q Desktop files into the Arch package
    if [ -d "$srcdir/../rootfs" ]; then
        cp -r "$srcdir/../rootfs"/* "$pkgdir/" 2>/dev/null || true
    fi
    
    # Create Q Desktop identity marker for Arch (Blue/Vergil)
    install -d "$pkgdir/etc/q-desktop"
    echo "IDENTITY=VERGIL" > "$pkgdir/etc/q-desktop/variant"
    
    # Ensure theme directories exist
    install -d "$pkgdir/usr/share/q-desktop/themes/red"
    install -d "$pkgdir/usr/share/q-desktop/themes/blue"
    install -d "$pkgdir/usr/share/q-desktop/configs"
    
    # Create placeholder files so package is never empty
    echo "# Q Desktop Red (Dante) Theme Assets" > "$pkgdir/usr/share/q-desktop/themes/red/README.md"
    echo "# Q Desktop Blue (Vergil) Theme Assets" > "$pkgdir/usr/share/q-desktop/themes/blue/README.md"
    echo "# Q Desktop Configuration Manifests" > "$pkgdir/usr/share/q-desktop/configs/README.md"
}
PKGBUILD_EOF

# ---------------------------------------------------------------------------
# STEP 5: Create placeholder theme files
# ---------------------------------------------------------------------------
echo "🎨 Creating placeholder theme files..."

cat << 'RED_EOF' > rootfs/usr/share/q-desktop/themes/red/README.md
# Q Desktop - Red Theme (Dante Identity)
This directory contains the Red/Dante themed assets for Kainat OS.
RED_EOF

cat << 'BLUE_EOF' > rootfs/usr/share/q-desktop/themes/blue/README.md
# Q Desktop - Blue Theme (Vergil Identity)
This directory contains the Blue/Vergil themed assets for Kainat OS.
BLUE_EOF

cat << 'CONFIG_EOF' > rootfs/usr/share/q-desktop/configs/README.md
# Q Desktop Configuration Manifests
This directory contains the "Golden State" configuration files.
CONFIG_EOF

# ---------------------------------------------------------------------------
# STEP 6: Create main README
# ---------------------------------------------------------------------------
echo "📖 Generating main README..."
cat << 'README_EOF' > README.md
# Quintuplet Desktop (Q Desktop) Builder
**The unified Desktop Environment layer for Kainat OS**
## Philosophy
- **Qt & QML**: The core framework powering the visual logic.
- **Plasma 5**: Honoring the fifth generation of the KDE desktop environment.
- **Dante (Red) & Vergil (Blue)**: The duality of Debian's stability and Arch's precision.
README_EOF

# ---------------------------------------------------------------------------
# STEP 7: Create .gitignore
# ---------------------------------------------------------------------------
echo "🔒 Creating .gitignore..."
cat << 'GITIGNORE_EOF' > .gitignore
# Build artifacts
*.deb
*.pkg.tar.zst
*.tar.gz
package/
dist/

# Editor files
*.swp
*.swo
*~
.vscode/
.idea/
GITIGNORE_EOF

# ---------------------------------------------------------------------------
# STEP 8: Final summary
# ---------------------------------------------------------------------------
echo ""
echo "========================================================="
echo "✅ Q Desktop Builder setup complete!"
echo "========================================================="
echo ""
echo "🔑 Next steps:"
echo "   1. Add GitHub Secrets: SF_USERNAME and SF_SSH_KEY"
echo "   2. Commit and push: git add . && git commit -m 'Fix CI/CD pipeline' && git push origin main"
echo "   3. Watch the GitHub Actions tab for the build!"
echo ""
