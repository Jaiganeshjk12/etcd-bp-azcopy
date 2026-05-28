# UBI image with azcopy + kando + etcdctl for the blueprint use.
# etcdctl & etcdutl is copied from the official etcd image.
# kando is copied from the kanister-tools image tag 0.119.0, which is the latest as of this commit.

ARG ETCD_SOURCE_IMAGE=quay.io/coreos/etcd:v3.6.11

FROM ghcr.io/kanisterio/kanister-tools:0.119.0 AS kando-src

FROM ${ETCD_SOURCE_IMAGE} AS etcd-src

FROM registry.access.redhat.com/ubi9/ubi-minimal:latest AS azcopy-builder

ARG AZCOPY_DOWNLOAD_URL=https://aka.ms/downloadazcopy-v10-linux

RUN microdnf update -y && \
    microdnf install -y curl-minimal tar gzip && \
    microdnf clean all

RUN curl -fsSL "${AZCOPY_DOWNLOAD_URL}" -o /tmp/azcopy.tgz && \
    tar -xzf /tmp/azcopy.tgz -C /tmp && \
    install -m 0755 /tmp/azcopy_linux_amd64_*/azcopy /azcopy && \
    rm -rf /tmp/azcopy.tgz /tmp/azcopy_linux_amd64_*

FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

RUN microdnf update -y && \
    microdnf install -y bash ca-certificates tar gzip && \
    microdnf clean all

COPY --from=azcopy-builder /azcopy /usr/local/bin/azcopy
COPY --from=kando-src /usr/local/bin/kando /usr/local/bin/kando
COPY --from=etcd-src /usr/local/bin/etcdctl /usr/local/bin/etcdctl
COPY --from=etcd-src /usr/local/bin/etcdutl /usr/local/bin/etcdutl

# Optional sanity check during build.
RUN /usr/local/bin/azcopy --version && \
    /usr/local/bin/kando --help >/dev/null || true

ENTRYPOINT ["/bin/bash", "-c"]
CMD ["azcopy --version && kando --help >/dev/null && etcdctl version && etcdutl version"]
