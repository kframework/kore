FROM ubuntu:bionic

ENV TZ=America/Chicago
RUN    ln --symbolic --no-dereference --force /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone

RUN    apt update                                                                \
    && apt upgrade --yes                                                         \
    && apt install --yes                                                         \
           autoconf bison clang-6.0 cmake curl flex gcc git jq libboost-test-dev \
           libffi-dev libgmp-dev libjemalloc-dev libmpfr-dev libtool             \
           libyaml-cpp-dev libz3-dev make maven opam openjdk-8-jdk pandoc        \
           pkg-config python3 python-pygments python-recommonmark python-sphinx  \
           time zlib1g-dev

RUN    git clone 'https://github.com/z3prover/z3' --branch=z3-4.6.0 \
    && cd z3                                                        \
    && python scripts/mk_make.py                                    \
    && cd build                                                     \
    && make -j8                                                     \
    && make install                                                 \
    && cd ../..                                                     \
    && rm -rf z3

RUN update-alternatives --set java /usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java

ARG USER_ID=1000
ARG GROUP_ID=1000
RUN    groupadd --gid $GROUP_ID user                                        \
    && useradd --create-home --uid $USER_ID --shell /bin/sh --gid user user

ADD scripts/install-stack.sh /home/user/.install-stack/
RUN /home/user/.install-stack/install-stack.sh

USER $USER_ID:$GROUP_ID

RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain 1.28.0

ENV LC_ALL=C.UTF-8

RUN    cd /home/user \
    && curl https://github.com/ndmitchell/hlint/releases/download/v3.1/hlint-3.1-x86_64-linux.tar.gz -sSfL | tar xzf - \
    && mv hlint-3.1 hlint
ENV PATH=/home/user/hlint:$PATH

RUN    cd /home/user \
    && curl https://github.com/jaspervdj/stylish-haskell/releases/download/v0.11.0.0/stylish-haskell-v0.11.0.0-linux-x86_64.tar.gz -sSfL | tar xzf - \
    && mv stylish-haskell-v0.11.0.0-linux-x86_64 stylish-haskell
ENV PATH=/home/user/stylish-haskell:$PATH

ADD --chown=user:user stack.yaml /home/user/.tmp-haskell/
ADD --chown=user:user kore/package.yaml /home/user/.tmp-haskell/kore/
RUN    cd /home/user/.tmp-haskell \
    && stack build --only-snapshot --test --bench --haddock
