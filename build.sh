#!/bin/bash
set -euo pipefail

# 克隆代码仓库及指定子模块
git clone https://github.com/DrKLO/Telegram --recursive --filter blob:none

cd Telegram

# 关闭优化、混淆，只保留 arm64
sed -i 's/#-dontoptimize/-dontoptimize/' TMessagesProj/proguard-rules.pro
sed -i 's/#-dontobfuscate/-dontobfuscate/' TMessagesProj/proguard-rules.pro
sed -i 's/abiFilters "armeabi-v7a", "arm64-v8a", "x86", "x86_64"/abiFilters "arm64-v8a"/' TMessagesProj_App/build.gradle TMessagesProj_AppStandalone/build.gradle
sed -i 's/defaultConfig {/defaultConfig { ndk { abiFilters "arm64-v8a" }/' TMessagesProj/build.gradle

# 生成 Dockerfile
echo "==> Generating Dockerfile..."
cat << 'EOF' > Dockerfile
FROM gradle:8.13-jdk17

ENV ANDROID_CMDLINE_TOOLS_VERSION=15859902
ENV ANDROID_SDK_URL=https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_VERSION}_latest.zip

ENV ANDROID_HOME=/usr/local/android-sdk-linux

ENV ANDROID_API_LEVEL=android-36
ENV ANDROID_VERSION=36
ENV ANDROID_BUILD_TOOLS_VERSION=36.0.0

ENV ANDROID_NDK_VERSION=27.2.12479018
ENV ANDROID_NDK_HOME=${ANDROID_HOME}/ndk/${ANDROID_NDK_VERSION}

ENV PATH=${PATH}:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools
ENV PATH=${PATH}:${ANDROID_NDK_HOME}
ENV PATH=${PATH}:${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin

RUN mkdir -p "${ANDROID_HOME}/cmdline-tools" /home/gradle/.android && \
    cd /tmp && \
    curl -fL "${ANDROID_SDK_URL}" -o commandlinetools.zip && \
    unzip commandlinetools.zip && \
    mv cmdline-tools "${ANDROID_HOME}/cmdline-tools/latest" && \
    rm commandlinetools.zip

RUN yes | sdkmanager --sdk_root="${ANDROID_HOME}" --licenses
RUN sdkmanager \
    --sdk_root="${ANDROID_HOME}" \
    "build-tools;36.0.0" \
    "build-tools;${ANDROID_BUILD_TOOLS_VERSION}" \
    "platforms;android-${ANDROID_VERSION}" \
    "platform-tools" \
    "ndk;${ANDROID_NDK_VERSION}" \
    "cmake;3.22.1"

CMD mkdir -p /home/source/TMessagesProj/build/outputs/apk && \
    cp -R /home/source/. /home/gradle && \
    cd /home/gradle && \
    gradle --parallel \
        :TMessagesProj_AppStandalone:assembleAfatStandalone \
        :TMessagesProj_App:assembleAfatRelease && \
    cp -R /home/gradle/TMessagesProj_App/build/outputs/apk/. /home/source/TMessagesProj/build/outputs/apk && \
    cp -R /home/gradle/TMessagesProj_AppStandalone/build/outputs/apk/. /home/source/TMessagesProj/build/outputs/apk

EOF

# 构建并运行容器导出产物
echo "==> Building Docker image..."
docker build -f Dockerfile -t telegram-builder:latest .

echo "==> Running build inside Docker container..."
mkdir -p build/outputs

# 挂载当前目录至容器内部运行构建流程
docker run --rm \
    -v "$(pwd)":/home/source \
    telegram-builder:latest

echo "==> Build complete! Output APKs:"
ls -lh TMessagesProj/build/outputs/apk/
