# syntax=docker/dockerfile:1
# ============================================================
# Kazama Windows — Windows RDP on Railway
# Developer  : @kazamaofficial-git
# Repository : https://github.com/kazamaofficial-git/kazama-windows
# ============================================================
# Thin layer on top of dockurr/windows (Windows inside QEMU) that adds:
#   - RDP_PASSWORD / RDP_USERNAME handling and validation
#   - WINDOWS_VERSION = windows-latest | windows-2025 | windows-2022
#   - automatic software-emulation fallback when /dev/kvm is missing
#   - optional Tailscale (private RDP, no public TCP Proxy)
#   - in-Windows extras via /oem: Storage Booster + Kazama wallpaper
#   - English / Indonesian log messages (APP_LANG)
#
# Build:  docker build -t kazama-windows .
# Run  :  docker run -it --rm --device=/dev/kvm --cap-add NET_ADMIN \
#           -p 8006:8006 -p 3389:3389 -e RDP_PASSWORD='Str0ng#Pass9' \
#           -v kazama-win:/storage kazama-windows

ARG DOCKUR_TAG=latest
ARG TAILSCALE_TAG=stable

# Static Tailscale binaries (official multi-stage pattern).
FROM docker.io/tailscale/tailscale:${TAILSCALE_TAG} AS tailscale

FROM dockurr/windows:${DOCKUR_TAG}

LABEL org.opencontainers.image.title="Kazama Windows RDP" \
      org.opencontainers.image.description="Windows Server over RDP, packaged for Railway" \
      org.opencontainers.image.authors="@kazamaofficial-git" \
      org.opencontainers.image.source="https://github.com/kazamaofficial-git/kazama-windows" \
      org.opencontainers.image.licenses="MIT"

COPY --from=tailscale /usr/local/bin/tailscale /usr/local/bin/tailscaled /usr/local/bin/

COPY rootfs/ /
# dockur copies /oem to C:\OEM inside Windows and runs install.bat at the end of the install.
# The wallpaper is optional: the glob keeps the build working if assets/wallpaper.png is missing.
COPY windows/ assets/wallpaper.pn[g] /oem/
RUN chmod 0755 /usr/local/bin/kazama-entrypoint \
    && chmod 0644 /usr/local/lib/kazama/common.sh

ENV WINDOWS_VERSION=windows-latest \
    RDP_USERNAME=kazama \
    APP_LANG=en

EXPOSE 8006 3389

# Same init as upstream (tini); our wrapper ends with `exec /run/entry.sh`.
ENTRYPOINT ["/usr/bin/tini", "-s", "/usr/local/bin/kazama-entrypoint"]
