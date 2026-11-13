#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

By default removes only what is unused: stopped containers, images not used
by a running container, build cache, unused networks, and volumes not used by
any container. Volumes of stopped containers are kept, so a stopped stack
keeps its data. Exactly the volumes listed before confirmation are deleted.

  -a, --all            Full reset: also stop and delete running containers,
                       so ALL images and volumes go too
  -k, --keep-volumes   Don't delete volumes
  -n, --dry-run        Only show what exists and which volumes would go
  -y, --yes            Don't ask for confirmation
  -h, --help           Show this help
EOF
}

all=0
dry_run=0
keep_volumes=0
assume_yes=0

while [[ $# -gt 0 ]]; do
    case "$1" in
    -a | --all) all=1 ;;
    -n | --dry-run) dry_run=1 ;;
    -k | --keep-volumes) keep_volumes=1 ;;
    -y | --yes) assume_yes=1 ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        echo "Unknown option: $1" >&2
        usage >&2
        exit 2
        ;;
    esac
    shift
done

if [[ -t 1 ]]; then
    step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
else
    step() { printf '\n==> %s\n' "$*"; }
fi

failed=0
# Run a cleanup step; on failure warn and carry on with the rest.
run() {
    "$@" || {
        echo "warning: '$*' failed, continuing" >&2
        failed=1
    }
}

# Volumes to delete: all of them with --all, otherwise those not mounted by
# any container, running or stopped.
doomed_volumes() {
    local all_vols containers in_use=""
    all_vols=$(docker volume ls -q)
    if ((! all)); then
        containers=$(docker ps -a -q)
        if [[ -n "$containers" ]]; then
            # shellcheck disable=SC2086 # split IDs into arguments
            in_use=$(docker inspect --format \
                '{{range .Mounts}}{{if eq .Type "volume"}}{{println .Name}}{{end}}{{end}}' \
                $containers)
        fi
    fi
    comm -23 <(sort -u <<<"$all_vols") <(sort -u <<<"$in_use") | sed '/^$/d'
}

if ! docker info >/dev/null 2>&1; then
    echo "Cannot talk to the Docker daemon (is it running? are you in the docker group?)" >&2
    exit 1
fi

step "Containers (docker ps -a)"
docker ps -a

step "Disk usage before (docker system df)"
docker system df

if ((keep_volumes)); then
    volumes=""
else
    volumes=$(doomed_volumes)
fi
vols_arr=()
if [[ -n "$volumes" ]]; then
    mapfile -t vols_arr <<<"$volumes"
fi

if ((dry_run)); then
    step "Detailed usage (docker system df -v)"
    docker system df -v
    step "Volumes that would be deleted"
    echo "${volumes:-(none)}"
    echo
    echo "Dry run: nothing was deleted."
    exit 0
fi

if ((! assume_yes)); then
    if [[ ! -t 0 ]]; then
        echo "No terminal to ask for confirmation; pass -y to run non-interactively." >&2
        exit 1
    fi
    echo
    if ((all)); then
        echo "This will stop and delete ALL containers, ALL images and ALL build cache."
    else
        echo "This will delete stopped containers, unused images, build cache and unused networks."
    fi
    if [[ -n "$volumes" ]]; then
        echo "These volumes will be deleted. Their data cannot be recovered:"
        printf '  %s\n' "${vols_arr[@]}"
    else
        echo "No volumes will be deleted."
    fi
    answer=""
    read -r -p "Type 'yes' to continue: " answer || true
    [[ "$answer" == "yes" ]] || {
        echo "Aborted."
        exit 1
    }
fi

if ((all)); then
    step "Force-removing all containers (docker rm -f)"
    ids=$(docker ps -a -q)
    if [[ -n "$ids" ]]; then
        mapfile -t ids_arr <<<"$ids"
        # Containers started with --rm may vanish on their own mid-way.
        docker rm -f "${ids_arr[@]}" || true
        left=$(docker ps -a -q)
        if [[ -n "$left" ]]; then
            echo "warning: some containers are still there, continuing:" >&2
            docker ps -a >&2
            failed=1
        fi
    else
        echo "No containers."
    fi
else
    step "Removing stopped containers (docker container prune -f)"
    run docker container prune -f
fi

step "Removing unused images (docker image prune -a -f)"
run docker image prune -a -f

step "Removing build cache (docker builder prune -a -f)"
run docker builder prune -a -f

step "Removing unused networks (docker network prune -f)"
run docker network prune -f

if ((${#vols_arr[@]})); then
    step "Removing the listed volumes (docker volume rm)"
    # A volume that got attached to a container meanwhile fails here and is kept.
    run docker volume rm "${vols_arr[@]}"
fi

step "Disk usage after (docker system df)"
docker system df

if ((failed)); then
    echo "Some steps failed; see warnings above." >&2
    exit 1
fi
