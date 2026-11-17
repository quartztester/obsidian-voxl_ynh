#!/bin/bash

#=================================================
# COMMON VARIABLES AND CUSTOM HELPERS
#=================================================

# voxl ships no prebuilt binaries: only the source crate. It is built on the box
# during install; the crate is pinned by sha256 below.
voxl_version="0.3.5"
voxl_sha256="84763b5eeb371b86932896e93a91c874a6b48caaf31880d1e58e0a42ef927fa2"
# Bookworm's cargo cannot parse the crate's lock file (version 4); pin a newer toolchain.
rust_version="1.85.1"

ynh_obsidian_deploy() {
    # Settings added after the first release are missing when upgrading or restoring,
    # and the core leaves their variable empty during an upgrade: read it from the
    # settings and export it so the launcher template renders.
    resolution=$(ynh_app_setting_get --key=resolution || true)
    if ! [[ "$resolution" =~ ^[0-9]{3,4}x[0-9]{3,4}$ ]]; then
        resolution=1920x1080
        ynh_app_setting_set --key=resolution --value="$resolution"
    fi
    export resolution

    ynh_setup_source --dest_dir="$install_dir" "$@"
    # systemd's append: log target needs the directory to exist.
    mkdir -p "/var/log/$app"
    chown "$app:$app" "/var/log/$app"
    ynh_config_add --template="start.sh" --destination="$install_dir/start.sh"
    chmod 755 "$install_dir/start.sh" "$install_dir/obsidian"
    chown -R "$app:$app" "$install_dir"
}

ynh_obsidian_install_voxl() {
    local crate build_dir
    if [ -x "$install_dir/voxl" ] && "$install_dir/voxl" --version 2>/dev/null | grep -q "$voxl_version"; then
        return
    fi

    crate="/var/cache/$app/voxl.crate"
    mkdir -p "$(dirname "$crate")"
    curl -fsSL -o "$crate" \
        "https://static.crates.io/crates/voxl-server/voxl-server-$voxl_version.crate"
    if ! echo "$voxl_sha256  $crate" | sha256sum --check --status; then
        rm -f "$crate"
        echo "The voxl download does not match the pinned checksum" >&2
        exit 1
    fi

    # Build as root into a scratch dir, then hand the single binary to the install dir.
    build_dir="/tmp/voxl-build-$app"
    rm -rf "$build_dir"
    mkdir -p "$build_dir"
    tar xzf "$crate" -C "$build_dir"
    rm -f "$crate"

    # Stock cargo rejects the v4 lock file: install a pinned rustup toolchain.
    export RUSTUP_HOME="$build_dir/rustup" CARGO_HOME="$build_dir/cargo"
    curl -fsSL https://sh.rustup.rs -o "$build_dir/rustup-init"
    sh "$build_dir/rustup-init" --yes --profile minimal --default-toolchain "$rust_version" --no-modify-path
    export PATH="$CARGO_HOME/bin:$PATH"

    (cd "$build_dir/voxl-server-$voxl_version" && cargo build --release --locked)
    install -m 755 "$build_dir/voxl-server-$voxl_version/target/release/voxl" "$install_dir/voxl"
    chown "$app:$app" "$install_dir/voxl"
    rm -rf "$build_dir"
}

ynh_obsidian_prepare_vault() {
    install -d -o "$app" -g "$app" -m 755 "$data_dir/vault"
    # Drag-and-drop uploads land here, written by the app user: nginx no longer touches the vault.
    install -d -o "$app" -g "$app" -m 755 "$data_dir/vault/attachments"
}
