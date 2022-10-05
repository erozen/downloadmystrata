FROM alpine:latest

# Copy config.sample, edit the contents, and bind-mount it in to /config

RUN apk update && apk add --no-cache --update --upgrade coreutils curl file rclone ca-certificates tzdata jq mailx ssmtp && rm -rf /var/cache/apk/* \
    && addgroup -g 1000 rclone && adduser -u 1000 -Ds /bin/sh -h /config -G rclone rclone \
    && mkdir /remote && chown rclone:rclone /remote \
    && ln -sf /config/rclone /root/.rclone.conf   ## TODO - is /root/.rclone.conf still required?

ADD run.sh /run.sh
ADD strata-get.sh /strata-get.sh

WORKDIR /remote

USER rclone

ENTRYPOINT ["/run.sh"]

