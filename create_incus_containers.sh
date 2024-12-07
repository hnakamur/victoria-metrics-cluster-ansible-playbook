#!/bin/sh
set -eu

if [ $# -ne 1 ]; then
  >&2 echo Usage: $0 project_name
  exit 2
fi

project_name="$1"
container_names="vicmet01 vicmet02"

project_ssh_dir=ssh
root_password="${ROOT_PASSWORD:-proxy-santos-hatch-plotting}"

ssh_known_hosts="$project_ssh_dir/known_hosts"
ssh_config="$project_ssh_dir/config"
private_key="$project_ssh_dir/id_ed25519.$project_name"
public_key="${private_key}.pub"

create_container() {
  container_name="$1"
  
  if incus info "$container_name" 2>/dev/null >/dev/null; then
    return
  fi

  incus launch images:ubuntu/24.04/cloud "$container_name" -c user.user-data="#cloud-config
timezone: Asia/Tokyo
" -c user.network-config="#cloud-config
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
      dhcp-identifier: mac
      link-local: [ ipv4 ]"

  incus exec "$container_name" -- apt update
  incus exec "$container_name" -- apt -y install openssh-server
  incus exec "$container_name" -- mkdir -p -m 700 /root/.ssh
  echo "root:$root_password" | incus exec "$container_name" -- chpasswd root
  incus file push --uid 0 --gid 0 "$public_key" "$container_name/root/.ssh/authorized_keys"
  incus exec "$container_name" -- chmod 600 /root/.ssh/authorized_keys
  
  ipv4_addr=$(incus list -c 4 -f csv "^${container_name}\$" | cut -d ' ' -f 1)
  
  if [ -f "$ssh_config" ]; then
    sed -i "/^Host $container_name$/,/^$/d" "$ssh_config"
  fi
  
  cat <<EOF >> "$ssh_config"
Host $container_name
  Hostname $ipv4_addr
  User root
  ForwardAgent yes
  UserKnownHostsFile $ssh_known_hosts
  IdentityFile $private_key

EOF
}

create_ssh_known_hosts() {
  for container_name in $container_names; do
    ipv4_addr=$(incus list -c 4 -f csv "^${container_name}\$" | cut -d ' ' -f 1)
    ssh-keyscan "$ipv4_addr" 2> /dev/null
    escaped_addr=$(echo "$ipv4_addr" | sed 's/\./\\./g')
    ssh-keyscan "$ipv4_addr" 2> /dev/null | sed "s/^$escaped_addr /$container_name /"
  done > "$ssh_known_hosts"
}

if [ ! -f "$public_key" ]; then
  mkdir -p "$project_ssh_dir"
  ssh-keygen -t ed25519 -C "key for $project_name incus project" -N '' -f "$private_key"
fi

if ! incus project info "$project_name" 2>/dev/null >/dev/null; then
  incus project create "$project_name"
  incus profile show default --project default | incus profile edit --project "$project_name" default
fi

incus project switch "$project_name"

for container_name in $container_names; do
  create_container "$container_name"
done

create_ssh_known_hosts
