# Build stages
FROM nginx:alpine as build

RUN apk add --update \
    wget

ARG HUGO_VERSION="0.83.0"
RUN wget --quiet "https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_${HUGO_VERSION}_Linux-64bit.tar.gz" && \
    tar xzf hugo_${HUGO_VERSION}_Linux-64bit.tar.gz && \
    rm -r hugo_${HUGO_VERSION}_Linux-64bit.tar.gz && \
    mv hugo /usr/bin

COPY ./source/ /site
WORKDIR /site
RUN hugo

#Copy static files to Nginx
FROM nginx:alpine
COPY --from=build /site/public /usr/share/nginx/html

WORKDIR /usr/share/nginx/html

LABEL maintainer="Hugo Blanc <hugoblanc@fastmail.com>"