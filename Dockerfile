FROM ubuntu:latest
LABEL maintainer="Hugo Blanc <hugoblanc@fastmail.com>"

ENV HUGO_VERSION="0.83.0"
ENV GITHUB_USERNAME="eze-kiel"
ENV GITHUB_REPOSITORY="tries"

USER root

RUN apt update >/dev/null 2>&1 && \
    apt install -y wget git

RUN wget --quiet https://github.com/spf13/hugo/releases/download/v${HUGO_VERSION}/hugo_${HUGO_VERSION}_Linux-64bit.tar.gz

RUN tar -xf hugo_${HUGO_VERSION}_Linux-64bit.tar.gz

RUN chmod +x hugo && \
    mv hugo /usr/local/bin/hugo && \
    rm -rf hugo_${HUGO_VERSION}_Linux-64bit.tar.gz

RUN git clone https://github.com/${GITHUB_USERNAME}/${GITHUB_REPOSITORY}.git

WORKDIR ${GITHUB_REPOSITORY}/source

ENTRYPOINT [ "hugo", "server", "--bind", "0.0.0.0" ]

EXPOSE 1313