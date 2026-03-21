#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# OpenTune – Codespace bootstrap
# Installs: Java 21 (Temurin), Android SDK, Android build-tools
# Mirrors the CI setup in .github/workflows/debug.yml
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  OpenTune Codespace Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 1. System packages ─────────────────────────────────────────────
echo "→ Installing system dependencies..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
    wget curl unzip git \
    libc6-i386 lib32z1 lib32stdc++6 \
    2>/dev/null

# ── 2. Java 21 Temurin (matches CI: actions/setup-java temurin 21) ─
TEMURIN_VERSION="21.0.7+6"
TEMURIN_VERSION_SHORT="21"
TEMURIN_DIR="/opt/java/${TEMURIN_VERSION_SHORT}"

if [ ! -d "$TEMURIN_DIR" ]; then
    echo "→ Installing Java 21 Temurin..."
    ARCH=$(dpkg --print-architecture)   # amd64 or arm64
    case "$ARCH" in
        amd64)  JDK_ARCH="x64" ;;
        arm64)  JDK_ARCH="aarch64" ;;
        *)      JDK_ARCH="x64" ;;
    esac
    TEMURIN_URL="https://api.adoptium.net/v3/binary/latest/${TEMURIN_VERSION_SHORT}/ga/linux/${JDK_ARCH}/jdk/hotspot/normal/eclipse"
    TMP_TAR=$(mktemp /tmp/jdk21.XXXXXX.tar.gz)
    wget -q --show-progress "$TEMURIN_URL" -O "$TMP_TAR"
    sudo mkdir -p "$TEMURIN_DIR"
    sudo tar -xzf "$TMP_TAR" -C "$TEMURIN_DIR" --strip-components=1
    rm "$TMP_TAR"
    echo "  Java 21 Temurin installed at $TEMURIN_DIR"
else
    echo "  Java 21 Temurin already present, skipping."
fi

export JAVA_HOME="$TEMURIN_DIR"
export PATH="$JAVA_HOME/bin:$PATH"
echo "  Java version: $(java -version 2>&1 | head -1)"

# ── 3. Android command-line tools ─────────────────────────────────
ANDROID_HOME=/opt/android-sdk
CMDLINE_TOOLS_VERSION="11076708"   # cmdline-tools 12.0
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip"

if [ ! -d "$ANDROID_HOME/cmdline-tools/latest" ]; then
    echo "→ Downloading Android command-line tools..."
    sudo mkdir -p "$ANDROID_HOME/cmdline-tools"
    TMP_ZIP=$(mktemp /tmp/cmdtools.XXXXXX.zip)
    wget -q --show-progress "$CMDLINE_TOOLS_URL" -O "$TMP_ZIP"
    sudo unzip -q "$TMP_ZIP" -d "$ANDROID_HOME/cmdline-tools"
    sudo mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" \
            "$ANDROID_HOME/cmdline-tools/latest" 2>/dev/null || true
    rm "$TMP_ZIP"
    echo "  command-line tools installed."
else
    echo "  command-line tools already present, skipping."
fi

export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/34.0.0:$PATH"

# ── 4. Accept licences & install SDK components ───────────────────
echo "→ Accepting Android licences..."
yes | sudo "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --licenses \
    --sdk_root="$ANDROID_HOME" > /dev/null 2>&1 || true

echo "→ Installing Android SDK components (this may take a few minutes)..."
sudo "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" \
    --sdk_root="$ANDROID_HOME" \
    "platform-tools" \
    "build-tools;34.0.0" \
    "platforms;android-34" \
    "platforms;android-35" \
    2>&1 | grep -v "^Warn" | grep -v "^\[="

# ── 5. Make SDK writable by Codespace user ────────────────────────
sudo chown -R "$(whoami):$(whoami)" "$ANDROID_HOME" 2>/dev/null || \
sudo chmod -R a+rw "$ANDROID_HOME" 2>/dev/null || true

# ── 6. Persist env vars across terminal sessions ──────────────────
PROFILE_SNIPPET='
# ── OpenTune dev environment ──────────────────────────────────────
export JAVA_HOME=/opt/java/21
export ANDROID_HOME=/opt/android-sdk
export ANDROID_SDK_ROOT=/opt/android-sdk
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/34.0.0:$PATH"
'
for RC_FILE in ~/.bashrc ~/.zshrc; do
    if [ -f "$RC_FILE" ] && ! grep -q "ANDROID_HOME" "$RC_FILE"; then
        echo "$PROFILE_SNIPPET" >> "$RC_FILE"
    fi
done

# ── 7. gradlew permissions ────────────────────────────────────────
if [ -f "./gradlew" ]; then
    chmod +x ./gradlew
    echo "  gradlew marked as executable."
fi

# ── 8. Debug keystore (mirrors CI signing step) ───────────────────
KEYSTORE_DIR="$HOME/.android"
KEYSTORE_FILE="$KEYSTORE_DIR/debug.keystore"
if [ ! -f "$KEYSTORE_FILE" ]; then
    echo "→ Generating local debug keystore..."
    mkdir -p "$KEYSTORE_DIR"
    keytool -genkey -v \
        -keystore "$KEYSTORE_FILE" \
        -storepass android \
        -keypass android \
        -alias androiddebugkey \
        -keyalg RSA -keysize 2048 -validity 10000 \
        -dname "C=US, O=Android, CN=Android Debug" \
        2>/dev/null
    echo "  Debug keystore created at $KEYSTORE_FILE"
fi

# Export the same env vars the CI workflow uses
{
    echo "MUSIC_DEBUG_KEYSTORE_FILE=$KEYSTORE_FILE"
    echo "MUSIC_DEBUG_SIGNING_STORE_PASSWORD=android"
    echo "MUSIC_DEBUG_SIGNING_KEY_PASSWORD=android"
    echo "MUSIC_DEBUG_SIGNING_KEY_ALIAS=androiddebugkey"
} >> ~/.bashrc
{
    echo "export MUSIC_DEBUG_KEYSTORE_FILE=$KEYSTORE_FILE"
    echo "export MUSIC_DEBUG_SIGNING_STORE_PASSWORD=android"
    echo "export MUSIC_DEBUG_SIGNING_KEY_PASSWORD=android"
    echo "export MUSIC_DEBUG_SIGNING_KEY_ALIAS=androiddebugkey"
} >> ~/.zshrc 2>/dev/null || true

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅  Environment ready!"
echo ""
echo "  Build commands (mirroring CI):"
echo "    ./gradlew assembleDebug --build-cache --configuration-cache --parallel"
echo "    ./gradlew clean assembleDebug"
echo "    ./gradlew tasks"
echo ""
echo "  Output APK:"
echo "    app/build/outputs/apk/debug/*.apk"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
