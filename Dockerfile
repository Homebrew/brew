ARG version=22.04
# version is passed through by Docker.
# shellcheck disable=SC2154
FROM ubuntu:"${version}"
ARG DEBIAN_FRONTEND=noninteractive

# Deterministic UID (first user). Helps with docker build cache
ENV USER_ID=1000
# Delete the default ubuntu user & group UID=1000 GID=1000 in Ubuntu 23.04+
# that conflicts with the linuxbrew user
RUN touch /var/mail/ubuntu && chown ubuntu /var/mail/ubuntu && userdel -r ubuntu; true

# We don't want to manually pin versions, happy to use whatever
# Ubuntu thinks is best.
# hadolint ignore=DL3008

# `gh` installation taken from https://github.com/cli/cli/blob/trunk/docs/install_linux.md#debian-ubuntu-linux-raspberry-pi-os-apt
# /etc/lsb-release is checked inside the container and sets DISTRIB_RELEASE.
# We need `[` instead of `[[` because the shell is `/bin/sh`.
# `:` below is a no-op that works around a ShellCheck parsing error.
# shellcheck disable=SC1091,SC2154,SC2292
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
  : \
  && retry() { bash -c 'for i in {1..5}; do "$@" && exit 0; [[ $((i)) -lt 5 ]] && sleep $((i)); done; exit 1' -- "$@"; } \
  && retry apt-get update --error-on=any \
  && apt-get install -y --no-install-recommends software-properties-common gnupg-agent \
  && if [ "$(uname -m)" != aarch64 ]; then retry add-apt-repository -y ppa:git-core/ppa; fi \
  && retry apt-get update --error-on=any \
  && apt-get install -y --no-install-recommends \
  acl \
  bzip2 \
  ca-certificates \
  curl \
  file \
  fonts-dejavu-core \
  g++ \
  gawk \
  git \
  gpg \
  less \
  locales \
  make \
  netbase \
  openssh-client \
  patch \
  skopeo \
  sudo \
  unzip \
  uuid-runtime \
  tzdata \
  jq \
  && if [ "$(. /etc/lsb-release; echo "${DISTRIB_RELEASE}" | cut -d. -f1)" -eq 22 ]; then apt-get install -y --no-install-recommends g++-12; fi \
  && mkdir -p /etc/apt/keyrings \
  && chmod 0755 /etc /etc/apt /etc/apt/keyrings \
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null \
  && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list >/dev/null \
  && apt-get update \
  && apt-get install -y --no-install-recommends gh \
  && apt-get remove --purge -y software-properties-common \
  && apt-get autoremove --purge -y \
  && sed -i -E 's/^(USERGROUPS_ENAB\s+)yes$/\1no/' /etc/login.defs \
  && localedef -i en_US -f UTF-8 en_US.UTF-8 \
  && useradd -u "${USER_ID}" --create-home --shell /bin/bash --user-group linuxbrew \
  && echo 'linuxbrew ALL=(ALL) NOPASSWD:ALL' >>/etc/sudoers \
  && su - linuxbrew -c 'mkdir ~/.linuxbrew'

USER linuxbrew
ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}" \
  HOMEBREW_PREFIX=/home/linuxbrew/.linuxbrew \
  HOMEBREW_CELLAR=/home/linuxbrew/.linuxbrew/Cellar \
  HOMEBREW_REPOSITORY=/home/linuxbrew/.linuxbrew/Homebrew \
  XDG_CACHE_HOME=/home/linuxbrew/.cache
WORKDIR /home/linuxbrew

ARG HOMEBREW_CORE_REVISION=origin/main

RUN --mount=type=cache,target=/tmp/homebrew-core,uid="${USER_ID}",sharing=locked \
  # Clone the homebrew-core repo into /tmp/homebrew-core or fetch latest changes if it exists
  git clone https://github.com/homebrew/homebrew-core /tmp/homebrew-core || git -C /tmp/homebrew-core fetch origin main \
  && git -C /tmp/homebrew-core checkout --force -B main "${HOMEBREW_CORE_REVISION:-origin/main}" \
  && mkdir -p /home/linuxbrew/.linuxbrew/Homebrew/Library/Taps/homebrew/homebrew-core \
  && cp -r /tmp/homebrew-core /home/linuxbrew/.linuxbrew/Homebrew/Library/Taps/homebrew/

COPY --chown=linuxbrew:linuxbrew . /home/linuxbrew/.linuxbrew/Homebrew

RUN --mount=type=cache,target=/home/linuxbrew/.cache,uid="${USER_ID}" \
  --mount=type=cache,target=/home/linuxbrew/.bundle,uid="${USER_ID}" \
  mkdir -p \
  .linuxbrew/bin \
  .linuxbrew/etc \
  .linuxbrew/include \
  .linuxbrew/lib \
  .linuxbrew/opt \
  .linuxbrew/sbin \
  .linuxbrew/share \
  .linuxbrew/var/homebrew/linked \
  .linuxbrew/Cellar \
  && ln -s ../Homebrew/bin/brew .linuxbrew/bin/brew \
  && git -C .linuxbrew/Homebrew remote set-url origin https://github.com/Homebrew/brew \
  && git -C .linuxbrew/Homebrew fetch origin \
  && HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_AUTO_UPDATE=1 brew tap --force homebrew/core \
  && brew install-bundler-gems --groups=all \
  && brew cleanup \
  && { git -C .linuxbrew/Homebrew config --unset gc.auto; true; } \
  && { git -C .linuxbrew/Homebrew config --unset homebrew.devcmdrun; true; } \
  && touch .linuxbrew/.homebrewdocker
