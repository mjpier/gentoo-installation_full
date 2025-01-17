!!! info
    This chapter basically follows [SELinux/Installation](https://wiki.gentoo.org/wiki/SELinux/Installation). Currently, I only use SELinux on servers, and only "mcs" policy type to be able to better isolate virtual machines from each other.

## 14.1. Enable SELinux

Reduce the number of services by disabling some unneeded ones in order to avoid a few SELinux denials. This may not be desired on "desktop" systems.

```shell hl_lines="3"
systemctl mask user@.service && \
systemctl disable systemd-userdbd.socket && \
rsync -a /etc/nsswitch.conf /etc/._cfg0000_nsswitch.conf && \
sed -i 's/^hosts:\([[:space:]]*\)mymachines \(.*\)$/hosts:\1\2/' /etc/._cfg0000_nsswitch.conf && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Setup "make.conf":

```shell hl_lines="1"
rsync -a /etc/portage/make.conf /etc/portage/._cfg0000_make.conf && \
echo -e '\nPOLICY_TYPES="mcs"' >> /etc/portage/._cfg0000_make.conf && \
sed -i 's/^USE_HARDENED="\(.*\)"/USE_HARDENED="\1 -ubac -unconfined"/' /etc/portage/._cfg0000_make.conf && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

For the switch to a SELinux profile, you have two options depending on the profile currently in use:

=== "duxsco:hardened-systemd-merged-usr"
    If you have switched to [duxsco:hardened-systemd-merged-usr](https://github.com/duxsco/gentoo-installation/tree/main/overlay/duxsco/profiles/hardened-systemd-merged-usr) in section [6.4. (Optional) Hardened Profiles](/portage_setup/#64-optional-hardened-profiles), you can easily "add" SELinux features with a simple switch to [duxsco:hardened-systemd-merged-usr-selinux](https://github.com/duxsco/gentoo-installation/tree/main/overlay/duxsco/profiles/hardened-systemd-merged-usr-selinux):

    ```shell
    eselect profile set "duxsco:hardened-systemd-merged-usr-selinux"
    ```

=== "default/linux/amd64/17.1/systemd/merged-usr"
    If you stayed with the profile that came with the stage3 tarball which is most likely "default/linux/amd64/17.1/systemd/merged-usr" you can select the SELinux profile with:

    ```shell
    eselect profile set --force "default/linux/amd64/17.1/systemd/selinux/merged-usr"
    ```

These commands are more or less required irrespective of the SELinux profile in use:

```shell
# (Recommended) Use the most recent SELinux policies
echo 'sec-policy/* ~amd64' >> /etc/portage/package.accept_keywords/main && \

# (Optional) To get a nice looking html site in /usr/share/doc/selinux-base-<VERSION>/mcs/html:
echo 'sec-policy/selinux-base doc' >> /etc/portage/package.use/main && \

# Definitely required:
FEATURES="-selinux" emerge --oneshot selinux-base && \

echo -e "\e[1;32mSUCCESS\e[0m"
```

Configure SELinux:

```shell hl_lines="1"
rsync -a /etc/selinux/config /etc/selinux/._cfg0000_config && \
sed -i 's/^SELINUXTYPE=strict$/SELINUXTYPE=mcs/' /etc/selinux/._cfg0000_config && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Update packages:

```shell
FEATURES="-selinux -sesandbox" emerge --oneshot selinux-base && \
FEATURES="-selinux -sesandbox" emerge --oneshot selinux-dbus && \
FEATURES="-selinux -sesandbox" emerge --oneshot selinux-base-policy && \
emerge -atuDN @world
```

Enable auditd logging:

```shell
systemctl enable auditd.service && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Rebuild the [kernel with SELinux support](https://github.com/duxsco/gentoo-installation/blob/main/bin/portage_hook_kernel#L23-L26):

```shell
emerge -at --oneshot \
$(qlist -eI sys-kernel/gentoo-kernel-bin >/dev/null && echo sys-kernel/gentoo-kernel-bin) \
$(qlist -eI sys-kernel/gentoo-kernel >/dev/null && echo sys-kernel/gentoo-kernel) && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Reboot with **permissive kernel**.

Make sure that UBAC gets disabled:

```shell
bash -c '(
    cd /usr/share/selinux/mcs && \
    semodule -i base.pp -i $(ls *.pp | grep -v base.pp) && \
    echo -e "\e[1;32mSUCCESS\e[0m"
)'
```

## 14.2. Relabel

[Relabel the entire system](https://wiki.gentoo.org/wiki/SELinux/Installation#Relabel):

```shell
mkdir /mnt/gentoo && \
mount -o bind / /mnt/gentoo && \
setfiles -r /mnt/gentoo /etc/selinux/mcs/contexts/files/file_contexts /mnt/gentoo/{dev,home,proc,run,sys,tmp,boot/efi*,var/cache/binpkgs,var/cache/distfiles,var/db/repos/gentoo,var/tmp} && \
umount /mnt/gentoo && \
rlpkg -a -r && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

Make sure that nothing (except perhaps ".keep" files) is unlabeled:

```shell
export tmpdir="$(mktemp -d)" && \
mount --bind / "$tmpdir" && \
find "$tmpdir" -context system_u:object_r:unlabeled_t:s0 && \
umount "$tmpdir" && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

If "/proc" was listed by above codeblock you have to relabel to avoid a denial:

``` { .shell .no-copy }
❯ cat <<EOF | audit2allow
[   19.902620] audit: type=1400 audit(1663630933.439:3): avc:  denied  { mounton } for  pid=1062 comm="(auditd)" path="/run/systemd/unit-root/proc" dev="dm-3" ino=67581 scontext=system_u:system_r:init_t:s0 tcontext=system_u:object_r:unlabeled_t:s0 tclass=dir permissive=1
EOF


#============= init_t ==============
allow init_t unlabeled_t:dir mounton;

# Credits: grift :)
❯ export tmpdir="$(mktemp -d)" && mount --bind / "$tmpdir" && chcon system_u:object_r:proc_t:s0 "$tmpdir"/proc && umount "$tmpdir" && echo -e "\e[1;32mSUCCESS\e[0m"
```

In section [10. SSH Server (optional)](/ssh_server/), the SSH port has been changed to 50022. This needs to be considered for no SELinux denials to occur:

``` { .shell .no-copy }
❯ semanage port -l | grep -e ssh -e Port
SELinux Port Type              Proto    Port Number
ssh_port_t                     tcp      22
❯ semanage port -a -t ssh_port_t -p tcp 50022
❯ semanage port -l | grep -e ssh -e Port
SELinux Port Type              Proto    Port Number
ssh_port_t                     tcp      50022, 22
```

## 14.3. Users and services

Default "mcs" SELinux "login" and "user" settings:

``` { .shell .no-copy }
❯ semanage login -l

Login Name           SELinux User         MLS/MCS Range        Service

__default__          user_u               s0-s0                *
root                 root                 s0-s0:c0.c1023       *

❯ semanage user -l

                Labeling   MLS/       MLS/
SELinux User    Prefix     MCS Level  MCS Range                      SELinux Roles

root            sysadm     s0         s0-s0:c0.c1023                 staff_r sysadm_r
staff_u         staff      s0         s0-s0:c0.c1023                 staff_r sysadm_r
sysadm_u        sysadm     s0         s0-s0:c0.c1023                 sysadm_r
system_u        user       s0         s0-s0:c0.c1023                 system_r
unconfined_u    unconfined s0         s0-s0:c0.c1023                 unconfined_r
user_u          user       s0         s0                             user_r
```

Add the initial user to the [administration SELinux user](https://wiki.gentoo.org/wiki/SELinux/Installation#Define_the_administrator_accounts):

```shell
semanage login -a -s staff_u david && \
restorecon -RFv /home/david && \
bash -c 'echo "%wheel ALL=(ALL) TYPE=sysadm_t ROLE=sysadm_r ALL" | EDITOR="tee" visudo -f /etc/sudoers.d/wheel && \
echo -e "\e[1;32mSUCCESS\e[0m"'
```

Now, we should have:

``` { .shell .no-copy }
❯ semanage login -l

Login Name           SELinux User         MLS/MCS Range        Service

__default__          user_u               s0-s0                *
david                staff_u              s0-s0:c0.c1023       *
root                 root                 s0-s0:c0.c1023       *
```

Create "/var/lib/sepolgen/interface_info" for "audit2why -R" to work:

```shell
sepolgen-ifgen -i /usr/share/selinux/mcs/include/support/ && \
echo -e "\e[1;32mSUCCESS\e[0m"
```

## 14.4. SELinux policies

At this point, you can reboot into permissive mode again and use the [selinux-policy-creator.sh](https://github.com/duxsco/selinux-policy-creator) script.
