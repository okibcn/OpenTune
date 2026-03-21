#!/bin/bash
# ─────────────────────────────────────────────────────────────────
# OpenTune – Codespace bootstrap  (runs via postCreateCommand)
# Base image: mcr.microsoft.com/devcontainers/universal:2
# Java 21 Temurin is pre-installed; we only add the Android SDK.
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  OpenTune Codespace Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 1. Locate Java 21 (pre-installed in universal:2) ──────────────
echo "→ Locating Java 21..."
JAVA_HOME_DETECTED=""

# universal:2 puts JDKs under SDKMAN or /usr/lib/jvm
for candidate in \
    "/opt/java/21" \
    "/usr/lib/jvm/temurin-21-amd64" \
    "/usr/lib/jvm/java-21-amazon-corretto" \
    "/usr/local/lib/jvm/temurin-21"
do
    if [ -x "$candidate/bin/java" ]; then
        JAVA_HOME_DETECTED="$candidate"
        break
    fi
done

# Try SDKMAN glob
if [ -z "$JAVA_HOME_DETECTED" ]; then
    for path in /usr/local/sdkman/candidates/java/21*/; do
        if [ -x "${path}bin/java" ]; then
            JAVA_HOME_DETECTED="${path%/}"
            break
        fi
    done
fi

# Fall back to update-alternatives
if [ -z "$JAVA_HOME_DETECTED" ]; then
    JAVA_BIN=$(update-alternatives --list java 2>/dev/null \
        | grep -E 'java-21|temurin-21|jdk-21' | head -1 || true)
    if [ -n "$JAVA_BIN" ] && [ -x "$JAVA_BIN" ]; then
        JAVA_HOME_DETECTED="$(dirname "$(dirname "$JAVA_BIN")")"
    fi
fi

if [ -z "$JAVA_HOME_DETECTED" ]; then
    echo "⚠  Java 21 not found — installing Temurin 21 from Adoptium..."
    ARCH=$(dpkg --print-architecture 2>/dev/null || echo "amd64")
    [ "$ARCH" = "amd64" ] && JDK_ARCH="x64" || JDK_ARCH="aarch64"
    TEMURIN_URL="https://api.adoptium.net/v3/binary/latest/21/ga/linux/${JDK_ARCH}/jdk/hotspot/normal/eclipse"
    TMP_TAR=$(mktemp /tmp/jdk21.XXXXXX.tar.gz)
    wget -q "$TEMURIN_URL" -O "$TMP_TAR"
    mkdir -p /opt/java/21
    tar -xzf "$TMP_TAR" -C /opt/java/21 --strip-components=1
    rm "$TMP_TAR"
    JAVA_HOME_DETECTED="/opt/java/21"
fi

# Ensure /opt/java/21 always resolves
if [ "$JAVA_HOME_DETECTED" != "/opt/java/21" ]; then
    mkdir -p /opt/java
    ln -sfn "$JAVA_HOME_DETECTED" /opt/java/21
fi

export JAVA_HOME=/opt/java/21
export PATH="$JAVA_HOME/bin:$PATH"
echo "  Java: $(java -version 2>&1 | head -1)"

# ── 2. Android command-line tools ─────────────────────────────────
ANDROID_HOME=/opt/android-sdk
CMDLINE_TOOLS_VERSION="11076708"
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip"

if [ ! -d "$ANDROID_HOME/cmdline-tools/latest" ]; then
    echo "→ Downloading Android command-line tools..."
    sudo mkdir -p "$ANDROID_HOME/cmdline-tools"
    TMP_ZIP=$(mktemp /tmp/cmdtools.XXXXXX.zip)
    wget -q "$CMDLINE_TOOLS_URL" -O "$TMP_ZIP"
    sudo unzip -q "$TMP_ZIP" -d "$ANDROID_HOME/cmdline-tools"
    sudo mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" \
            "$ANDROID_HOME/cmdline-tools/latest"
    rm "$TMP_ZIP"
    echo "  Command-line tools installed."
else
    echo "  Command-line tools already present, skipping."
fi

export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/34.0.0:$PATH"

# ── 3. Accept licences & install SDK components ───────────────────
echo "→ Accepting Android licences..."
yes | sudo "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" \
    --sdk_root="$ANDROID_HOME" --licenses > /dev/null 2>&1 || true

echo "→ Installing Android SDK components..."
sudo "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" \
    --sdk_root="$ANDROID_HOME" \
    "platform-tools" \
    "build-tools;34.0.0" \
    "platforms;android-34" \
    "platforms;android-35" \
    2>&1 | grep -v "^Warn" | grep -v "^\[="

# ── 4. Fix ownership so the codespace user can write ──────────────
sudo chown -R "$(id -un):$(id -gn)" "$ANDROID_HOME" 2>/dev/null || \
sudo chmod -R a+rw "$ANDROID_HOME" 2>/dev/null || true

# ── 5. Persist env vars across terminal sessions ──────────────────
PROFILE_BLOCK='
# ── OpenTune Android dev ──────────────────────────────────────────
export JAVA_HOME=/opt/java/21
export ANDROID_HOME=/opt/android-sdk
export ANDROID_SDK_ROOT=/opt/android-sdk
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/34.0.0:$PATH"
'
for RC in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$RC" ] && ! grep -q "ANDROID_HOME" "$RC" && printf '%s' "$PROFILE_BLOCK" >> "$RC"
done

# ── 6. gradlew permissions ────────────────────────────────────────
if [ -f "./gradlew" ]; then
    chmod +x ./gradlew
    echo "  gradlew marked as executable."
fi

# ── 7. Debug keystore (mirrors CI signing step) ───────────────────
KEYSTORE_DIR="$HOME/.android"
KEYSTORE_FILE="$KEYSTORE_DIR/debug.keystore"
if [ ! -f "$KEYSTORE_FILE" ]; then
    echo "→ Generating local debug keystore..."
    mkdir -p "$KEYSTORE_DIR"
    "$JAVA_HOME/bin/keytool" -genkey -v \
        -keystore "$KEYSTORE_FILE" \
        -storepass android -keypass android \
        -alias androiddebugkey \
        -keyalg RSA -keysize 2048 -validity 10000 \
        -dname "C=US, O=Android, CN=Android Debug" > /dev/null 2>&1
    echo "  Debug keystore created."
fi

SIGNING_BLOCK="
export MUSIC_DEBUG_KEYSTORE_FILE=$KEYSTORE_FILE
export MUSIC_DEBUG_SIGNING_STORE_PASSWORD=android
export MUSIC_DEBUG_SIGNING_KEY_PASSWORD=android
export MUSIC_DEBUG_SIGNING_KEY_ALIAS=androiddebugkey
"
for RC in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$RC" ] && ! grep -q "MUSIC_DEBUG_KEYSTORE_FILE" "$RC" && printf '%s' "$SIGNING_BLOCK" >> "$RC"
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅  Environment ready!"
echo ""
echo "  Build:"
echo "    ./gradlew assembleDebug --build-cache --configuration-cache --parallel"
echo "  Output: app/build/outputs/apk/debug/*.apk"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
