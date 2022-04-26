#!/usr/bin/env bash

# Prevent tainting variables via environment
# See: https://gist.github.com/duxsco/fad211d5828e09d0391f018834f955c9
unset BOOT_EFI_FILE BOOT_FILE CURRENT_KERNEL_VERSION EFI_FILE MOUNTPOINT NEW_KERNEL_VERSION UMOUNT

function secure_mount() {
    if ! mountpoint --quiet "$1"; then
        if ! mount "$1" || ! mountpoint --quiet "$1"; then
            echo "Failed to mount \"$1\"! Aborting..." >&2
            exit 1
        fi

        UMOUNT+=("$1")
    fi
}

NEW_KERNEL_VERSION="$(readlink /usr/src/linux | sed 's/linux-//')"
declare -a UMOUNT

secure_mount "/boot"

grep -Po "^UUID=[0-9A-F]{4}-[0-9A-F]{4}[[:space:]]+/\Kefi[a-z](?=[[:space:]]+vfat[[:space:]]+)" /etc/fstab | while read -r MOUNTPOINT; do
    secure_mount "/${MOUNTPOINT}"

    CURRENT_KERNEL_VERSION="$(uname -r | sed "s/-$(arch)$//")"
    if [[ -f "/${MOUNTPOINT}/boot.cfg" ]] && ! cmp "/boot/grub_${MOUNTPOINT}.cfg" <(sed "s/${CURRENT_KERNEL_VERSION}/${NEW_KERNEL_VERSION}/g" "/${MOUNTPOINT}/boot.cfg"); then
        echo "Something is possibly wrong with /boot/grub_${MOUNTPOINT}.cfg! Aborting..."
        exit 1
    fi
done

find /boot -maxdepth 1 -type f -name "*\.sig" -exec rm {} +

find /boot -maxdepth 1 -type f -exec gpg --detach-sign {} \;

grep -Po "^UUID=[0-9A-F]{4}-[0-9A-F]{4}[[:space:]]+/\Kefi[a-z](?=[[:space:]]+vfat[[:space:]]+)" /etc/fstab | while read -r MOUNTPOINT; do
    (find /"${MOUNTPOINT}"/{"System.map-${NEW_KERNEL_VERSION}-x86_64-ssh","initramfs-${NEW_KERNEL_VERSION}-x86_64-ssh.img","vmlinuz-${NEW_KERNEL_VERSION}-x86_64-ssh"} 2>/dev/null || true) | while read -r EFI_FILE; do
        if [[ -f ${EFI_FILE} ]]; then
            mv -f "${EFI_FILE}" "${EFI_FILE}.old"
            mv -f "${EFI_FILE}.sig" "${EFI_FILE}.old.sig"
        fi
    done
done

find /boot /efi* -type f ! -name "*\.sig" ! -name "bootx64\.efi" | while read -r BOOT_EFI_FILE; do
    if  [[ ! -f ${BOOT_EFI_FILE}.sig ]] || \
        ! grep -q "^GOODSIG TRUST_ULTIMATE VALIDSIG$" < <(
            gpg --status-fd 1 --verify "${BOOT_EFI_FILE}.sig" "${BOOT_EFI_FILE}" 2>/dev/null | \
            grep -Po "^\[GNUPG:\][[:space:]]+\K(GOODSIG|VALIDSIG|TRUST_ULTIMATE)(?=[[:space:]])" | \
            sort | \
            paste -d " " -s -
        )
    then
        echo "GnuPG signature verification failed for ${BOOT_EFI_FILE}! Aborting..." >&2
        exit 1
    fi
done

grep -Po "^UUID=[0-9A-F]{4}-[0-9A-F]{4}[[:space:]]+/\Kefi[a-z](?=[[:space:]]+vfat[[:space:]]+)" /etc/fstab | while read -r MOUNTPOINT; do
    rsync -a /boot/{"System.map-${NEW_KERNEL_VERSION}-x86_64-ssh","initramfs-${NEW_KERNEL_VERSION}-x86_64-ssh.img","vmlinuz-${NEW_KERNEL_VERSION}-x86_64-ssh"}{,.sig} "/${MOUNTPOINT}/"
    rsync -a "/boot/grub_${MOUNTPOINT}.cfg" "/${MOUNTPOINT}/grub.cfg"
    rsync -a "/boot/grub_${MOUNTPOINT}.cfg.sig" "/${MOUNTPOINT}/grub.cfg.sig"
    rm "/boot/grub_${MOUNTPOINT}.cfg" "/boot/grub_${MOUNTPOINT}.cfg.sig"
    sync
done

rm -f /boot/{"System.map-${NEW_KERNEL_VERSION}-x86_64-ssh","initramfs-${NEW_KERNEL_VERSION}-x86_64-ssh.img","vmlinuz-${NEW_KERNEL_VERSION}-x86_64-ssh"}{,.sig}

for MOUNTPOINT in "${UMOUNT[@]}"; do
    umount "${MOUNTPOINT}"
done
