FROM centos:7 as build
COPY rke2.fc rke2.if rke2-selinux.spec rke2.sh rke2.te /

COPY scripts scripts
RUN scripts/build-setup

ARG TAG
ENV TAG $TAG

ARG COMMIT
ENV COMMIT $COMMIT

RUN scripts/build

FROM scratch
COPY --from=build dist /
