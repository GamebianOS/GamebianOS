# Ubuntu slim live ISO: do not enable i386 here.
# Steam is installed by Calamares (packages.conf + gamebian-install-steam);
# ensure_apt_gaming_repos / gamebian-ensure-apt-sources adds i386 on the target.
# Re-adding "i386" to packages.foreign-architectures pulls multiarch libs onto the live squashfs.
